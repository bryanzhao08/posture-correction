"""Tennis stroke classifier: a fixed-length descriptor per counted rep, and a JSON model to read it.

The engine (formcoach/) already tells forehand from backhand from serve; this module adds the
nuance underneath that: one- vs two-handed backhand, volleys, smash, slice vs flat/topspin and the
three serve types. Everything here is computed from the engine's Samples (smoothed joints in
height units, mid-hip, torso length) and the Rep it counted, so the iOS Swift and browser
TypeScript ports can compute the same numbers and run the same model.

Descriptor (see FEATURES for the exact order):
  - side: +1/-1 so that x * side puts the dominant side at +x. It is the sign of the mean of
    (dominant shoulder x - other shoulder x) over the rep, i.e. the same convention as the
    engine's `facing` (which uses a slow average of the same quantity).
  - dominant / other wrist relative to the mid-hip in torso units (x multiplied by side, y down),
    linearly resampled to N_POINTS times evenly spaced over [t_start, t_end].
  - wrist heights and the elbow angles at the rep's backswing / contact / finish events,
    two-hand-ness (distance between the wrists), swing duration, peak speed, toss height for
    serves, a few body measures, the engine's rep type as a one-hot, and the engine's racket
    metrics (missing ones are replaced by the training median stored in the model JSON).

Model: shared/stroke_model.json holds the feature list, the standardisation (mean, std,
imputation value per feature), and for each task a multinomial logistic regression
(weights [classes x features], bias [classes]). `predict` needs only numpy and that file.
"""
from __future__ import annotations

import json
import math
from functools import lru_cache
from pathlib import Path

import numpy as np

MODEL_PATH = Path(__file__).resolve().parents[1] / "shared" / "stroke_model.json"
N_POINTS = 16

# THETIS folder -> fine class (the dataset's 12 labels)
THETIS_FOLDERS = {
    "backhand": "backhand_one_handed",
    "backhand2hands": "backhand_two_handed",
    "backhand_slice": "backhand_slice",
    "backhand_volley": "backhand_volley",
    "forehand_flat": "forehand_flat",
    "forehand_openstands": "forehand_open_stance",
    "forehand_slice": "forehand_slice",
    "forehand_volley": "forehand_volley",
    "flat_service": "serve_flat",
    "kick_service": "serve_kick",
    "slice_service": "serve_slice",
    "smash": "smash",
}
FINE_CLASSES = list(THETIS_FOLDERS.values())
COARSE = {
    "backhand_one_handed": "backhand_one", "backhand_two_handed": "backhand_two",
    "backhand_slice": "backhand_one", "backhand_volley": "volley", "forehand_flat": "forehand",
    "forehand_open_stance": "forehand", "forehand_slice": "forehand", "forehand_volley": "volley",
    "serve_flat": "serve", "serve_kick": "serve", "serve_slice": "serve", "smash": "smash",
}
COARSE_CLASSES = ["forehand", "backhand_one", "backhand_two", "volley", "serve", "smash"]
# Spin / variant: groundstrokes are slice or not (THETIS "flat" forehands and the plain backhands
# are hit flat-to-topspin); serves are flat, kick or slice. Volleys and smashes have no variant.
GROUNDSTROKE_SPIN = {
    "backhand_one_handed": "flat_topspin", "backhand_two_handed": "flat_topspin",
    "forehand_flat": "flat_topspin", "forehand_open_stance": "flat_topspin",
    "backhand_slice": "slice", "forehand_slice": "slice",
}
SERVE_TYPE = {"serve_flat": "flat", "serve_kick": "kick", "serve_slice": "slice"}


def labels(fine: str) -> dict:
    return {"fine": fine, "coarse": COARSE[fine], "groundstroke_spin": GROUNDSTROKE_SPIN.get(fine),
            "serve_type": SERVE_TYPE.get(fine)}


# The engine's racket-analyzer metrics used as features (absent ones are imputed).
ENGINE_METRICS = ["stance_height", "contact_arm", "contact_height", "swing_through", "shoulder_turn",
                  "swing_tempo", "backswing_size", "ready_height", "head_stability", "finish_height",
                  "elbow_finish", "off_hand_reach", "spacing", "extension_through"]
