# Brief for Antigravity, batch 2: backend packaging, pose debug renderer, privacy policy

Project root: `/Users/bryan/Documents/GitHub/FormCoach` (always use absolute paths or `cd` there
first; your shell starts in the home directory). Context is in `docs/CONTRACTS.md`.

Other agents are editing the rest of the tree. You own **only** the files listed below. Do not
edit any existing file, including `backend/app/*.py`, `ml/formcoach/*`, `ml/datasets.py`,
`ml/extract_pose.py` and `shared/sport_profiles.json`. Read them as much as you like.

## Task A: backend packaging (4 new files)
The backend is a FastAPI app in `backend/app/` (entry point `app.main:app`, run from `backend/`),
SQLite via SQLAlchemy, JWT auth, and email through the Resend HTTP API. Read
`backend/app/config.py` and `backend/app/emailer.py` first; they are the source of truth.

1. `backend/requirements.txt`: runtime dependencies pinned to what is installed and tested:
   `fastapi==0.142.2`, `uvicorn[standard]==0.54.0`, `SQLAlchemy==2.1.2`, `PyJWT==2.15.1`,
   `bcrypt==5.0.0`, `httpx==0.28.1`, `pydantic==2.13.5`, `email-validator==2.3.0`.
   Put `pytest` in a separate `backend/requirements-dev.txt`.
2. `backend/.env.example`: every environment variable `config.py` reads, each with a one-line
   comment, safe placeholder values only (no real secrets).
3. `backend/Dockerfile`: small production image (python:3.12-slim, non-root user, the data
   directory as a volume, uvicorn on port 8000). Note that `config.py` reads
   `shared/sport_profiles.json` relative to the repository root, so the build context must be the
   repository root and both `backend/` and `shared/` must be copied preserving that layout.
4. `backend/README.md`: how to run locally (venv, install, `uvicorn app.main:app --reload`),
   how to run the tests (`python -m pytest backend/tests -q` from the root), the environment
   variables, how to get a Resend API key and verify a sending domain (and that without a key,
   emails are written to `backend/data/outbox/` for inspection), how to build and run the Docker
   image, and a short "before real users" checklist: HTTPS in front, a fixed
   `FORMCOACH_JWT_SECRET`, Postgres via `FORMCOACH_DATABASE_URL`, backups, and that the in-memory
   login limiter is per-process. Do not invent endpoints: take them from `docs/CONTRACTS.md`.

Do not try to verify the Dockerfile by building it (Docker is not installed here); say so in
your report.

## Task B: `ml/tools/render_pose.py` (new file)
A debugging tool to visually check pose tracking and rep detection.

`python ml/tools/render_pose.py <recording.json> <out.mp4> [--sport golf] [--video original.mp4]`

- A recording is `{"fps", "aspect", "frames": [{"t": seconds, "j": [[x, y, conf] * 13]}]}` with
  normalised coordinates (origin top-left) and joints in the order listed in
  `shared/sport_profiles.json` under `"joints"`. Examples appear in `ml/data/poses/` once
  extraction has run; `ml/formcoach/synth.py`'s `recording()` generates synthetic ones.
- Draw the skeleton (bones between the 13 joints; skip joints with conf < 0.3) on the original
  video frames when `--video` is given, otherwise on a dark canvas of the recording's aspect.
- When `--sport` is given, run the engine frame by frame
  (`formcoach.engine.Engine(profiles, sport, handedness).push(t, joints, aspect)`, with
  `load_profiles()` from the same module; read `ml/formcoach/engine.py` for the API) and overlay:
  the current `engine.state`, the running rep count, the tracked hand speed, and a flash plus
  the rep score when a rep is counted, or the rejection reason when a motion is rejected.
- Use OpenCV only (`cv2`, already installed in `/Users/bryan/Documents/GitHub/FormCoach/.venv`).
  Add `ml/` to `sys.path` from the script so it runs from anywhere.
- Verify it: generate a synthetic golf recording with `synth.recording("golf", [("rest", 1.5),
  ("golf_swing",), ("rest", 1.5)])`, save it under the system temp directory, render it with
  `--sport golf`, and confirm the output file is a readable video with the expected frame count.

## Task C: `docs/PRIVACY.md` (new file)
A plain-language privacy policy **draft** for the app, plus the App Store "privacy nutrition
label" answers. Base it strictly on what the system actually does:
- The camera video is processed on the phone and is never uploaded or stored.
- Uploaded per session: sport, time, duration, rep counts, per-rep form metrics and scores.
- Only if the user opts in: body-pose keypoints (13 joint positions per frame, no images).
- Account data: name, email, bcrypt-hashed password. Emails (session and checkpoint reports) are
  sent through Resend, a third-party processor, and can be switched off in Settings.
- Account deletion in the app removes the account, sessions, checkpoints and stored keypoints.
- No ads, no third-party analytics, no data sale.
Mark clearly at the top that it is a draft that needs review by a lawyer before publication, and
leave bracketed placeholders for company name, contact email and jurisdiction.

## When done
Reply with the files written, how you verified Task B, and anything you were unsure about.
