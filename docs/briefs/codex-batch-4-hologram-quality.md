# Brief for Codex, batch 4: make the hologram demos look right

Your batch 3 works and is committed (55e35ca): ask-first prompts, 40 demos, marker tracking, 5 UI
tests passing. Claude reviewed the screenshots. The mechanics are good; the **movements and the
look are not yet convincing**, and a coach would notice. This batch is quality only.

## House rules (from batch 3)
- **All build/test output goes under `/tmp/formcoach-codex/`** (DerivedData, xcresult, logs,
  screenshots, generated projects). Nothing under `ios/FormCoach/` or `ios/FormCoachUITests/`:
  the app and test targets include every file in those folders. Batch 3 left 514 MB of artifacts
  there; Claude moved them out and added ignore rules.
- Test backend: `FORMCOACH_DATA_DIR=/tmp/formcoach-codex/backend ../.venv/bin/uvicorn app.main:app
  --port 18004` from `backend/` (the UI test already points at 18004). Never use port 8000: that is
  the user's real backend.
- You own `ios/FormCoach/**`, `ios/FormCoachUITests/**`, `ios/project.yml`. Do not edit
  `ios/FormCore`, `shared/`, `ml/`, `backend/`.

## Problems seen in the screenshots
1. **Golf shoulder-turn "correct" pose is wrong.** The figure holds the club vertically overhead
   with both arms straight up. A real top of backswing (right-handed golfer): lead (left) arm
   straight across the chest, hands about shoulder height behind the trail (right) shoulder, club
   shaft roughly parallel to the ground pointing at the target, trail elbow bent ~90 degrees and
   pointing down, shoulders turned ~90 degrees, hips ~45 degrees, spine tilted forward from address
   (~35-40 degrees). Address: bent forward from the hips, knees flexed, arms hanging, club to the
   ball. Use these as the golf base keyframes.
2. **"Wrong" golf pose has the lead arm sticking straight out sideways** while the other hand holds
   the club. Both hands must stay on the grip for the whole golf swing (one hand on top of the
   other); for tennis/pickleball one hand on the implement except two-handed backhands; basketball
   both hands on the ball until the set point, then the guide hand comes off at release.
3. **Rotation is invisible** because the camera looks straight at the figure. For rotation cues
   (shoulder turn, hip sway, unit turn, head movement) start the orbit at a 3/4 angle or show a
   second small down-the-line view, and draw a faint arc or ghost showing the angle (e.g. a cyan
   arc from the address shoulder line to the top shoulder line labelled "90 degrees").
4. **It does not look holographic.** Solid flat colour. Wanted: semi-transparent emissive body
   (alpha ~0.6, additive blend, `writesToDepthBuffer = false` for the glow pass), a brighter rim
   (fresnel) on the edges via a shader modifier, a slow vertical scanline band, a soft bloom
   (SCNCamera `bloomIntensity`/`bloomThreshold`), faint flicker, and the grid floor with a glowing
   ring under the figure. Wrong = warm orange, Correct = cyan, Both = wrong as a faint orange ghost
   behind the cyan correct motion, playing in sync, so the difference is visible at a glance.
5. **Proportions.** Torso and head read as a toy. Use adult proportions (head ~1/7.5 of height,
   shoulders ~1.1x hip width, upper arm ~0.19, forearm ~0.15, thigh ~0.25, shin ~0.25 of height),
   slimmer capsules, small hands, and feet that stay planted (no sliding) except where the cue is
   about drift or a jump.
6. **Setup demo:** the phone/tripod is a thin line far to the side. Model a recognisable phone
   (rounded slab, glowing screen, camera dot) on a tripod at the stated height and distance, with
   a translucent view-frustum cone from the lens to the figure so "full body in frame" is obvious,
   and a distance label ("3-4 m"). Wrong version: tripod too close / too low, frustum cutting off
   head or feet (red tint on the cut-off parts).

## Every sport, every cue
Go through all 40 entries and make each "wrong" and "correct" clearly differ in the one thing the
cue is about, with everything else identical, using the `meaning` / `wrong_motion` /
`correct_motion` text in `shared/cue_catalog.json`. Basketball (one-handed shot with guide hand),
tennis (forehand, one-handed backhand, serve with toss), pickleball (ready position paddle up,
compact dink/drive, overhead) each need sport-correct base keyframes as careful as the golf ones
above. Implements: golf club ~1.1 m, tennis racket ~0.69 m, pickleball paddle ~0.4 m solid face,
basketball ~0.24 m diameter.

## Review tooling (required)
- Add a DEBUG-only **Demo gallery** in Settings that lists all 40 demos (grouped by sport) and
  opens each one, so the user can review them on the phone.
- Add a UI test (can be slow; mark it clearly) that opens every gallery entry and saves two
  screenshots per entry (Wrong at the key moment, Correct at the same moment) named
  `<key>-wrong.png` / `<key>-correct.png`, and export them to `/tmp/formcoach-codex/gallery/`.
  Look at them yourself and fix any where the difference is not obvious. Claude will review the
  same folder.

## Report
Files changed, test results, the gallery folder path, and any cue where you are unsure the
biomechanics are right.