ENGINE_TYPES = ["forehand", "backhand", "serve"]
EVENTS = ["backswing", "contact", "finish"]

FEATURES = (
    [f"dom_x_{i}" for i in range(N_POINTS)] + [f"dom_y_{i}" for i in range(N_POINTS)]
    + [f"off_x_{i}" for i in range(N_POINTS)] + [f"off_y_{i}" for i in range(N_POINTS)]
    + [f"dom_elbow_{e}" for e in EVENTS] + [f"off_elbow_{e}" for e in EVENTS]
    + [f"dom_wrist_y_{e}" for e in EVENTS] + [f"dom_wrist_x_{e}" for e in EVENTS]
    + ["hands_gap_min", "hands_gap_mean", "hands_gap_contact", "hands_close_frac",
       "duration", "peak_speed", "contact_frac", "backswing_frac",
       "dom_apex_y", "off_apex_y", "toss_lead", "off_apex_x",
       "nose_x_contact", "nose_y_contact", "ankle_gap_contact", "hip_dx", "hip_dy",
       "shoulder_width_min", "dom_path_len", "dom_vx_contact", "dom_vy_contact"]
    + [f"type_{t}" for t in ENGINE_TYPES]
    + [f"m_{k}" for k in ENGINE_METRICS]
)


# ---- feature extraction -----------------------------------------------------------------------
def _angle(a, b, c):
    if a is None or b is None or c is None:
        return None
    v1 = (a[0] - b[0], a[1] - b[1])
    v2 = (c[0] - b[0], c[1] - b[1])
    n = math.hypot(*v1) * math.hypot(*v2)
    if n < 1e-9:
        return None
    return math.degrees(math.acos(max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / n))))


def _rel(s, name, side):
    """A joint relative to the sample's mid-hip in torso units, dominant side at +x (None if unseen)."""
    p = s.pts.get(name)
    if p is None:
        return None
    return ((p[0] - s.hip[0]) / s.torso * side, (p[1] - s.hip[1]) / s.torso)


def _filled(vals):
    """Fill gaps (None) with the nearest earlier value, or the first later one at the start."""
    out = list(vals)
    last = None
    for i, v in enumerate(out):
        if v is None:
            out[i] = last
        else:
            last = v
    nxt = None
    for i in range(len(out) - 1, -1, -1):
        if out[i] is None:
            out[i] = nxt
        else:
            nxt = out[i]
    return out


def _resample(ts, vals, t0, t1, n=N_POINTS):
    """Linear interpolation of vals(ts) at n evenly spaced times from t0 to t1 inclusive."""
    out = []
    j = 0
    for i in range(n):
        t = t0 + (t1 - t0) * i / (n - 1)
        while j < len(ts) - 2 and ts[j + 1] < t:
            j += 1
        if len(ts) == 1 or t <= ts[0]:
            out.append(vals[0])
            continue
        if t >= ts[-1]:
            out.append(vals[-1])
            continue
        a, b = ts[j], ts[j + 1]
        w = (t - a) / (b - a) if b > a else 0.0
        out.append(vals[j] + w * (vals[j + 1] - vals[j]))
    return out


def _at(seg, t):
    """Index of the sample closest to time t."""
    best = 0
    for i, s in enumerate(seg):
        if abs(s.t - t) < abs(seg[best].t - t):
            best = i
    return best


