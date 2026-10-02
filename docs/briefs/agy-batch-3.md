# Brief for Antigravity, batch 3: iOS code review and pickleball data-collection protocol

Project root: `/Users/bryan/Documents/GitHub/FormCoach` (use absolute paths). You may create
**only** the two files named below. Do not edit any existing file: this batch is review and
documentation only.

## Task A: `docs/reviews/ios-review.md` (new file)
Another agent (Codex) wrote the iOS app in `ios/FormCoach/` and `ios/project.yml`. Xcode is not
installed on this machine, so **none of it has ever been compiled**. Your job is to be the
compiler and the reviewer: read every Swift file and report what will break. Do not fix anything.

Check, in this order of importance:
1. **Compile errors.** Wrong or non-existent API names and signatures (SwiftUI, AVFoundation,
   Vision, CoreMotion, Charts, Security/Keychain), type mismatches, missing imports, optional
   misuse, non-exhaustive switches, use of members that do not exist. The target is iOS 17,
   Swift language mode 5. Where you are not sure an API exists with that exact signature, say
   "uncertain" rather than asserting.
2. **Mismatches with `ios/FormCore`.** The package's public types are in
   `ios/FormCore/Sources/FormCore/Models.swift` (the engine class `FormEngine` is specified in
   `docs/CONTRACTS.md` section 1 and is being ported now). List every place the app uses a FormCore
   name, initializer, property or case that does not match.
3. **Mismatches with the backend.** Compare the app's request/response models and paths
   (`ios/FormCoach/Services/`) with `docs/CONTRACTS.md` section 2 and the real implementation in
   `backend/app/main.py`: field names, optionality, status codes, JSON coding keys.
4. **Concurrency and lifecycle bugs.** Main-actor violations, capture session started on the
   main thread, retain cycles, UI updated from background queues, camera not stopped when the
   view disappears.
5. **`ios/project.yml`.** Will `xcodegen generate` produce a buildable project: the local
   package reference, the bundled `shared/sport_profiles.json` resource path, Info.plist keys.

Format: a table of findings sorted by severity (blocker / likely / minor), each with
`file:line`, what is wrong, and the exact suggested fix. End with a short list of things you
checked and found correct, so the reader knows the coverage.

## Task B: `docs/DATA_COLLECTION.md` (new file)
There is no public pickleball stroke or pose dataset, so pickleball detection is currently
unvalidated. Write a practical protocol for collecting a first validation set ourselves:
- What to record: which strokes (dink, drive, volley, overhead, serve; forehand and backhand),
  how many reps per stroke per player, how many players and what skill mix, plus deliberate
  "should not count" footage (standing, walking, picking up balls, bouncing the ball, practice
  motions without intent).
- How to record it so it matches the app: phone on a tripod, face-on, chest height, 3-5 m away,
  full body in frame, portrait, 60 fps if available, even lighting, one player in frame.
- How to label it cheaply: one row per stroke in a CSV (clip file, start time, contact time,
  stroke type, hand, player id, skill level) and how the app's opt-in pose upload
  (`POST /sessions/{id}/keypoints`, see `docs/CONTRACTS.md`) can supply recordings without video.
- How the data will be used: a player-level train/verification split (no player in both), the
  metrics that will be reported (count accuracy, false counts per minute of idle footage, stroke
  type accuracy, expert-vs-beginner separation), mirroring `ml/validate.py` and
  `ml/fit_reference.py`, which you should read first.
- Consent and privacy notes for recording other people.
Keep it concrete and under about 150 lines.

## When done
Reply with the number of findings by severity and anything you could not determine.
