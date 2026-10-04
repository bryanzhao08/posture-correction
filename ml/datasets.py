"""Loaders that turn each public dataset into engine recordings plus ground truth.

GolfDB   (golf)       1,400 pro swings from YouTube with 8 labelled swing events; we use the 246
                      face-on, real-time clips. https://github.com/wmcnally/golfdb  (CC BY-NC 4.0)
THETIS   (tennis)     55 players (p1-p31 beginners, p32-p55 experts) shadow-swinging in front of a
                      Kinect (mirrored video, un-mirrored here); one stroke type per clip. https://github.com/THETIS-dataset/dataset
SPL      (basketball) 583 motion-captured free throws from 5 athletes with made/missed result.
                      https://github.com/mlsedigital/SPL-Open-Data
Penn Action           2,326 YouTube clips of 15 actions with human-labelled joints (same 13 joints):
                      golf swings and tennis strokes by players of all levels, plus squats, jumping
                      jacks, pitches, bat swings, push-ups... used as motions that must not count.
                      http://dreamdragon.github.io/PennAction/  (labels only; frames not needed)
"""
from __future__ import annotations

import glob
import json
import math
from pathlib import Path

DATA = Path(__file__).parent / "data"
JOINTS = ["nose", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
          "l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]
GOLF_EVENTS = ["address", "toe_up", "mid_backswing", "top", "mid_downswing", "impact",
               "mid_follow_through", "finish"]


def pad_end(rec: dict, seconds: float) -> dict:
    """Hold the final pose: dataset clips are cut right after the motion, a live camera is not."""
    fps = rec["fps"]
    last = rec["frames"][-1]
    for i in range(1, int(seconds * fps) + 1):
        rec["frames"].append({"t": round(last["t"] + i / fps, 4), "j": last["j"]})
    return rec


_SWAP = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11]


def unmirror(rec: dict) -> dict:
    """Kinect colour video is mirrored, which makes pose models swap left and right. Flip it back."""
    for fr in rec["frames"]:
        fr["j"] = [[round(1.0 - fr["j"][k][0], 5), fr["j"][k][1], fr["j"][k][2]] for k in _SWAP]
    return rec


def golfdb(split: set[int] | None = None):
    import pandas as pd
    df = pd.read_pickle(DATA / "golfdb" / "data" / "golfDB.pkl")
    df = df[(df["view"] == "face-on") & (df["slow"] == 0)]
    for _, row in df.iterrows():
        if split is not None and int(row["split"]) not in split:
            continue
        path = DATA / "poses" / "golfdb" / f"{int(row['id'])}.json"
        if not path.exists():
            continue
        rec = json.loads(path.read_text())
        rec.update(sport="golf", handedness="right")
        ev = [int(e) - int(row["events"][0]) for e in row["events"]]
        truth = {name: ev[i + 1] / rec["fps"] for i, name in enumerate(GOLF_EVENTS)}
        yield f"golfdb_{int(row['id'])}", pad_end(rec, 0.6), {
            "events": truth, "player": str(row["player"]), "club": str(row["club"]), "split": int(row["split"])}


THETIS_CLASSES = {"forehand_flat": "forehand", "backhand": "backhand", "flat_service": "serve"}


def thetis(classes=THETIS_CLASSES):
    for folder, stroke in classes.items():
        for path in sorted(glob.glob(str(DATA / "poses" / "thetis" / folder / "*.json"))):
            name = Path(path).stem
            subject = int(name.split("_")[0][1:])
            rec = unmirror(json.loads(Path(path).read_text()))
            rec.update(sport="tennis", handedness="right")
            yield f"thetis_{name}", pad_end(rec, 0.6), {
                "stroke": stroke, "subject": subject, "expert": subject >= 32}


