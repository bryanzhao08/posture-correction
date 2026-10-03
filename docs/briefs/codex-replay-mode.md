# Brief for Codex, batch 2: DEBUG replay mode so the app can be tested in the Simulator

Good news first: Xcode is now installed, and your app type-checks against the iOS 26.2 SDK with
**0 errors** (6 Swift 6 concurrency warnings, fine in Swift 5 mode). The real `FormCore` package
now exists in `ios/FormCore` and matches the Python engine exactly.

## Problem
The iOS Simulator has no camera, so the session screen cannot be exercised there. We need to test
the whole flow (log in, run a session, see reps counted, summary, upload, history) in the
Simulator against the local backend.

## Task
Add a **DEBUG-only replay source** that feeds a recorded pose session through the same pipeline
the camera uses.

- Recordings are in `ios/FormCoach/DebugFixtures/{golf,basketball,tennis,pickleball}_demo.json`,
  format `{"sport","handedness","fps","aspect","frames":[{"t": seconds, "j": [[x, y, conf] * 13]}]}`
  (normalised, origin top-left, joints in `Profiles.joints` order). Bundle them as resources in
  DEBUG builds only (or bundle always but only reference them under `#if DEBUG`).
- When there is no camera (Simulator: `#if targetEnvironment(simulator)`), or when a DEBUG
  setting "Replay demo session" is on, the session screen uses the replay instead of
  `AVCaptureSession`. Play the sport's fixture frames in real time on the same serial queue,
  through the same path as camera frames: the same setup check, countdown, `FormEngine.push`,
  `CameraFrameState` publishing, skeleton overlay (on a dark background instead of the preview),
  haptics, and summary. Use the recording's `t` values as timestamps. The expected result per
  fixture: golf 3 swings, basketball 2 shots, tennis forehand + backhand + serve, pickleball 2.
- The upright-phone check uses CoreMotion, which is unavailable in the Simulator: treat it as
  passing in replay mode.
- When the recording ends, keep the last frame visible; the user ends the session with the
  normal End button.
- Do not change any release-build behaviour, `ios/FormCore`, or anything outside
  `ios/FormCoach/**` and `ios/project.yml`.

## Verify (you can compile now)
From `/Users/bryan/Documents/GitHub/FormCoach/ios`:
```
xcodegen generate
xcrun swiftc -emit-module -module-name FormCore -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -target arm64-apple-ios17.0 -swift-version 5 FormCore/Sources/FormCore/*.swift \
  -emit-module-path /tmp/fc/FormCore.swiftmodule
xcrun swiftc -typecheck -module-name FormCoach -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios17.0-simulator -swift-version 5 -I /tmp/fc $(find FormCoach -name '*.swift')
```
(build the FormCore module for the simulator SDK/target too for the second command, into a
separate directory). The iOS platform for full `xcodebuild` builds is still downloading; Claude
will run the full build and the Simulator test once it lands. Report 0 errors from the
type-check, and list the files you changed.
