# Brief for Antigravity, batch 5: convert TennisDB motion capture into side/back/front tennis recordings

Project root `/Users/bryan/Documents/GitHub/FormCoach` (use absolute paths; your shell starts in
the home directory). Python: `/Users/bryan/Documents/GitHub/FormCoach/.venv/bin/python` (install
extra packages into that venv with its pip, e.g. `ezc3d` or `c3d`).

## Why
The tennis engine now supports three camera views (`front`, `side`, `back`). A tennis coach asked
for cues that need a side view (contact in front, back-leg load, weight transfer, extension
through the ball) or a view from behind (spacing, turn, finish). There is no public side-view
tennis keypoint dataset, so we create one by projecting 3D motion capture into virtual cameras.

## Data
TennisDB / 3DTennisDS, Lublin University of Technology: https://tennisdb.cs.pollub.pl/
Vicon C3D files (Plug-in Gait marker set, about 100 Hz), 11 players, forehand and backhand with and
without a ball, forehand and backhand volleys. 62 zip files linked from the site, about 2-3 MB
each, for example `https://tennisdb.cs.pollub.pl/wp-content/uploads/2022/12/tp1_fhb.zip`.
License: attribution. Credit line: "The used tennis motion capture dataset was obtained from
https://tennisdb.cs.pollub.pl at the Lublin University of Technology".

## Tasks
1. Download all zips into `ml/data/tennisdb/` (git-ignored) and unzip. Write a short inventory
   (files per player and stroke, frame rate, number of strokes per file, marker labels present)
   into `ml/data/tennisdb/INVENTORY.md`.
2. Write `ml/datasets_tennisdb.py` (new file) with a generator
   `tennisdb(views=("front", "side", "back"))` that yields
   `(name, recording, truth)` exactly like the loaders in `ml/datasets.py` (read that file first and
   reuse `pad_start` / `pad_end`):
   - `recording = {"sport": "tennis", "handedness": "right"|"left", "view": <view>, "fps": 30.0,
     "aspect": 0.5625, "frames": [{"t", "j": [[x, y, conf] * 13]}]}`, x and y normalised to the
     image (origin top-left, y down), joints in the order of `shared/sport_profiles.json` `"joints"`:
     nose, l_shoulder, r_shoulder, l_elbow, r_elbow, l_wrist, r_wrist, l_hip, r_hip, l_knee, r_knee,
     l_ankle, r_ankle. Use the person's anatomical left/right. Confidence 0.9 when the markers exist,
     0 when missing.
   - Joint from markers (Plug-in Gait names; check what the files actually contain): nose = mean of
     LFHD and RFHD; shoulders = LSHO/RSHO; elbows = LELB/RELB; wrists = mean of LWRA and LWRB
     (RWRA/RWRB); hips = hip joint centres if the file has them, else mean of the ASIS and PSIS
     markers on that side; knees = LKNE/RKNE; ankles = LANK/RANK.
   - Resample to 30 fps.
   - Virtual pinhole camera, portrait 9:16, vertical focal length chosen so a 1.8 m person fills
     about 60% of the frame height at the camera distance below, camera height 1.2 m:
     `front` = 5 m in front of the player facing them; `back` = 5 m behind the player looking
     toward the net; `side` = 5 m to the player's right (the forehand side for a right-hander),
     looking across. "Forward" (toward the net) is the direction the pelvis faces in the first
     frames (normal to the ASIS line, horizontal). Report how you determined the lab axes.
   - `handedness`: from the dataset's metadata if it exists, otherwise the wrist that moves fastest.
   - `truth = {"player", "stroke": "forehand"|"backhand"|"forehand_volley"|"backhand_volley",
     "with_ball": bool, "strokes_in_file": int}`.
3. Sanity check and report: run the engine on every recording and view,
   ```python
   from formcoach.engine import analyze_recording, load_profiles
   eng = analyze_recording(recording, load_profiles())   # eng.reps, eng.rejected
   ```
   (with `PYTHONPATH=ml`), and report per view and stroke: counted exactly once / missed /
   double-counted, rep types, and the median of these metrics on counted reps: `contact_front`,
   `extension_through`, `back_load`, `weight_shift`, `spacing`, `finish_height`, `elbow_finish`,
   `off_hand_reach`, `contact_arm`. Also save 3 rendered sanity frames per view as PNGs (stick
   figure at the contact frame) in `ml/data/tennisdb/preview/` so Claude can check the projection.

You own only `ml/datasets_tennisdb.py` and `ml/data/tennisdb/**`. Do **not** edit
`ml/formcoach/`, `ml/datasets.py`, `shared/`, `ml/validate.py`, `ml/fit_reference.py` (Claude is
changing them). Do not commit. Reply with the inventory summary, the axis/camera decisions, the
sanity table, and anything odd.