def _project(p, cam_x: float, cam_z: float, focal: float, aspect: float):
    """Pinhole camera on the hoop side of the shooter, looking back at them (-x), z up."""
    depth = cam_x - p[0]
    u = focal * p[1] / depth          # +y (shooter's left) is image right for this camera
    v = focal * (cam_z - p[2]) / depth
    return [round(0.5 + u / aspect, 5), round(0.5 + v, 5), 1.0]


def spl(distance_ft: float = 12.0):
    """Project the 3D mocap to the 2D view a phone on a tripod in front of the shooter would see."""
    names = [j.replace("l_", "LEFT_").replace("r_", "RIGHT_").upper() for j in JOINTS]
    aspect = 9 / 16
    for path in sorted(glob.glob(str(DATA / "SPL-Open-Data/basketball/freethrow/data/*/*/*.json"))):
        d = json.loads(Path(path).read_text())
        hip_x = sorted(fr["data"]["player"]["LEFT_HIP"][0] for fr in d["tracking"]
                       if (fr["data"]["player"].get("LEFT_HIP") or [None])[0] is not None)
        if not hip_x:
            continue
        cam_x = hip_x[len(hip_x) // 2] + distance_ft
        cam_z = 4.0
        focal = 0.6 * distance_ft / 6.5          # a 6.5 ft person fills ~60% of the frame height
        frames = []
        hi = {"l": -1e9, "r": -1e9}
        for fr in d["tracking"]:
            pl = fr["data"]["player"]
            j = []
            for n in names:
                p = pl.get(n)
                ok = p is not None and all(c is not None and c == c for c in p)
                j.append(_project(p, cam_x, cam_z, focal, aspect) if ok else [0.0, 0.0, 0.0])
            for side, n in (("l", "LEFT_WRIST"), ("r", "RIGHT_WRIST")):
                p = pl.get(n)
                if p and p[2] is not None and p[2] == p[2]:
                    hi[side] = max(hi[side], p[2])
            frames.append({"t": fr["time"] / 1000.0, "j": j})
        rec = {"sport": "basketball", "handedness": "right" if hi["r"] >= hi["l"] else "left",
               "fps": float(d["sampling_rate"]), "aspect": aspect, "frames": frames}
        yield f"spl_{d['trial_date']}_{d['participant_id']}_{d['trial_id']}", pad_end(rec, 0.6), {
            "result": d["result"], "participant": d["participant_id"], "date": d["trial_date"]}


def pad_start(rec: dict, seconds: float) -> dict:
    """Hold the first pose: trimmed clips start mid-routine, a person at the camera stands first."""
    fps = rec["fps"]
    first = rec["frames"][0]
    n = int(seconds * fps)
    for fr in rec["frames"]:
        fr["t"] = round(fr["t"] + n / fps, 4)
    rec["frames"][:0] = [{"t": round(i / fps, 4), "j": first["j"]} for i in range(n)]
    return rec


def penn_action(actions=None, fps: float = 30.0):
    """Penn Action labels. Clips have no frame rate on record; YouTube footage is mostly 30 fps."""
    import scipy.io as sio
    for path in sorted(glob.glob(str(DATA / "Penn_Action" / "labels" / "*.mat"))):
        m = sio.loadmat(path, squeeze_me=True)
        action = str(m["action"])
        if actions is not None and action not in actions:
            continue
        h, w = float(m["dimensions"][0]), float(m["dimensions"][1])
        xs, ys, vis = m["x"], m["y"], m["visibility"]
        frames = []
        for i in range(int(m["nframes"])):
            j = [[round(float(xs[i][k]) / w, 5), round(float(ys[i][k]) / h, 5), 0.9 if vis[i][k] else 0.4]
                 for k in range(13)]
            frames.append({"t": round(i / fps, 4), "j": j})
        rec = {"handedness": "right", "fps": fps, "aspect": w / h, "frames": frames}
        yield f"penn_{Path(path).stem}", pad_end(pad_start(rec, 1.6), 0.6), {
            "action": action, "view": str(m["pose"])}
