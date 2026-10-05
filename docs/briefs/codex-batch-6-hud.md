# Brief for Codex, batch 6 (after batch 5): live session HUD layout

User request: "make the score equal size as the reps so reps / score throughout the middle, and make
it possible to close the numbers or minimize them".

File: `ios/FormCoach/Views/SessionView.swift` (the counting HUD, around the `repFontSize` /
`scoreFontSize` block). Today the rep count is a 112 pt number in the middle and the last score is a
small 48 pt badge top-right.

## Change
1. **Reps and score side by side, same size, across the middle.** One centred row, two equal columns:
   left `REPS` with the rep count, right `SCORE` with the last rep's score (`—` before the first rep),
   both using the same font (`repFontSize`, heavy rounded, monospaced digits, `minimumScaleFactor`
   so 3-digit values fit), with a thin divider between them. Keep the coaching cue and its
   "Want to see what this means?" prompt underneath the row, as now. Remove the old top-right score
   badge (the state pill stays at the top).
2. **Minimise / close the numbers.** A small button on the numbers panel (e.g. `chevron.down` /
   `xmark`, 44 pt hit area, VoiceOver labels "Minimize scoreboard" / "Show scoreboard") cycles:
   - **full**: the side-by-side panel above;
   - **minimized**: a compact pill pinned near the top (e.g. "7 reps · 92"), so the skeleton and
     camera are visible; tapping it restores full;
   - **hidden**: only a small floating button to bring it back.
   Persist the choice with `@AppStorage("scoreboardMode")`. Counting, haptics, sounds and spoken cues
   continue in every mode; only the display changes. Animate transitions (respect Reduce Motion).
3. The coaching cue stays visible in **full**; in **minimized**/**hidden** show the cue as a single line
   under the pill only for a few seconds after each rep (or not at all in hidden).

## Verify
Build, run the UI tests (update `FormCoachFlowTests` for the new layout: assert both "REPS" and
"SCORE" are present, then minimize and restore once, with screenshots), output under
`/tmp/formcoach-codex/batch6/`, look at the screenshots, commit (do not push), and report.

## Addendum (user request): a Start session button instead of starting on tap
Today tapping a sport card on Home immediately opens the live session, so an accidental tap starts a
session the user then has to end. Change the flow:
- Tapping a sport card opens a **pre-session screen** (not the camera yet): sport name, the camera
  placement text for the chosen view with its `Show me` setup demo, and for tennis the batch 5
  training-type and view picker (move it here if it currently appears after the session opens).
- A large **Start session** button at the bottom opens the live session (camera, setup check,
  countdown) exactly as now. A **Back** / close control returns to Home without creating anything.
- Nothing is recorded, saved or uploaded until Start session is pressed; backing out leaves no
  session in history and no pending upload.
- Update the UI tests: tap a card, assert the session has not started (no "End session" button),
  tap Back, tap the card again, then Start session and continue the existing flow.
