# FormCoach iOS handoff

Implemented against `docs/CONTRACTS.md`. The app owns presentation, Vision-to-joint mapping,
setup gating and persistence; only FormCore counts, rejects and scores reps.

## Build on a Mac with Xcode

From `ios/`, run `xcodegen generate --spec project.yml`, then open `FormCoach.xcodeproj`.
Select a signing team for `com.formcoach.app` and build the FormCoach scheme on a physical
iPhone running iOS 17 or newer. Swift language mode is 5.0. FormCore is a local package and
`shared/sport_profiles.json` is a resource in the app bundle. No external libraries are used.

The app now type-checks with **0 errors** in DEBUG and release mode for both arm64 device and
arm64 Simulator, targeting iOS 17 with the iOS 26.2 SDK. Existing Swift 6 concurrency warnings
remain in Swift 5 mode. XcodeGen project generation and fixture resource references were verified.
The full app was subsequently built and tested in the Simulator; see the batch 3 results below.

## Operation

- Auth stores the access token only in Keychain. Public user metadata in UserDefaults permits
  immediate offline restoration. Server/account-specific Application Support directories hold
  atomic session JSON and cached stats, history, details, checkpoints and preferences.
- Every ended session reaches disk before any POST. Persistent client UUIDs make retries
  idempotent; offline sessions replay oldest first so comparisons follow practice order. Retry on launch, foreground entry, explicit Retry, or a successful authenticated
  request. Account preference changes also queue for offline sync. An account-generation guard
  prevents late responses from modifying a different account after logout/server changes.
- Front camera preview is mirrored; data buffers are unmirrored and rotated to portrait.
  Vision points preserve anatomical labels, use `y = 1 - y`, and follow `Profiles.joints` order.
  Preview and skeleton both use aspect-fit geometry so ankles cannot be cropped by a tall screen.
- Capture configuration, Vision, FormEngine.push and summary snapshots share one serial queue.
  Frames use presentation timestamps and late frames are discarded. The main actor publishes UI.
- Before counting, nose/ankles need confidence >= 0.3 and a small edge margin; nose-to-ankle
  height must be 45–90% of the image. Device-motion gravity checks portrait uprightness. The
  framing/alignment conditions must hold throughout a 3-second countdown. FormCore then waits
  for stillness/arming itself. Camera switches are disabled during an active motion, preserve
  accumulated reps, and repeat setup; missing observations during re-setup disarm FormCore.
- Backgrounding or capture interruption ends and saves a session. Ending does not synthesize
  a final rep or flush an incomplete motion: the contract exposes no flush/end API.
- Screen wake state is restored at session exit. Each FormCore rep produces a haptic and system
  sound; speech is optional, skips overlapping utterances, and stops when disabled.
- Pose sharing defaults off. Collection is snapshotted at session start; uploads additionally
  require current opt-in. Revoking consent removes queued recordings. Uploaded raw frames are
  removed locally after successful upload. Frames already transmitted cannot be recalled by
  the toggle. Video/photo/audio data is never recorded.
- Cached history renders offline. Online history refresh warms missing detail caches for the
  returned 50 sessions; details never received from the server remain unavailable offline.
  Local sessions and their detail/metrics always remain available, and appear in the trend
  immediately. Statistics and comparisons use server results.
- Development backend URL is editable at login and in Settings in DEBUG builds. Changing it
  logs out. Default is http://localhost:8000; on a physical iPhone use your Mac's LAN hostname
  or private IP. The plist permits local networking and HTTP private IPv4 ranges. Set the
  production endpoint before release distribution and choose signing configuration in Xcode.

## Contract assumptions / missing interfaces

1. Recording.j does not specify missing-joint representation. The app sends 13 numeric triples
   and uses `[0, 0, 0]` for a missing joint (zero confidence), rather than null. Recording timestamps
   share the exact camera-presentation timebase with reps; the example's relative times are not
   interpreted as a requirement to subtract an origin.
2. FormEngine has no finish/flush/cancel method. End/interruption snapshots only completed reps.
   Incomplete motion handling remains FormCore's responsibility.
3. The contract does not define a confidence threshold or upright tolerance for setup. The app
   uses confidence 0.3, gravity y < -0.8, |x| < 0.25 and |z| < 0.55.
4. Stats does not expose last_score. Home uses the newest trend point, with newer local sessions
   taking precedence, and includes locally queued sessions in the session count.
