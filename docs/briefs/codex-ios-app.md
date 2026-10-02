# Brief for Codex: build the FormCoach iOS app

## What FormCoach is
A consumer iPhone app. The user puts the phone on a tripod **in front of them (face-on)**, picks
a sport (golf, basketball, tennis, pickleball), and practises. The app tracks their body pose
live, counts only real swings/shots (never idle movement), scores each rep against professional
reference ranges, shows coaching cues, saves every session, and uploads it to a backend that
emails progress reports.

Project root: `/Users/bryan/Documents/GitHub/FormCoach`. Read `docs/CONTRACTS.md` first: it is
the binding interface for the analysis engine (`FormCore`) and the backend REST API.

## Your job
Write the whole iOS app. You own **only** these paths; do not edit anything else:
- `ios/FormCoach/**` (app sources, assets, Info.plist if needed)
- `ios/project.yml` (XcodeGen spec that generates `FormCoach.xcodeproj`)

Someone else is writing `ios/FormCore` (the Swift package from CONTRACTS.md section 1) and the
backend at the same time. Code against the contract exactly; do not reimplement the analysis,
rep counting or scoring in the app.

## Hard constraints
- **Xcode is not installed on this machine**, so nothing can be compiled or run. Write
  conservatively: only APIs you are sure exist, no experimental features, and re-read every file
  for type errors before finishing. Say plainly in your report that it is uncompiled.
- SwiftUI, iOS 17.0 deployment target, Swift language mode 5 (`SWIFT_VERSION: "5.0"`), iPhone
  only, portrait only. No third-party dependencies.
- `project.yml`: app target `FormCoach`, bundle id `com.formcoach.app`, local package
  `FormCore` at `ios/FormCore`, and `../shared/sport_profiles.json` bundled as a resource.
  Info.plist keys: `NSCameraUsageDescription`, portrait-only orientation, and
  `NSAppTransportSecurity` allowing local networking (the dev backend is plain http on the LAN).
- JSON: explicit `CodingKeys`, never the snake-case key strategies (see CONTRACTS.md).
- Access token in the Keychain, never in UserDefaults.

## Screens and behaviour
1. **Auth**: register (name, email, password) and log in. Show server error text. Stay logged in
   across launches.
2. **Home**: four sport cards. Each shows last score and session count (from `/stats/{sport}`,
   cached so it works offline).
3. **Session (the core screen)**
   - Full-screen camera preview with the skeleton drawn over the body. Front camera by default
     (so the user can see themselves from the tripod), with a switch to the back camera.
   - `AVCaptureSession` + `AVCaptureVideoDataOutput` on a background serial queue, Vision
     `VNDetectHumanBodyPoseRequest` per frame, map the 13 joints in contract order (convert
     `y = 1 - y`), call `FormEngine.push` on that same queue, publish UI state on the main actor.
     Use the frame's presentation timestamp for `t`. Drop late frames
     (`alwaysDiscardsLateVideoFrames = true`). Keep the screen awake during a session.
   - **Setup check before counting starts**: show the sport's `camera` instruction text; require
     the full body in frame (nose and both ankles visible, body height between 45% and 90% of
     the frame) and the phone roughly upright (CoreMotion); then a 3-second countdown.
   - Live HUD, readable from 4 metres away: big rep count, a state pill driven by
     `engine.state` (No person / Get set / Ready / Swinging), last rep score, and the top cue of
     the last rep. Short haptic + system sound on each counted rep. Optional spoken cue
     (`AVSpeechSynthesizer`) with a toggle, since the user is far from the screen.
   - End button -> summary.
4. **Summary**: session score, reps, each metric as a row (user average, pro target, 0-100 bar),
   top cues, and how many motions were ignored and why (`rejected`), so the user can trust the
   count. After upload, show `comparison` from the server (better/worse vs their previous average).
5. **History**: sessions list per sport (`/sessions`), detail view, and a simple score trend
   chart using Swift Charts (`/stats/{sport}` `trend`). Checkpoints list (`/checkpoints`).
6. **Settings**: handedness, email reports on/off (`PATCH /me`), spoken cues toggle, opt-in
   "share pose data to improve accuracy" (uploads the raw recording to
   `/sessions/{id}/keypoints`; default off), backend URL (debug), log out, **delete account**
   (`DELETE /me`, with confirmation; the App Store requires this).

## Data rules
- **Every session is saved locally first** (JSON files in Application Support), then uploaded.
  Failed uploads stay queued and retry on next launch / next successful request. `client_id`
  (a UUID per session) makes retries idempotent.
- The app must be fully usable offline after login, except for server comparisons.

## Suggested layout
`App/` (entry, AppState), `Services/` (APIClient, KeychainStore, SessionStore, models),
`Camera/` (CameraManager, PoseDetector, CameraPreview, SkeletonOverlay, SessionController),
`Views/` (one file per screen).

## When done
Reply with: files created, anything in the contract that was ambiguous or that you needed and
did not have, and every place you are unsure the code compiles.
