"""Run MediaPipe pose estimation over videos and save recordings in the engine's input format.

Needs the pose environment (.venv-pose: mediapipe==0.10.14, whose pose solution runs on CPU).

usage: ../.venv-pose/bin/python extract_pose.py <out_dir> <video> [<video> ...]      (skips videos already done)
"""
from __future__ import annotations

import json
import sys
from multiprocessing import Pool
from pathlib import Path

# engine joint order -> MediaPipe landmark index
MP_INDEX = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
MIN_SIDE = 480


def extract(video: str, complexity: int = 1) -> dict:
    import cv2
    import mediapipe as mp

    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    frames = []
    aspect = 1.0
    with mp.solutions.pose.Pose(static_image_mode=False, model_complexity=complexity) as pose:
        i = 0
        while True:
            ok, img = cap.read()
            if not ok:
                break
            h, w = img.shape[:2]
            aspect = w / h
            if min(h, w) < MIN_SIDE:
                s = MIN_SIDE / min(h, w)
                img = cv2.resize(img, (round(w * s), round(h * s)), interpolation=cv2.INTER_CUBIC)
            res = pose.process(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
            if res.pose_landmarks:
                p = res.pose_landmarks.landmark
                j = [[round(p[k].x, 5), round(p[k].y, 5), round(p[k].visibility, 3)] for k in MP_INDEX]
            else:
                j = [[0.0, 0.0, 0.0]] * 13
            frames.append({"t": round(i / fps, 4), "j": j})
            i += 1
    return {"fps": fps, "aspect": aspect, "frames": frames}


def _job(args):
    video, out = args
    if not Path(out).exists():
        Path(out).write_text(json.dumps(extract(video)))
    return out


if __name__ == "__main__":
    out_dir = Path(sys.argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)
    jobs = [(v, str(out_dir / (Path(v).stem + ".json"))) for v in sys.argv[2:]]
    with Pool(6) as pool:
        for n, _ in enumerate(pool.imap_unordered(_job, jobs), 1):
            if n % 50 == 0:
                print(n, "/", len(jobs), flush=True)