5. FormCore exposes only the aggregate MetricSpec target. Summary displays mean ± tol; any
   sport/type-specific target treatment remains in FormCore scoring and server comparisons.
6. System sound 1057 is used for rep feedback; physical-device audibility must be verified.

## DEBUG demo replay

In the Simulator, a DEBUG session always uses the sport's bundled demo. On a device, enable
Settings → Development session source → **Replay demo session** (or replay is selected if the
front camera is unavailable). This setting is immediate and applies to the next session.

Replay never requests camera access or starts capture/CoreMotion. It draws the normal skeleton
on a dark background, treats uprightness as passing, and otherwise uses the same
`PoseSessionPipeline` as camera frames: framing check, countdown, FormEngine events, HUD,
haptics/speech, summary, local save and uploads. Fixture handedness is used consistently in the
engine and uploaded session/recording rather than analyzing right-handed demos as left-handed.

The source holds the initial pose for a three-second setup pre-roll because the recordings start
moving about two seconds in. These setup-only samples precede the fixture timebase; every actual
fixture frame keeps its original `t`. A timer runs on the capture serial queue and catches up
without dropping poses. At EOF it cancels the timer, keeps the last frame visible, and shows
“Demo complete · tap End session.” Ending early cancels playback and saves completed reps normally.

`ReplayDemoSource` and the setting are compiled only under `#if DEBUG`. The JSON fixtures are
bundled in all configurations (the brief permits this); release code never references them.
Camera permissions, motion checks and live-session processing retain their prior release behavior.

## Verification and remaining runtime checks

- Type-checked all app Swift sources with `-D DEBUG` and without it for arm64 iOS device and
  arm64 Simulator, using separately built matching FormCore modules: **0 errors in all four checks**.
- Generated the XcodeGen project inside a temporary directory in the assigned app path and
  checked that all four demo JSON files appear in Copy Bundle Resources and DEBUG is configured.
- Compiled the actual `ReplayDemoSource`, shared pipeline and FormCore into a native verification
  executable. Played all four fixtures concurrently in real time on a serial queue. Checked
  countdown 3/2/1, original timestamps, all recorded frames reaching the opt-in recording,
  matching rep events and last HUD/frame state, and real-time duration (within 0.5 seconds).
  Results: golf **3 swings**, basketball **2 shots**, tennis **forehand + backhand + serve**,
  pickleball **2 forehands**. Temporary verification outputs were removed after checking.
- The earlier native replay check verified the source/pipeline. The batch 3 UI test below now
  also verifies registration, SwiftUI presentation, networking, summary upload and history.

On-device checks needed: preview/skeleton alignment on front and back cameras; permissions and
local-network/ATS access; countdown reset on bad framing; engine transitions and idle rejection;
background/interruption saving; Keychain restore; offline restart/history; retries without duplicate
sessions; preference edits while syncing; opt-out while an upload is queued; first-session null
comparisons; deletion confirmation/server failure; 375-point layouts and largest Dynamic Type;
VoiceOver controls and chart descriptions; long-session raw pose memory/storage performance.

API choices were checked against the official references:
- https://developer.apple.com/documentation/vision/vnhumanbodyposeobservation
- https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
- https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

## Static checks performed

Parsed project.yml with Ruby YAML and checked deployment, language mode, local-package and
resource entries. `plutil -lint` passed for Info.plist. Parsed every asset JSON, verified the icon
is opaque RGB at 1024×1024 and inspected it visually, checked shared joint/sport mapping, and
ran a simple delimiter scan of the original 18 Swift sources. Reviewed source files, token
persistence and explicit CodingKeys. The later replay task added the type-check/project-generation
and real-time verification above. Batch 3 adds the actual Simulator build, UI flow and screenshot review below.


## Batch 3: hologram demos and orange markers

Completed within `ios/FormCoach/**`, `ios/FormCoachUITests/**`, and `ios/project.yml`.
No FormCore, shared catalog/profile, backend, or ML source was edited.

### Implementation

The bundled cue catalog resolves displayed cues by exact text and sport. Live cues, setup camera
instructions, summary focus, checkpoint focus, rep cues and session details use the shared
ask-first prompt. “Not now” persists for that cue/session, and “Offer movement demos” defaults on.
A stable presentation host keeps the full-screen demo open when the live setup countdown ends.
Tripod instructions remain available through an explicit 44-point control during counting.

