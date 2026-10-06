# Brief for Antigravity, batch 7: plain-language cues and short spoken labels

Read `docs/QUIET_COACHING.md` (the "Words" section). Players hear these from far away and read them
mid-practice; coaching jargon ("there is a hitch between your dip and your release") is not
understood. You own ONLY `docs/cue_rewrites.json` for this batch — do not edit `shared/`, `ml/`,
`ios/`, `web/`, or anything else. Claude reviews and applies it.

## Task
For every metric spec in `shared/sport_profiles.json` (each sport's `metrics`, and each tennis view's
`views.<view>.metrics`) that has `cue_low` and/or `cue_high`, write an entry:

```json
{"sport": "basketball", "view": null, "metric": "shot_rhythm",
 "cue_low_old": "...", "cue_low": "...", "short_low": "...",
 "cue_high_old": "...", "cue_high": "...", "short_high": "..."}
```
(omit the low or high half when the spec has no such cue; `view` is null for the sport's base list).

Rules:
- `cue_*`: one or two short sentences, plain words a 12-year-old would get, says what to DO, keeps
  the same meaning and direction as the old text (low vs high must not flip). No jargon; if a term is
  unavoidable, explain it in the same sentence. Keep any camera-view-specific meaning.
- `short_*`: 2–4 words, an instruction you could shout across a court ("Elbow up at the finish",
  "Hit it out front", "Smooth, one motion"). Must be distinct within a sport+view.
- Keep text that is already plain (just copy it to the new field).
- Check against the metric's `label` and the cue catalog (`shared/cue_catalog.json`: meaning,
  wrong_motion, correct_motion) so the meaning is right.

Then validate: a short Python script that loads both files and asserts every cue in the profile has
exactly one entry, every `*_old` matches the current text exactly, and every short label has 2–4 words.
Put the script's output at the end of your reply. Do not commit.
