# Brief for Antigravity, batch 4: find and convert more validation data (golf, basketball, pickleball)

Project root: `/Users/bryan/Documents/GitHub/FormCoach` (use absolute paths). Python env:
`/Users/bryan/Documents/GitHub/FormCoach/.venv/bin/python`. Pose extraction from video:
`/Users/bryan/Documents/GitHub/FormCoach/.venv-pose/bin/python ml/extract_pose.py <out_dir> <videos...>`
(run from `ml/`; MediaPipe 0.10.14 CPU, writes the engine's recording format).

## Why
The engine counts swings/shots from 13 body joints filmed **face-on** by a phone on a tripod.
It was validated on GolfDB (pro golf), THETIS (tennis shadow swings) and SPL (basketball free
throws, mocap). Real-phone testing by the user showed: golf swings by an amateur were not detected
at all, basketball needed a deep squat to register, and pickleball has no data. We need data that
looks like **ordinary people practising in front of a camera**, not broadcast pros. Claude is
separately handling Penn Action (do not download it).

## Your task
1. Search the web for downloadable datasets (video or 2D/3D keypoints) of:
   - **golf**: amateur / recreational swings, ideally face-on (e.g. CaddieSet 2025, GolfPose's
     GolfSwing data, Kaggle/Roboflow/Hugging Face/academic pages; check each one's actual access).
   - **basketball**: jump shots or set shots by amateurs, one person, roughly front view (check
     Hugging Face `muyu111/basketball` (SHOT), `amathislab/SHOT7M2`, `Henu-Software/Henu-MultiSubjects`
     (gated: note how to request), and anything else you find).
   - **pickleball**: any stroke video/keypoint data at all; if none, the closest proxy (badminton
     or table-tennis *player-pose* datasets filmed from in front: e.g. ShuttleSet poses, TTStroke).
2. For each candidate, write one row in `ml/data_sources.md` (new file): name, URL, what it
   contains, view angle, size, **license** (quote it), whether it is downloadable without a request,
   and your verdict (use / maybe / no) with one line why.
3. For up to **two** "use" datasets that are freely downloadable and under **3 GB**, download them
   into `ml/data/extra/<name>/` (git-ignored; disk is tight, about 15 GB free, so check sizes first
   and stream/extract only what is needed) and write `ml/extra_datasets.py` (new file) with a
   generator per dataset in the same shape as the loaders in `ml/datasets.py`:
   `yield name, recording, truth`, where `recording = {"sport", "handedness", "fps", "aspect",
   "frames": [{"t", "j": [[x, y, conf] * 13]}]}` with x, y normalised 0..1, origin top-left,
   joints in the order of `shared/sport_profiles.json` `"joints"`, and `truth` holding whatever
   labels exist (number of swings/shots in the clip, event frames, skill level, made/missed...).
   Read `ml/datasets.py` first and reuse its helpers (`pad_end`, the SPL projection) rather than
   copying them. If a dataset has videos only, run `extract_pose.py` on at most 300 clips.
4. Run the engine over what you converted and report counting accuracy (counted exactly once /
   missed / double-counted) and rejection reasons, like this:
   ```python
   from formcoach.engine import analyze_recording, load_profiles
   eng = analyze_recording(recording, load_profiles())   # eng.reps, eng.rejected
   ```
   (run with `PYTHONPATH=ml`). **Do not change** `ml/formcoach/`, `shared/sport_profiles.json`,
   `ml/datasets.py`, `ml/validate.py` or `ml/fit_reference.py`: Claude is editing them now. If you
   think a threshold is wrong, say so in your report with the numbers.

You own only: `ml/data_sources.md`, `ml/extra_datasets.py`, `ml/data/extra/**`. Do not commit.
Reply with the table summary, what you downloaded, the counting results, and anything blocked
(gated datasets, missing licenses).