def rep_features(samples, rep, dom: str = "r") -> dict:
    """Descriptor of one counted rep. samples: the engine Samples covering the rep (any superset is
    fine: only those with t_start <= t <= t_end are used); rep: the engine Rep (or its to_dict());
    dom: "r" or "l" for the player's handedness. Unavailable values are None (imputed by predict)."""
    r = rep if isinstance(rep, dict) else rep.to_dict()
    off = "l" if dom == "r" else "r"
    seg = [s for s in samples if r["t_start"] - 1e-6 <= s.t <= r["t_end"] + 1e-6]
    if len(seg) < 2:
        raise ValueError("rep has fewer than 2 samples")
    across = [(s.pts[dom + "_shoulder"][0] - s.pts[off + "_shoulder"][0]) / s.torso for s in seg]
    side = 1.0 if sum(across) >= 0 else -1.0
    ts = [s.t for s in seg]
    t0, t1 = ts[0], ts[-1]
    dur = max(t1 - t0, 1e-6)
    dw = _filled([_rel(s, dom + "_wrist", side) for s in seg])
    ow = _filled([_rel(s, off + "_wrist", side) for s in seg])
    if ow[0] is None:
        ow = dw                                           # other wrist never seen: treat as together
    f: dict = {}
    for name, traj in (("dom", dw), ("off", ow)):
        for k, axis in ((0, "x"), (1, "y")):
            for i, v in enumerate(_resample(ts, [p[k] for p in traj], t0, t1)):
                f[f"{name}_{axis}_{i}"] = v

    ev = r.get("events") or {}
    idx = {}
    for e in EVENTS:
        idx[e] = _at(seg, ev[e]) if e in ev else None
    if idx["contact"] is None:                            # fastest sample stands in for contact
        idx["contact"] = max(range(len(seg)), key=lambda i: seg[i].speed)
    for e in EVENTS:
        i = idx[e]
        s = seg[i] if i is not None else None
        f[f"dom_elbow_{e}"] = _angle(s.pts.get(dom + "_shoulder"), s.pts.get(dom + "_elbow"),
                                     s.pts.get(dom + "_wrist")) if s else None
        f[f"off_elbow_{e}"] = _angle(s.pts.get(off + "_shoulder"), s.pts.get(off + "_elbow"),
                                     s.pts.get(off + "_wrist")) if s else None
        f[f"dom_wrist_y_{e}"] = dw[i][1] if s else None
        f[f"dom_wrist_x_{e}"] = dw[i][0] if s else None

    c = idx["contact"]
    lo = idx["backswing"] if idx["backswing"] is not None else 0
    hi = idx["finish"] if idx["finish"] is not None else len(seg) - 1
    if hi < lo:
        lo, hi = hi, lo
    gaps = [math.hypot(dw[i][0] - ow[i][0], dw[i][1] - ow[i][1]) for i in range(lo, hi + 1)]
    f["hands_gap_min"] = min(gaps)
    f["hands_gap_mean"] = sum(gaps) / len(gaps)
    f["hands_gap_contact"] = math.hypot(dw[c][0] - ow[c][0], dw[c][1] - ow[c][1])
    f["hands_close_frac"] = sum(1 for g in gaps if g < 0.5) / len(gaps)
    f["duration"] = dur
    f["peak_speed"] = max(s.speed for s in seg)
    f["contact_frac"] = (seg[c].t - t0) / dur
    f["backswing_frac"] = (seg[lo].t - t0) / dur
    da = min(range(len(seg)), key=lambda i: dw[i][1])
    oa = min(range(len(seg)), key=lambda i: ow[i][1])
    f["dom_apex_y"] = dw[da][1]
    f["off_apex_y"] = ow[oa][1]                           # toss height for serves
    f["toss_lead"] = (seg[da].t - seg[oa].t) / dur        # how long before the hit the toss peaks
    f["off_apex_x"] = ow[oa][0]                           # toss placement left/right of the hips
    nz = _rel(seg[c], "nose", side)
    f["nose_x_contact"] = nz[0] if nz else None
    f["nose_y_contact"] = nz[1] if nz else None
    la, ra = seg[c].pts.get("l_ankle"), seg[c].pts.get("r_ankle")
    f["ankle_gap_contact"] = abs(la[0] - ra[0]) / seg[c].torso if la and ra else None
    f["hip_dx"] = (seg[-1].hip[0] - seg[0].hip[0]) / seg[-1].torso * side
    f["hip_dy"] = (seg[-1].hip[1] - seg[0].hip[1]) / seg[-1].torso
    sw0 = math.dist(seg[0].pts["l_shoulder"], seg[0].pts["r_shoulder"])
    f["shoulder_width_min"] = min(math.dist(s.pts["l_shoulder"], s.pts["r_shoulder"]) for s in seg) / max(sw0, 1e-6)
    f["dom_path_len"] = sum(math.hypot(dw[i][0] - dw[i - 1][0], dw[i][1] - dw[i - 1][1]) for i in range(1, len(seg)))
    a, b = max(c - 1, 0), min(c + 1, len(seg) - 1)
    dt = max(seg[b].t - seg[a].t, 1e-6)
    f["dom_vx_contact"] = (dw[b][0] - dw[a][0]) / dt
    f["dom_vy_contact"] = (dw[b][1] - dw[a][1]) / dt
    for t in ENGINE_TYPES:
        f[f"type_{t}"] = 1.0 if r["type"] == t else 0.0
    m = r.get("metrics") or {}
    for k in ENGINE_METRICS:
        v = m.get(k)
        f[f"m_{k}"] = float(v) if v is not None else None
    return f


