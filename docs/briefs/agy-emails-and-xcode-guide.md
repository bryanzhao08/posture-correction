# Brief for Antigravity: email templates and the Xcode deployment guide

## What FormCoach is
A consumer iPhone app that watches a user practise golf, basketball, tennis or pickleball from a
tripod, scores their form against professionals, and emails them progress reports. Project root:
`/Users/bryan/Documents/GitHub/FormCoach`. Read `docs/CONTRACTS.md` first.

You own **only** these three files; do not edit anything else (other agents are working in the
rest of the tree right now):

## Task 1: `backend/app/email_templates.py`
Implement the two functions in CONTRACTS.md section 3 exactly as specified (pure functions,
standard library only, returning `(subject, html_body, text_body)`).

- **Session email**: sent after every session. Lead with the session score and the change versus
  the user's previous average; then reps and duration; a table of metrics (their value, their
  previous average, the pro target, and a better/worse marker); then the top coaching cues as
  "what to work on next".
- **Checkpoint email**: sent every 5 sessions. Lead with the average score of this block versus
  the previous block; then the same metric table (this block vs previous block vs pro); then the
  focus cues.
- Handle the first-ever session/checkpoint, where `previous`, `score_delta`,
  `previous_avg_score` and `direction` are `None`. No "None" or "nan" may ever appear in output.
- HTML must work in real mail clients: table layout, inline styles only, no external CSS, images,
  fonts or scripts; max width about 600px; readable in dark mode. HTML-escape every string that
  comes from the user or the data. Round numbers sensibly (scores to whole numbers, metric values
  to at most 2 decimals) and show units.
- Tone: encouraging and specific, plain language, no hype.

## Task 2: `backend/tests/test_email_templates.py`
pytest tests for the above: normal data, first-session data with the `None` fields, HTML
escaping of a hostile user name such as `<script>alert(1)</script>`, and that neither body
contains "None" or "nan". Run them with
`/Users/bryan/Documents/GitHub/FormCoach/.venv/bin/python -m pytest backend/tests/test_email_templates.py -q`
from the project root and make them pass. (`backend/app/__init__.py` may not exist yet; create it
empty if you need it, and that is the only extra file you may add.)

## Task 3: `docs/XCODE_DEPLOY.md`
A step-by-step guide teaching a first-time iOS developer to get this app onto their own iPhone.
The reader has a Mac (Apple Silicon, macOS 15.6) with **no Xcode installed**, about 50 GB free
disk, Homebrew installed, and has never deployed an app. Cover, in order:
1. Installing Xcode from the Mac App Store (disk space needed, first-launch component install,
   `sudo xcode-select -s /Applications/Xcode.app`, accepting the licence).
2. `brew install xcodegen`, then `cd ios && xcodegen generate` to create `FormCoach.xcodeproj`
   from `ios/project.yml`, and opening it.
3. Signing with a free Apple ID ("Personal Team"): adding the account in Xcode settings, picking
   the team under Signing & Capabilities, changing the bundle identifier to something unique.
   State the free-account limits honestly (apps expire after 7 days, limited app IDs) versus the
   paid Apple Developer Program (needed for TestFlight and the App Store).
4. Preparing the iPhone: cable, "Trust This Computer", enabling Developer Mode
   (Settings > Privacy & Security > Developer Mode, restart), trusting the developer certificate
   (Settings > General > VPN & Device Management).
5. Build and run; why the Simulator is not enough here (no camera, so pose tracking needs a real
   device).
6. Pointing the app at the backend running on the Mac: start it with
   `.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000` from `backend/`, find the Mac's
   LAN IP, put `http://<ip>:8000` in the app's Settings, both devices on the same Wi-Fi.
7. A troubleshooting table for the common failures (signing errors, "Untrusted Developer",
   device not showing up, Developer Mode missing, camera permission denied, cannot reach
   backend).
8. A short "what shipping to the App Store would additionally require" section.

Only state menu names and steps you are confident are correct for current Xcode; where a label
may differ between Xcode versions, say so instead of guessing.

## When done
Reply with the files you wrote, the test result, and anything you were unsure about.
