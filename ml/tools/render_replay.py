"""Prototype of "replay with fix": a short clip of a rep that triggered a coaching cue, showing the
athlete's tracked skeleton over the video and a ghost skeleton of the corrected pose (the athlete's own
pose with only the faulty body part moved, from formcoach.corrections), ending on a freeze-frame.

usage (from ml/, PYTHONPATH=.):
    python tools/render_replay.py thetis 4        # first 4 THETIS recordings that give a replay
    python tools/render_replay.py golf 2          # same for GolfDB
    python tools/render_replay.py contact         # contact sheet of every replay rendered so far

Output goes to /tmp/formcoach-replays/ (one MP4 per rep, plus replays.json listing them).
"""
from __future__ import annotations

import json
import math
import os
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from formcoach.corrections import EVENTS, corrected_pose  # noqa: E402
from formcoach.engine import Engine, load_profiles  # noqa: E402
from formcoach.scoring import target_for  # noqa: E402

OUT_DIR = Path("/tmp/formcoach-replays")
DATA = Path(__file__).resolve().parents[1] / "data"

BONES = [
    ("nose", "l_shoulder"), ("nose", "r_shoulder"), ("l_shoulder", "r_shoulder"),
    ("l_shoulder", "l_elbow"), ("l_elbow", "l_wrist"), ("r_shoulder", "r_elbow"), ("r_elbow", "r_wrist"),
    ("l_shoulder", "l_hip"), ("r_shoulder", "r_hip"), ("l_hip", "r_hip"),
    ("l_hip", "l_knee"), ("l_knee", "l_ankle"), ("r_hip", "r_knee"), ("r_knee", "r_ankle"),
]

OUT_FPS = 15.0
MARGIN_S = 0.4          # clip covers the rep plus this much either side
GHOST_HALF_S = 0.35     # ghost is visible within this distance of the key moment (fades in and out)
FREEZE_S = 1.6
MAX_H = 480
MIN_H = 360             # tiny sources (GolfDB 160x160) are upscaled so the drawing stays legible

# BGR
WHITE = (255, 255, 255)
GREEN = (80, 255, 80)
CYAN = (255, 230, 0)
CYAN_HI = (255, 255, 120)
YELLOW = (0, 225, 255)


# ---- helpers ---------------------------------------------------------------

