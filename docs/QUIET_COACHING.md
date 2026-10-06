# Quiet coaching: feedback for a player who is far from the phone

Feedback from on-court testing (tennis coach and player):

1. The player is usually far from the camera, deep in the court, and not looking at the phone.
   Text that pops up the moment a rep ends is never read, and is distracting when it is.
2. Coaching words are hard to act on mid-practice (for example "there is a hitch between your dip
   and your release"). Seeing it on your own body is much clearer.
3. The REPS / SCORE numbers are too big, and should be easy to shrink further.

This is the design both apps (iOS `ios/FormCoach`, browser `web/`) follow.

## During play: quiet by default
- **Nothing pops up when a rep ends.** No cue text and no "What does this mean?" prompt over the camera.
  The state pill, rep count and last score update silently.
- **Scoreboard is compact by default**: one small panel, REPS and SCORE side by side at equal size,
  about a third of the old height (numbers ~40 pt / clamp(1.8rem, 8vw, 2.6rem) on web). Three modes,
  cycled by one button and remembered: **compact** -> **mini** (a pill "7 · 92") -> **hidden**
  (only a small restore button). The old full-size panel is gone.
- **Spoken cue (on by default, toggle in settings / pre-session):** after a rep that needs work, say the
  metric's **short label** (2–4 plain words, e.g. "Elbow higher at the finish"), not the full sentence.
  At most one spoken cue per rep, and not more often than once every 6 s. Good reps can optionally get
  a short "Nice" (off by default).
- Haptics/sounds unchanged.

## Between reps: the "last rep" card (visual, glanceable)
- After a rep with a correctable fault, a **small card** appears in a corner (about 28% of the screen
  width) and **stays until the next rep** replaces it, so whenever the player walks back or glances
  over it is still there. It never covers the centre of the frame.
- Content: a freeze-frame of the player at the rep's key moment (the correction event from
  `ml/formcoach/corrections.py` `EVENTS`, e.g. contact or follow-through), with
  - their skeleton in **white**,
  - the **corrected pose** (`corrected_pose(...)` with the metric's reference mean as target) as a
    translucent **cyan ghost**, only the moved limbs drawn strongly,
  - an arrow from each moved joint to where it should be,
  - the short label underneath in large text, plus the rep score.
- Tap the card to open it big: the freeze-frame large, the full cue sentence, the plain explanation
  from the cue catalog, and (iOS) the existing "Show me" hologram; (iOS, when replays exist) play the
  replay clip.
- Cues with no correction rule (timing, rotation, head stability) show the short label and score on the
  card with the plain skeleton and no ghost; tapping opens the explanation / hologram.
- When the camera frame is not available (simulator replay, web sample mode) draw the freeze-frame
  as the skeleton on a dark background.

## Words
- Every metric spec in `shared/sport_profiles.json` gets `short_low` / `short_high` next to
  `cue_low` / `cue_high`: 2–4 plain words, an instruction, no jargon. Both apps look the short label up
  from the cue text the engine returns (match `cue_low`/`cue_high` of the effective profile's metrics);
  fall back to the full cue if a short label is missing.
- Full cue sentences are rewritten in plain language (no "hitch", "lag", "unit turn" without saying what
  it means). Only the text changes, never the metric logic.

## After the session
Unchanged: the summary lists cues and per-metric scores. Each rep row shows its short label; tapping
shows the same freeze-frame view as the card.