`DemoMotionTable.swift` contains all 36 catalog entries and four setup entries. Ten shared base
motions use smooth joint-angle keyframes with parameter overrides and realistic swing/release
timing. SceneKit renders the mannequin, sport implements, tripod/phone, emissive additive colors,
moving scanline and floor grid. Wrong/Correct/Both, Replay, handedness mirroring, Reduce Motion
crossfades and accessible captions are implemented. Catalog/table coverage is asserted in DEBUG.

Per-sport marker preferences and sticker guides cover golf, tennis and pickleball. The serial
camera queue samples BGRA every fourth pixel, thresholds centralized orange HSV constants and
finds connected components. Only a low-confidence/missing wrist near a fresh known wrist or
forearm extrapolation can be replaced, at confidence 0.6. Golf uses the non-dominant wrist;
racket sports use the dominant wrist. The farthest marker along the forearm identifies the
implement. All detections appear as orange rings, with a setup count. Opt-in recordings include
optional `m` centroid arrays; replay uses its original joints and no marker detection.

### Files changed

- New: `Demos/CoachingInstruction.swift`, `Demos/DemoMotionTable.swift`, `Demos/HologramDemo.swift`.
- New: `Camera/OrangeMarkerTracker.swift`.
- Updated: `App/AppState.swift`, `App/FormCoachApp.swift`.
- Updated: `Camera/CameraManager.swift`, `Camera/PoseSessionPipeline.swift`,
  `Camera/SessionController.swift`, `Camera/SkeletonOverlay.swift`.
- Updated: `Services/Models.swift`.
- Updated: `Views/SessionView.swift`, `Views/SettingsView.swift`, `Views/SummaryView.swift`,
  `Views/HistoryView.swift`.
- Updated: `../FormCoachUITests/FormCoachFlowTests.swift`; new
  `../FormCoachUITests/OrangeMarkerTests.swift`.
- Updated: `../project.yml`, this `README.md`.

Paths without a leading `../` are relative to this app directory. Generated projects, build
outputs, test logs, temporary backend data and screenshots are under
`../FormCoachUITests/Artifacts/Batch3/`, excluded from target sources.

### Verification results

Xcode 26.3 (17C529), iOS Simulator SDK 26.2, iPhone 16 Pro on iOS 18.5.
XcodeGen generation passed. The latest `xcodebuild build-for-testing` passed; the matching
`test-without-building` run passed **5 tests, 0 failures**, including:

- Catalog coverage: 36 unique catalog keys, four setup keys, differing wrong/correct parameters,
  and every base motion represented.
- BGRA synthetic blobs: centroid coordinates, separated components and tiny-speck rejection.
- Wrist fallback: confidence gating, preserving other joints, proximity rejection and implement selection.
- Dominant-side extrapolation and rejection of stale wrist history.
- Registration → golf replay → cue demo → Wrong/Correct/Replay → close → tripod setup demo →
  Correct → close → three counted reps → synced summary → history.

The UI test starts with a fresh login only when both explicit UI-test/reset arguments are present
in a DEBUG Simulator build. Its default backend is `http://localhost:8000`. For this verification,
port 8000 was already occupied, so the generated verification scheme supplies
`FORMCOACH_UI_TEST_BACKEND=http://127.0.0.1:18004`. The isolated server used
`FORMCOACH_DATA_DIR=ios/FormCoachUITests/Artifacts/Batch3/backend-data` and was stopped after testing.
The installed iPhone 16 Pro runtime is 18.5, so the destination specifies `OS=18.5`.
The generated verification project's app plist path was adjusted because it lives below `ios/`.

Results: `../FormCoachUITests/Artifacts/Batch3/TestsReviewed.xcresult`.
Build log: `../FormCoachUITests/Artifacts/Batch3/build-reviewed.log`.
Test log: `../FormCoachUITests/Artifacts/Batch3/test-reviewed.log`.

Reviewed screenshots are under `../FormCoachUITests/Artifacts/Batch3/ReviewedScreenshots/`:

- `3b-golf-hologram-both.png`
- `3c-golf-hologram-wrong.png`
- `3d-golf-hologram-correct.png`
- `4a-setup-hologram.png`
- `4b-setup-hologram-correct.png`
- `5-summary.png`, `6-summary-scrolled.png`, `7-history.png`.

Inspected the golf wrong/correct and tripod wrong/correct images: the mannequin, club, phone and
tripod render visibly; the SceneKit views are not black or empty. The final scanline is faint.
Physical iPhone 14 marker latency (~3 ms target), real lighting/stickers, and physical camera
alignment still require device measurement; Simulator tests do not establish those results.

