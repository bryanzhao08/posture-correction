# Brief for Codex, batch 8: quiet coaching on iOS (higher priority than batch 7 parts 2–3)

Read `docs/QUIET_COACHING.md` first; it is the spec. Same house rules: build output in
/tmp/formcoach-codex/batch8/, test backend on 18004, you own `ios/**` only (never `web/`, `ml/`,
`shared/`, `backend/`). Commit when done, do not push.

## Order of work
1. **Batch 7 part 1 first** (`docs/briefs/codex-batch-7-replays.md`): port `corrections.py` to
   `Corrections.swift` + `formcore-check --corrections`, and remove the xfail in
   `ml/tests/test_parity.py::test_swift_corrections_match_python` (that one-line edit in ml/tests is
   allowed). The last-rep card below needs it.
2. **This batch** (below).
3. Then batch 7 parts 2–3 (replay clips), reusing the freeze-frame drawing from this batch.

## Changes
- `SessionView` HUD: remove the cue text and the "Want to see what this means?" prompt from the live
  view. Scoreboard modes become compact / mini / hidden (`@AppStorage("scoreboardMode")`, migrate the
  old "full" value to "compact"). Compact = REPS and SCORE side by side, equal size, ~40 pt numbers,
  small labels; mini = pill "7 · 92"; hidden = small restore button (44 pt hit area, VoiceOver labels).
- Spoken cue: AVSpeechSynthesizer says the short label (`short_low`/`short_high` of the matching
  metric in the effective profile; fall back to the full cue), one per rep, at most every 6 s. Setting
  "Speak cues" (default on) in Settings and the pre-session screen; "Say 'nice' on good reps" (default off).
- Last-rep card: keep the most recent camera frame near each rep's correction event. Keep a small ring
  buffer (~2 s at ~10 fps, frames downscaled to <= 360 px tall, CGImage or JPEG data) paired with the
  joints pushed to the engine. When a rep with a correctable cue arrives, pick the frame nearest the
  event time, compute `correctedPose` (target = the metric's reference mean for the rep type via
  `targetFor`), and render the card per the spec (white skeleton, cyan ghost on moved limbs, arrows,
  short label, score). Card sits bottom-leading above the controls, stays until the next card.
  Tap opens a sheet with the big freeze-frame, the full cue, the catalog explanation and "Show me".
  Frames are not saved or uploaded for this (memory only); respect the front-camera mirroring the
  preview uses.
- Summary: rep rows show the short label; tapping a rep with a stored card shows its freeze-frame.

## Verify
Simulator replay mode: draw the fixture skeleton on a dark background as the "camera frame". Update
the UI tests (no cue text in the live HUD; cycle compact -> mini -> hidden -> compact; a card appears
after a rep with a fault; open it). Look at the screenshots. Run
`.venv/bin/python -m pytest ml/tests/test_parity.py -q` (all must pass). Report files changed and results.

Note: Antigravity is adding `short_low`/`short_high` to `shared/sport_profiles.json` and rewording
cues; until that lands, the fallback (full cue) is expected. Do not hard-code cue strings.
