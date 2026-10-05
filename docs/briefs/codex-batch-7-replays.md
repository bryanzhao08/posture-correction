# Brief for Codex, batch 7 (after batches 5 and 6): "Replay with fix" clips

User request: for each session with errors, save a low-resolution video of the swing with the pose
points drawn clearly, plus what the pose should actually have been, so the result is easy to see.

House rules unchanged (build output in /tmp/formcoach-codex/, test backend on 18004, never 8000).
You own `ios/**`. Do not edit `ml/`, `shared/`, `backend/`. Commit when done, do not push.

## Part 1: port the correction rules (acceptance: parity)
Claude wrote `ml/formcoach/corrections.py` (with `ml/tests/test_corrections.py`): given the
player's pose at a rep's key moment, it returns the same pose with only the faulty limb moved to
the target, keeping bone lengths. Port it to `ios/FormCore/Sources/FormCore/Corrections.swift`
(public `correctedPose(analyzer:metric:target:pose:ref:torso:dominant:repType:) -> [String: Point]?`
plus the public `EVENTS` table as `correctionEvent(analyzer:metric:) -> (event: String, ref: String?)?`;
make `Point` public if needed). Add a `--corrections <file>` mode to `formcore-check` that reads a
JSON array of `{analyzer, metric, target, pose, ref, torso, dom, expected}` (points are `[x, y]`
arrays; `expected` may be null) and compares within 1e-6.
**Acceptance:** `.venv/bin/python -m pytest ml/tests/test_parity.py -q` passes, including the new
`test_swift_corrections_match_python` (remove its `xfail` mark as part of this).

## Part 2: capture and clip writing (on device only)
- New Settings toggle **"Save replays of reps that need work"** (default off). The first time a
  session starts with it off, ask once: "Save short replays of reps that need work? They stay on this
  iPhone and are never uploaded." Respect the answer.
- While a session runs with replays on, keep a ring buffer of the last ~4 s of frames, downscaled to
  at most 480 px tall at ~15 fps (CVPixelBuffer pool or JPEG data; keep memory under ~20 MB), each
  frame paired with the joints pushed to `FormEngine` for it and their timestamp.
- When `FormEngine` returns a rep that has at least one cue whose metric has a correction rule
  (look the metric up from the cue text via the profile's `cue_low`/`cue_high`, as the hologram
  catalog lookup does), write a clip off the camera queue with `AVAssetWriter` (H.264, ~15 fps,
  <= 480 px tall) covering `rep.tStart - 0.4 s` to `rep.tEnd + 0.4 s`. Max 1 clip per rep and 20 per
  session; skip if the buffer no longer covers the rep.
- Drawing (Core Graphics or Core Image onto each frame): the real skeleton in bright white with
  joint dots; around the key moment (the correction event time, ±0.4 s, fading in and out) a
  translucent cyan ghost of the corrected pose with a soft glow and the moved joints highlighted;
  arrows from each moved joint's real position to its corrected position; a caption bar with the
  cue text and "Your swing (white) vs the fix (cyan)"; end with a 1.5 s freeze-frame at the key
  moment. The corrected pose comes from `correctedPose` with the event's pose and the reference
  event's pose (`start`/`end` = first/last frame of the rep). Coordinates: engine points are
  (x * aspect, y) with origin top-left; convert back to pixels.
- Front camera: the frames you store are unmirrored (Vision input); show them mirrored in the player
  if that is what the live preview does, mirroring the drawing with them.
- Store clips in Application Support under the local session folder; delete them when the session is
  deleted or the account is deleted/logged out. Never upload them.

## Part 3: show them
- Session summary and session detail: for each rep with a clip, a row "Rep 3 · 72 · Elbow at nose
  level" with a thumbnail; tapping plays it full screen (AVPlayer, loop, scrub), with a share button.
- History: a small film icon on sessions that have replays.
- Update `docs`-free README notes in `ios/FormCoach/README.md`.

## Verify
Simulator replay mode has no camera frames: generate frames for the replay source (draw the
fixture's stick figure on a dark background at 480 px) so the full path, capture -> clip -> playback,
is exercised in UI tests. Add a test that runs a replay session with replays on, ends it, opens a
replay and screenshots it. Look at the screenshots. Report files changed and test results.
