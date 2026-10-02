import sys
import os
import json
import argparse
import numpy as np

# Ensure ml/ is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import cv2
from formcoach.engine import Engine, load_profiles

BONES = [
    ("nose", "l_shoulder"), ("nose", "r_shoulder"), ("l_shoulder", "r_shoulder"),
    ("l_shoulder", "l_elbow"), ("l_elbow", "l_wrist"),
    ("r_shoulder", "r_elbow"), ("r_elbow", "r_wrist"),
    ("l_shoulder", "l_hip"), ("r_shoulder", "r_hip"),
    ("l_hip", "r_hip"), ("l_hip", "l_knee"), ("l_knee", "l_ankle"),
    ("r_hip", "r_knee"), ("r_knee", "r_ankle")
]

def render(rec_path, out_path, sport=None, video_path=None):
    with open(rec_path, 'r') as f:
        rec = json.load(f)
    
    fps = rec.get("fps", 30.0)
    aspect = rec.get("aspect", 0.5625) # 9:16 default
    frames = rec["frames"]
    handedness = rec.get("handedness", "right")
    
    profiles = load_profiles() if sport else None
    joints_list = profiles["joints"] if profiles else ["nose", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist", "l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]
    
    eng = Engine(profiles, sport, handedness) if sport else None
    
    cap = cv2.VideoCapture(video_path) if video_path else None
    if cap:
        W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    else:
        H = 1280
        W = int(H * aspect)
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    writer = cv2.VideoWriter(out_path, fourcc, fps, (W, H))
    
    flash_text = ""
    flash_frames_left = 0
    flash_color = (255, 255, 255)
    
    rep_count = 0
    
    for i, fr in enumerate(frames):
        t = fr["t"]
        joints = fr["j"] # [[x,y,conf], ...]
        
        # Build dictionary for drawing
        j_dict = {}
        for j_name, j_val in zip(joints_list, joints):
            if j_val is not None and j_val[2] >= 0.3:
                # x and y are normalised (origin top-left)
                jx = int(j_val[0] * W)
                jy = int(j_val[1] * H)
                j_dict[j_name] = (jx, jy)
        
        if cap:
            ret, frame = cap.read()
            if not ret:
                frame = np.zeros((H, W, 3), dtype=np.uint8)
        else:
            frame = np.zeros((H, W, 3), dtype=np.uint8)
            
        # Draw skeleton
        for pt1, pt2 in BONES:
            if pt1 in j_dict and pt2 in j_dict:
                cv2.line(frame, j_dict[pt1], j_dict[pt2], (0, 255, 0), 2)
        for name, pt in j_dict.items():
            cv2.circle(frame, pt, 4, (0, 0, 255), -1)
            
        if eng:
            events = eng.push(t, joints, aspect)
            for ev in events:
                if ev.kind == "rep":
                    rep_count += 1
                    flash_text = f"REP! Score: {ev.rep.score:.1f}"
                    flash_color = (0, 255, 0)
                    flash_frames_left = int(fps * 1.5)
                elif ev.kind == "rejected":
                    flash_text = f"Rejected: {ev.reason}"
                    flash_color = (0, 0, 255)
                    flash_frames_left = int(fps * 1.5)
            
            speed = eng._speed if eng._speed is not None else 0.0
            
            # Draw overlays
            cv2.putText(frame, f"State: {eng.state}", (20, 40), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
            cv2.putText(frame, f"Reps: {rep_count}", (20, 80), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
            cv2.putText(frame, f"Speed: {speed:.2f}", (20, 120), cv2.FONT_HERSHEY_SIMPLEX, 1, (255, 255, 255), 2)
            
        if flash_frames_left > 0:
            cv2.putText(frame, flash_text, (20, 180), cv2.FONT_HERSHEY_SIMPLEX, 1.5, flash_color, 3)
            flash_frames_left -= 1
            
        writer.write(frame)
        
    if cap:
        cap.release()
    writer.release()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("rec", help="recording.json")
    parser.add_argument("out", help="out.mp4")
    parser.add_argument("--sport", help="run engine for sport")
    parser.add_argument("--video", help="original.mp4")
    args = parser.parse_args()
    
    render(args.rec, args.out, args.sport, args.video)