def analyze_with_samples(rec: dict, profiles: dict | None = None):
    """analyze_recording, keeping every Sample (the engine's buffer only keeps a few seconds)."""
    from formcoach.engine import Engine, load_profiles
    profiles = profiles or load_profiles()
    eng = Engine(profiles, rec["sport"], rec.get("handedness", "right"), rec.get("view"), rec.get("focus"),
                 rec.get("player"), rec.get("drill"))
    eng.events = []
    samples = []
    for fr in rec["frames"]:
        n = len(eng.buf)
        last = eng.buf[-1] if n else None
        eng.events.extend(eng.push(fr["t"], fr["j"], rec.get("aspect", 1.0)))
        if eng.buf and eng.buf[-1] is not last:
            samples.append(eng.buf[-1])
    return eng, samples


def recording_features(rec: dict, profiles: dict | None = None) -> list[dict]:
    """Descriptor of every rep the engine counts in a recording."""
    eng, samples = analyze_with_samples(rec, profiles)
    dom = "r" if rec.get("handedness", "right") == "right" else "l"
    return [rep_features(samples, rep, dom) for rep in eng.reps]


# ---- inference (numpy + the JSON only) ---------------------------------------------------------
@lru_cache(maxsize=4)
def load_model(path: str | Path = MODEL_PATH) -> dict:
    return json.loads(Path(path).read_text())


def vectorize(features, model: dict) -> np.ndarray:
    """Standardised feature vector in the model's order. features: dict by name or ordered sequence."""
    norm = model["normalization"]
    if isinstance(features, dict):
        x = [features.get(n) for n in model["features"]]
    else:
        x = list(features)
        if len(x) != len(model["features"]):
            raise ValueError(f"expected {len(model['features'])} features, got {len(x)}")
    x = np.array([np.nan if v is None else float(v) for v in x], dtype=float)
    x = np.where(np.isfinite(x), x, np.asarray(norm["impute"], dtype=float))
    return (x - np.asarray(norm["mean"])) / np.asarray(norm["std"])


def _softmax(z: np.ndarray) -> np.ndarray:
    z = z - z.max()
    e = np.exp(z)
    return e / e.sum()


def predict(features, model: dict | str | Path | None = None, tasks=None) -> dict:
    """Run every task in the model (coarse, fine, groundstroke_spin, serve_type) on one descriptor.

    Returns {task: {"label": str, "probs": {class: p}}}. The variant tasks are only meaningful for
    the matching stroke (spin for groundstrokes, serve_type for serves); callers should show them
    only when the coarse label is a groundstroke / serve ("applies_to" in the model lists which).
    """
    if model is None:
        model = load_model()
    elif not isinstance(model, dict):
        model = load_model(str(model))
    z = vectorize(features, model)
    out = {}
    for name, task in model["tasks"].items():
        if tasks is not None and name not in tasks:
            continue
        p = _softmax(np.asarray(task["weights"]) @ z + np.asarray(task["bias"]))
        k = int(np.argmax(p))
        out[name] = {"label": task["classes"][k], "probs": {c: float(v) for c, v in zip(task["classes"], p)}}
    return out
