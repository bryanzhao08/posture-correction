# Brief for Codex, batch 3: 3D hologram cue demos (ask first) + neon-orange marker tracking

Project root `/Users/bryan/Documents/GitHub/FormCoach`. Xcode 26.3 is installed; you can build and
run the UI test yourself (see "Verify"). You own `ios/FormCoach/**`, `ios/FormCoachUITests/**` and
`ios/project.yml`. Do **not** edit `ios/FormCore`, `shared/`, `ml/`, `backend/` (Claude is changing
the engine and profiles right now; the cue texts may still be edited, so never hard-code cue text:
always go through the catalog by key).

## Part A: "Want to see it?" hologram demos for every instruction

The user asked: for every coaching instruction in every sport, first **ask** whether they want to
see what it means, and if yes, show a **3D holographic animation** of it on screen.

**Data.** `shared/cue_catalog.json` (bundle it as a resource, like `sport_profiles.json`) lists all
36 cues: `key` (`sport.metric.direction`), `text` (exactly the string FormCore puts in `Rep.cues` /
`SessionSummary.topCues`), `meaning`, `wrong_motion`, `correct_motion`. Map a displayed cue string
to its entry by exact `text` match. Also cover each sport's **setup instruction** (the profile's
`camera` text: where to put the tripod): add a demo with key `setup.<sport>` that shows a phone on a
tripod in front of the figure at the described height and distance.

**Ask first.** Wherever a cue or setup instruction is shown (live session HUD under the cue,
the setup screen, the session summary's coaching focus, and session detail), show a small
prompt: "Want to see what this means?" with **Show me** and **Not now**. "Not now" collapses it to a
small "Show me" link for that cue for the rest of the session. A Settings toggle "Offer movement
demos" (default on) hides all prompts.

**The hologram.** Tapping Show me opens a full-screen sheet with:
- a SceneKit (`SCNView`) 3D mannequin built from capsules/spheres for the 13 joints plus head,
  hands and the sport implement (golf club, tennis racket, pickleball paddle, basketball),
- a holographic look: emissive cyan, additive blending, partial transparency, a moving scanline or
  shader-modifier shimmer, faint grid floor, slow camera orbit; the "wrong" version tinted red/orange,
  the "correct" version cyan,
- playback: wrong motion once, then correct motion, looping; a segmented control Wrong / Correct /
  Both, replay, and the `meaning` text plus the cue `text` as captions,
- respects Reduce Motion (no orbit, simple crossfade) and VoiceOver (captions are labels).

**Animation architecture (required: 36 hand-made animations would not be maintainable).**
Build a parametric motion system: a small set of base motions in code, each driven by named
parameters, and each catalog entry = base motion + `wrong` parameter set + `correct` parameter set.
Base motions: golf swing (address, top, impact, finish), basketball shot (dip, set point, release,
follow-through), tennis forehand / backhand / serve, pickleball dink / drive / overhead, ready stance,
tripod setup scene. Parameters such as `leadElbowBendAtTop`, `shoulderTurnDeg`, `hipSlide`,
`headSlide`, `headDrop`, `spineTiltLoss`, `tempoBackSeconds/tempoDownSeconds`, `kneeBend`,
`elbowFlare`, `releaseHeight`, `followThroughHold`, `armAcrossBody`, `guideHandPushes`, `drift`,
`backswingSize`, `paddleHeightReady`, `contactHeight`, `armExtensionAtContact`, `swingThrough`,
`unitTurnDeg`, `headTurnEarly`, `accelerationProfile`. Keep the per-cue table in one Swift file (or
JSON) keyed by catalog key so a coach could tweak it; every one of the 36 keys plus the 4
`setup.*` keys must have an entry, and a DEBUG check should assert the table covers the catalog.
Joint motion should be keyframed in joint-angle space with smooth interpolation, using realistic
timing (golf downswing ~0.25-0.3 s, basketball release ~0.4 s from dip, tennis forward swing ~0.3 s).
Handedness: mirror for left-handed users (Settings value).

## Part B: neon-orange sticker markers (golf, tennis, pickleball only)

Users can put neon-orange stickers on key points to make tracking more reliable.

- Settings (per sport, only golf / tennis / pickleball): toggle "I'm using neon-orange markers",
  with a short guide (and a `setup.markers.<sport>` hologram is a bonus, not required) on where to
  stick them: golf: back of the lead glove + club head; tennis: hitting wrist + racket tip;
  pickleball: hitting wrist + top edge of the paddle.
- Detection runs on the same serial camera queue, per frame, on the BGRA buffer, **downsampled**
  (e.g. sample every 4th pixel) to stay under ~3 ms per frame on an iPhone 14: threshold neon orange
  in HSV (hue about 10-35 degrees, high saturation and value; make the thresholds constants in one
  place), connected components on the downsampled grid, keep blobs above a minimum size, return
  normalised centroids (same coordinate convention as the joints: origin top-left, y down).
- Use: for the wrist marker, when Vision's wrist for that side has confidence below 0.5 or is
  missing, and a blob lies within 0.08 (normalised) of the last good wrist position (or of the
  elbow-to-wrist extrapolation), substitute the blob as that wrist with confidence 0.6 before
  calling `FormEngine.push`. The implement marker is the blob farthest from the body along the
  forearm direction: draw it on the overlay (orange ring) and record it in the opt-in pose
  recording as an optional extra field `"m": [[x, y], ...]` per frame (the backend stores the JSON
  as-is). Do not change what FormCore receives other than the wrist substitution.
- Overlay: orange rings on detected markers so the user can see they are picked up; a HUD hint
  "Markers: 2 found" during setup.
- Replay demo mode is unaffected.

## Verify
```
cd /Users/bryan/Documents/GitHub/FormCoach/ios && xcodegen generate
xcodebuild test -project FormCoach.xcodeproj -scheme FormCoach \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```
The UI test needs the backend: start it first in another shell from `backend/` with
`../.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000` (stop it when done) and set
`FORMCOACH_DATA_DIR` to a temp directory so it does not touch the user's real database.
Extend `FormCoachFlowTests` (or add a second test) to: tap "Show me" on a cue during the replayed
golf session, screenshot the hologram sheet, switch Wrong/Correct, close it; and open one `setup.*`
demo. Also add a unit-level check (can be in the UI test bundle or a small XCTest target) that every
catalog key has an animation entry. Look at your screenshots: a black or empty SceneKit view is a
failure. Report: files changed, test results, and screenshots' paths.