def _font(size: int):
    for path in ("/System/Library/Fonts/Helvetica.ttc", "/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _wrap(draw: ImageDraw.ImageDraw, text: str, font, width: int) -> list[str]:
    lines, cur = [], ""
    for word in text.split():
        test = (cur + " " + word).strip()
        if draw.textlength(test, font=font) <= width or not cur:
            cur = test
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def _metric_for_cue(cue: str, specs: list) -> str | None:
    for spec in specs:
        if cue and cue in (spec.get("cue_low"), spec.get("cue_high")):
            return spec["id"]
    return None


def _event_time(rep, name: str):
    if name == "start":
        return rep.t_start
    if name == "end":
        return rep.t_end
    return rep.events.get(name)


def _nearest(samples: list, t: float):
    return min(samples, key=lambda s: abs(s.t - t))


# ---- planning: which reps get a replay, and what the fix is -----------------

def plan_replays(recording: dict, sport: str, handedness: str, view: str | None = None,
                 profiles: dict | None = None) -> tuple[list, list]:
    """Run the engine over the whole recording, keeping every Sample. Returns (samples, plans) with one
    plan per counted rep that has a cue whose metric has a correction rule."""
    profiles = profiles or load_profiles()
    eng = Engine(profiles, sport, handedness, view, recording.get("focus"))
    aspect = recording.get("aspect", 1.0)
    samples, reps = [], []
    for fr in recording["frames"]:
        n_before = len(eng.buf)
        last_before = eng.buf[-1] if eng.buf else None
        for ev in eng.push(fr["t"], fr["j"], aspect):
            if ev.kind == "rep":
                reps.append(ev.rep)
        if eng.buf and (eng.buf[-1] is not last_before or len(eng.buf) != n_before) and eng.buf[-1].t == fr["t"]:
            samples.append(eng.buf[-1])

    analyzer = eng.profile["analyzer"]
    specs = eng.profile["metrics"]
    plans = []
    for k, rep in enumerate(reps):
        rep_samples = [s for s in samples if rep.t_start - 1e-6 <= s.t <= rep.t_end + 1e-6]
        if not rep_samples:
            continue
        for cue in rep.cues:
            metric = _metric_for_cue(cue, specs)
            rule = EVENTS.get(analyzer, {}).get(metric) if metric else None
            if rule is None:
                continue
            spec = next(s for s in specs if s["id"] == metric)
            tgt = target_for(spec, rep.type)
            if tgt is None:
                continue
            ev_name, ref_name = rule
            t_key = _event_time(rep, ev_name)
            if t_key is None:
                continue
            key = _nearest(rep_samples, t_key)
            ref = None
            if ref_name is not None:
                t_ref = _event_time(rep, ref_name)
                if t_ref is None:
                    continue
                ref = _nearest(rep_samples, t_ref).pts
            fixed = corrected_pose(analyzer, metric, tgt[0], key.pts, ref, key.torso, eng.dom, rep.type)
            if fixed is None:
                continue
            moved = [n for n in fixed if n in key.pts and math.dist(fixed[n], key.pts[n]) > 0.002]
            if not moved:
                continue
            plans.append({
                "rep_index": k, "rep": rep, "cue": cue, "metric": metric, "target": tgt[0],
                "value": rep.metrics.get(metric), "event": ev_name, "ref_event": ref_name,
                "key": key, "fixed": fixed, "moved": moved,
                "delta": {n: (fixed[n][0] - key.pts[n][0], fixed[n][1] - key.pts[n][1]) for n in moved},
            })
            break   # one replay per rep: the worst correctable cue
    return samples, plans


# ---- drawing -----------------------------------------------------------------

class Canvas:
    def __init__(self, W: int, H: int, aspect: float, mirror_x: bool):
        self.W, self.H, self.aspect, self.mirror_x = W, H, aspect, mirror_x
        self.s = H / 480.0                       # line-width scale

    def px(self, p) -> tuple[int, int]:
        xn = p[0] / self.aspect
        if self.mirror_x:
            xn = 1.0 - xn
        return int(round(xn * self.W)), int(round(p[1] * self.H))

    def lw(self, v: float) -> int:
        return max(1, int(round(v * self.s)))


def draw_real(img, cv: Canvas, pts: dict):
    """The tracked skeleton: white bones with a dark outline, green joint dots."""
    P = {n: cv.px(p) for n, p in pts.items()}
    for a, b in BONES:
        if a in P and b in P:
            cv2.line(img, P[a], P[b], (20, 20, 20), cv.lw(6), cv2.LINE_AA)
    for a, b in BONES:
        if a in P and b in P:
            cv2.line(img, P[a], P[b], WHITE, cv.lw(3), cv2.LINE_AA)
    for n, q in P.items():
        cv2.circle(img, q, cv.lw(6), (20, 20, 20), -1, cv2.LINE_AA)
        cv2.circle(img, q, cv.lw(4.5), GREEN, -1, cv2.LINE_AA)


def _hot_bones(moved: list):
    return [(a, b) for a, b in BONES if a in moved or b in moved]


def draw_ghost(img, cv: Canvas, pts: dict, moved: list, alpha: float, part: str):
    """The corrected pose as a translucent cyan skeleton with a soft glow.
    part="body": the unchanged bones only, as a faint halo (drawn under the real skeleton, which
    coincides with them). part="fix": the bones touching a moved joint, bright with a glow (also drawn
    under the real skeleton so a small correction never hides it). part="joints": the moved joints,
    highlighted, drawn on top."""
    if alpha <= 0.01:
        return img
    P = {n: cv.px(p) for n, p in pts.items()}
    hot = _hot_bones(moved)
    bones = [b for b in BONES if b not in hot] if part == "body" else hot if part == "fix" else []
    glow = np.zeros_like(img)
    layer = np.zeros_like(img)
    mask = np.zeros(img.shape[:2], np.uint8)
    w_line = 9 if part == "body" else 5
    for a, b in bones:
        if a in P and b in P:
            cv2.line(glow, P[a], P[b], CYAN, cv.lw(18 if part == "fix" else 14), cv2.LINE_AA)
            cv2.line(layer, P[a], P[b], CYAN_HI if part == "fix" else CYAN, cv.lw(w_line), cv2.LINE_AA)
            cv2.line(mask, P[a], P[b], 255, cv.lw(w_line), cv2.LINE_AA)
    if part == "joints":
        for n in moved:
            if n in P:
                cv2.circle(glow, P[n], cv.lw(14), CYAN, -1, cv2.LINE_AA)
                cv2.circle(layer, P[n], cv.lw(6), CYAN_HI, -1, cv2.LINE_AA)
                cv2.circle(mask, P[n], cv.lw(6), 255, -1, cv2.LINE_AA)
    k = 2 * cv.lw(10) + 1
    glow = cv2.GaussianBlur(glow, (k, k), 0)
    strength = 0.35 if part == "body" else 0.8
    out = cv2.addWeighted(img, 1.0, glow, strength * alpha, 0)
    m = (mask.astype(np.float32) / 255.0 * (0.45 if part == "body" else 0.8) * alpha)[..., None]
    out = (out.astype(np.float32) * (1 - m) + layer.astype(np.float32) * m).astype(np.uint8)
    if part == "joints":   # white rim around the moved joints so they read on any background
        rim = out.copy()
        for n in moved:
            if n in P:
                cv2.circle(rim, P[n], cv.lw(9), WHITE, cv.lw(2), cv2.LINE_AA)
        out = cv2.addWeighted(out, 1 - alpha, rim, alpha, 0)
    return out


def _arrow_pairs(real: dict, fixed: dict, moved: list):
    """Arrows real -> corrected. When the moved joints all shift together (head_lift, hip_sway...),
    one arrow from their centre says it better than a bundle of parallel ones."""
    deltas = [(fixed[n][0] - real[n][0], fixed[n][1] - real[n][1]) for n in moved]
    mx = sum(d[0] for d in deltas) / len(deltas)
    my = sum(d[1] for d in deltas) / len(deltas)
    size = math.hypot(mx, my)
    if len(moved) > 1 and size > 0 and all(math.hypot(d[0] - mx, d[1] - my) < 0.15 * size for d in deltas):
        cx = sum(real[n][0] for n in moved) / len(moved)
        cy = sum(real[n][1] for n in moved) / len(moved)
        return [((cx, cy), (cx + mx, cy + my))]
    return [(real[n], fixed[n]) for n in moved]


def draw_arrows(img, cv: Canvas, real: dict, fixed: dict, moved: list, alpha: float):
    if alpha <= 0.01:
        return img
    layer = img.copy()
    for pa, pb in _arrow_pairs(real, fixed, moved):
        a, b = cv.px(pa), cv.px(pb)
        L = math.dist(a, b)
        if L < 1:
            continue
        min_len = cv.lw(16)
        if L < min_len:   # small correction: keep the arrow readable, tip still on the corrected joint
            a = (int(round(b[0] - (b[0] - a[0]) * min_len / L)), int(round(b[1] - (b[1] - a[1]) * min_len / L)))
            L = min_len
        tip = min(0.45, cv.lw(12) / L)
        cv2.arrowedLine(layer, a, b, (20, 20, 20), cv.lw(6), cv2.LINE_AA, tipLength=tip)
        cv2.arrowedLine(layer, a, b, YELLOW, cv.lw(3), cv2.LINE_AA, tipLength=tip)
    return cv2.addWeighted(img, 1 - alpha, layer, alpha, 0)


def compose(img, cv: Canvas, real: dict, ghost: dict | None, moved: list, alpha: float,
            arrows: tuple | None = None, arrow_alpha: float = 0.0):
    """Ghost body halo, then the real skeleton, then the corrected limb and arrows on top."""
    if ghost is not None:
        img = draw_ghost(img, cv, ghost, moved, alpha, "body")
        img = draw_ghost(img, cv, ghost, moved, alpha, "fix")
    draw_real(img, cv, real)
    if ghost is not None:
        img = draw_ghost(img, cv, ghost, moved, alpha, "joints")
    if arrows is not None:
        img = draw_arrows(img, cv, arrows[0], arrows[1], moved, arrow_alpha)
    return img


class Caption:
    """Caption bar below the video: the cue text and the colour legend."""

    def __init__(self, cue: str, W: int, Hv: int):
        self.fs = max(12, int(Hv / 26))
        self.f_cue, self.f_sub = _font(self.fs), _font(max(10, int(self.fs * 0.8)))
        self.f_b = _font(int(self.fs * 1.05))
        self.pad = int(self.fs * 0.5)
        d = ImageDraw.Draw(Image.new("RGB", (8, 8)))
        self.lines = _wrap(d, cue, self.f_cue, W - 2 * self.pad)
        self.h = self.pad * 2 + len(self.lines) * int(self.fs * 1.2) + int(self.fs * 1.1)
        self.h += self.h % 2

    def apply(self, img, banner: str | None = None):
        Hv, W = img.shape[:2]
        pil = Image.new("RGB", (W, Hv + self.h), (18, 18, 22))
        pil.paste(Image.fromarray(cv2.cvtColor(img, cv2.COLOR_BGR2RGB)), (0, 0))
        d = ImageDraw.Draw(pil)
        fs, pad = self.fs, self.pad
        y = Hv + pad
        for ln in self.lines:
            d.text((pad, y), ln, font=self.f_cue, fill=(255, 255, 255))
            y += int(fs * 1.2)
        x = pad
        for txt, col in (("Your swing (", (190, 190, 190)), ("white", (255, 255, 255)),
                         (") vs the fix (", (190, 190, 190)), ("cyan", (0, 230, 255)), (")", (190, 190, 190))):
            d.text((x, y), txt, font=self.f_sub, fill=col)
            x += d.textlength(txt, font=self.f_sub)
        if banner:
            tw = d.textlength(banner, font=self.f_b)
            d.rounded_rectangle([pad, pad, pad + tw + 2 * pad, pad + int(fs * 1.7)], radius=pad, fill=(0, 140, 190))
            d.text((2 * pad, pad + int(fs * 0.3)), banner, font=self.f_b, fill=(255, 255, 255))
        return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


def _ghost_pose(cur: dict, plan: dict, at_key: bool) -> dict:
    """At the key moment the ghost is exactly the corrected pose; around it, the athlete's current pose
    with the moved joints offset by the same correction, so the ghost follows the motion."""
    if at_key:
        return dict(plan["fixed"])
    g = dict(cur)
    for n, (dx, dy) in plan["delta"].items():
        if n in g:
            g[n] = (g[n][0] + dx, g[n][1] + dy)
    return g


def _open_writer(path: str, size: tuple[int, int]):
    for cc in ("avc1", "mp4v"):
        w = cv2.VideoWriter(path, cv2.VideoWriter_fourcc(*cc), OUT_FPS, size)
        if w.isOpened():
            return w
        w.release()
    raise RuntimeError("no usable MP4 codec")


def _read_video(path: str):
    cap = cv2.VideoCapture(str(path))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    while True:
        ok, img = cap.read()
        if not ok:
            break
        frames.append(img)
    cap.release()
    if not frames:
        raise FileNotFoundError(path)
    return frames, fps


# ---- main entry point ------------------------------------------------------

def render_replay(recording: dict, video_path: str, out_path: str, sport: str, handedness: str,
                  view: str | None = None, mirror_x: bool = False) -> list[dict]:
    """Writes one MP4 per counted rep that has a correctable cue. With one such rep the clip goes to
    out_path; with several, to <out_path stem>_rep<k>.mp4. Recording time t maps to video frame
    round(t * video_fps) (held frames past the end of the video show its last frame).
    mirror_x: the recording's x was flipped relative to the video (THETIS), so flip it back to draw.
    Returns one dict per clip: path, cue, metric, key_frame (index of the key moment in the clip),
    n_frames."""
    samples, plans = plan_replays(recording, sport, handedness, view)
    if not plans:
        return []
    video, vfps = _read_video(video_path)
    h0, w0 = video[0].shape[:2]
    aspect = recording.get("aspect", w0 / h0)

    def frame_at(t: float, W: int, Hv: int):
        i = min(max(int(round(t * vfps)), 0), len(video) - 1)
        return cv2.resize(video[i], (W, Hv), interpolation=cv2.INTER_AREA if h0 > Hv else cv2.INTER_LINEAR)

    results = []
    out = Path(out_path)
    for plan in plans:
        # video area plus caption bar below it, at most MAX_H tall in all
        Hv = int(min(MAX_H, max(h0, MIN_H)))
        for _ in range(3):
            Hv -= Hv % 2
            W = int(round(w0 * Hv / h0))
            W -= W % 2
            cap = Caption(plan["cue"], W, Hv)
            if Hv + cap.h <= MAX_H:
                break
            Hv = MAX_H - cap.h
        cv = Canvas(W, Hv, aspect, mirror_x)

        path = out if len(plans) == 1 else out.with_name(f"{out.stem}_rep{plan['rep_index'] + 1}{out.suffix}")
        rep, key = plan["rep"], plan["key"]
        t0 = max(samples[0].t, rep.t_start - MARGIN_S)
        t1 = min(samples[-1].t, rep.t_end + MARGIN_S)
        times = [t0 + i / OUT_FPS for i in range(int((t1 - t0) * OUT_FPS) + 1)]
        # make sure one output frame lands exactly on the key moment
        ki = min(range(len(times)), key=lambda i: abs(times[i] - key.t))
        times[ki] = key.t
        writer = _open_writer(str(path), (W, Hv + cap.h))
        for i, t in enumerate(times):
            at_key = i == ki
            pts = key.pts if at_key else _nearest(samples, t).pts
            dt = abs(t - key.t)
            alpha = 0.5 * (1 + math.cos(math.pi * dt / GHOST_HALF_S)) if dt < GHOST_HALF_S else 0.0
            ghost = _ghost_pose(pts, plan, at_key) if alpha > 0.01 else None
            img = compose(frame_at(t, W, Hv), cv, pts, ghost, plan["moved"], alpha,
                          arrows=(pts, ghost) if ghost else None, arrow_alpha=max(0.0, alpha * 2 - 1))
            writer.write(cap.apply(img))
        # freeze-frame at the key moment, video dimmed so both skeletons stand out
        img = (frame_at(key.t, W, Hv).astype(np.float32) * 0.7).astype(np.uint8)
        img = compose(img, cv, key.pts, plan["fixed"], plan["moved"], 1.0, arrows=(key.pts, plan["fixed"]),
                      arrow_alpha=1.0)
        img = cap.apply(img, banner=f"The fix, at {plan['event'].replace('_', ' ')}")
        n_freeze = int(FREEZE_S * OUT_FPS)
        for _ in range(n_freeze):
            writer.write(img)
        writer.release()
        results.append({"path": str(path), "sport": sport, "cue": plan["cue"], "metric": plan["metric"],
                        "value": plan["value"], "target": plan["target"], "event": plan["event"],
                        "moved": plan["moved"], "key_frame": ki, "n_frames": len(times) + n_freeze,
                        "rep_type": rep.type})
    return results


# ---- CLI -----------------------------------------------------------------

def _thetis_video(name: str) -> Path | None:
    stem = name[len("thetis_"):]
    for folder in ("forehand_flat", "backhand", "flat_service"):
        p = DATA / "thetis" / folder / f"{stem}.avi"
        if p.exists():
            return p
    return None


def _manifest_path() -> Path:
    return OUT_DIR / "replays.json"


def _load_manifest() -> dict:
    try:
        return json.loads(_manifest_path().read_text())
    except (OSError, ValueError):
        return {}


def run(dataset: str, n: int):
    import datasets as ds
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = _load_manifest()
    done = 0
    if dataset == "thetis":
        source = ((name, rec, _thetis_video(name), True) for name, rec, _ in ds.thetis())
    elif dataset == "golf":
        source = ((name, rec, DATA / "golfdb" / "data" / "videos_160" / f"{name.split('_')[1]}.mp4", False)
                  for name, rec, _ in ds.golfdb())
    else:
        raise SystemExit("dataset must be thetis or golf")
    for name, rec, video, mirror in source:
        if done >= n:
            break
        if video is None or not Path(video).exists():
            continue
        res = render_replay(rec, str(video), str(OUT_DIR / f"{name}.mp4"), rec["sport"],
                            rec.get("handedness", "right"), rec.get("view"), mirror_x=mirror)
        if not res:
            continue
        done += 1
        for r in res:
            manifest[Path(r["path"]).name] = r
            print(f"{r['path']}  [{r['metric']} {r['value']:.3g} -> {r['target']:.3g}, moved {r['moved']}]  {r['cue']}")
    _manifest_path().write_text(json.dumps(manifest, indent=1))


def contact_sheet(out: Path = OUT_DIR / "contact.png", thumb_h: int = 240):
    """Three frames per replay (clip start, key moment, freeze-frame), one row per replay."""
    rows = []
    for fname, r in sorted(_load_manifest().items()):
        cap = cv2.VideoCapture(str(OUT_DIR / fname))
        frames = []
        while True:
            ok, img = cap.read()
            if not ok:
                break
            frames.append(img)
        cap.release()
        if not frames:
            continue
        picks = [frames[0], frames[min(r["key_frame"], len(frames) - 1)], frames[-1]]
        picks = [cv2.resize(p, (int(p.shape[1] * thumb_h / p.shape[0]), thumb_h)) for p in picks]
        label = np.zeros((22, sum(p.shape[1] for p in picks) + 8, 3), np.uint8)
        cv2.putText(label, f"{fname}  ({r['metric']})", (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, WHITE, 1, cv2.LINE_AA)
        row = np.hstack([np.hstack([p, np.zeros((thumb_h, 4, 3), np.uint8)]) for p in picks])[:, :label.shape[1]]
        rows.append(np.vstack([label, row]))
    if not rows:
        return None
    width = max(r.shape[1] for r in rows)
    rows = [np.hstack([r, np.zeros((r.shape[0], width - r.shape[1], 3), np.uint8)]) for r in rows]
    cv2.imwrite(str(out), np.vstack(rows))
    return out


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "contact":
        print(contact_sheet())
    elif len(sys.argv) >= 3:
        run(sys.argv[1], int(sys.argv[2]))
        print(contact_sheet())
    else:
        print(__doc__)
        sys.exit(1)