## Batch 4: hologram quality and review

The procedural skeleton now uses adult limb lengths and two-bone IK. Golf keeps both hands on
one grip and turns around the tilted address spine; basketball separates the guide hand at
release and keeps the ball's flight independent of the follow-through hand. Tennis includes a
one-handed backhand and serve toss; pickleball includes ready, compact groundstroke, and overhead
poses. The motion table maps each catalog entry to its own posture or timing parameter.

The renderer uses translucent additive material, a Fresnel rim, moving scan band, bloom, subtle
flicker, and a grid/ring floor. Both plays one shared clock with an orange ghost behind cyan.
Rotation guides use reusable nodes; setup demos show a phone, tripod, full-body frustum, distance
label, and red clipping indication. Reduce Motion freezes the comparison pose and scan band.

In DEBUG builds, Settings → Demo gallery lists 40 entries by sport. Key moment pauses positional
cues at the same swing phase and timing cues at the same elapsed second. Replay resumes motion.
`DemoGalleryReviewTests.testSlowReviewEveryWrongAndCorrectKeyMoment` is intentionally slow and
attaches `<key>-wrong.png` and `<key>-correct.png` for every entry. Export its xcresult attachments
with `xcrun xcresulttool export attachments`; use the manifest's human-readable names to recover
the key/mode (the export tool adds an index and UUID). Keep generated projects, DerivedData,
xcresult bundles, exported screenshots, and logs under `/tmp/formcoach-codex/`.

Current UI tests default to `http://127.0.0.1:18004`. Start their isolated backend from `backend/`:
`FORMCOACH_DATA_DIR=/tmp/formcoach-codex/backend ../.venv/bin/uvicorn app.main:app --port 18004`.
Do not run tests against the user's normal backend on port 8000.

These are illustrative keyframes, not motion-capture measurements. In particular, the low-ball
leg load in `tennis.contact_height.high` and `pickleball.contact_height.high` is exaggerated for
visibility and should receive coach review. Serve toss/ball flight and the one-handed backhand
are stylized; full-body sequencing is not validated against an athlete capture.

### Batch 4 verification

The final iPhone 16 Pro / iOS 18.5 Simulator run passed **10 tests, 0 failures**:
four anatomy checks, catalog coverage, the complete 40-entry gallery audit, the registration /
practice / demo / sync / history flow, and three marker-tracking checks. The gallery audit took
574 seconds and saved all 80 Wrong/Correct key-moment screenshots. An independent sweep of all
40 entries, both variants, at 20 ms intervals found zero arm-chain length violations.

Results: `/tmp/formcoach-codex/batch4/quality-audited.xcresult`.
Build log: `/tmp/formcoach-codex/batch4/build-final.log`.
Test log: `/tmp/formcoach-codex/batch4/quality-audited.log`.
Reviewed gallery: `/tmp/formcoach-codex/gallery/`, containing exactly 80 files named
`<key>-wrong.png` / `<key>-correct.png`. All pairs were visually inspected using four sport
contact sheets; head-direction, elbow-flare, stance-height, and phone/frustum details were also
inspected at full resolution. Contact sheets and attachment manifests remain under
`/tmp/formcoach-codex/batch4/audited-attachments/`.

The gallery supports search and uses the existing coaching-demo presenter. Each cue receives
fresh playback state. Frozen comparisons stop continuous rendering, and closing a demo detaches
its scene and actions. SceneKit geometry is omitted from the accessibility tree; the cue text,
Wrong/Correct controls, Replay, Key moment, and Close remain accessible.

Changed files: `App/FormCoachApp.swift`, `Demos/CoachingInstruction.swift`,
`Demos/DemoGallery.swift`, `Demos/DemoMotion.swift`, `Demos/DemoMotionTable.swift`,
`Demos/HologramDemo.swift`, `Views/SettingsView.swift`, this README,
`../FormCoachUITests/DemoGalleryReviewTests.swift`,
`../FormCoachUITests/FormCoachFlowTests.swift`, and `../project.yml`.

Coach review remains appropriate for the exaggerated low-ball knee load in
`tennis.contact_height.high` / `pickleball.contact_height.high`, the exaggerated lateral
upper-body lean in `golf.head_sway.high`, and the stylized serve toss and one-handed backhand
sequencing. These illustrative poses do not establish athlete-level biomechanics.
