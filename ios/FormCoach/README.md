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
The full application has not been built or launched in the Simulator; that end-to-end test remains
with the delegating agent when the Simulator platform/runtime download completes.

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
- Full app login → replay → summary → backend upload → history remains to be tested in the
  Simulator. The native replay test verifies the actual source/pipeline, not SwiftUI presentation,
  Keychain, networking or physical haptics.

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
and real-time verification above; visual layout and full app runtime checks are still outstanding.
