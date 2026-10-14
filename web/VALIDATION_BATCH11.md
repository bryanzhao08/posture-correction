# Batch 11 — on-device tennis stroke estimates

Validated 2026-10-14. The TypeScript and Swift ports use the unchanged `shared/stroke_model.json` (version 1.0.0) and the feature/inference definition in `ml/strokes.py`. The web bundles that JSON; Xcode copies the same shared file into the app resource bundle. The built iOS resource was byte-compared to the shared source.

The existing engines still determine rep boundaries, rejection, metrics and scores. After a counted tennis rep, the app computes its 114 features from the engine's smoothed samples and runs coarse-family and groundstroke-spin inference locally. No fine/experimental serve-subtype prediction appears in either UI. Non-tennis flows do not acquire stroke tags or counts.

Display policy:

- Family labels: Forehand, One-handed backhand, Two-handed backhand, Serve at probability ≥0.6.
- Volley/Smash only at probability ≥0.75.
- Slice or topspin/flat only for a displayed groundstroke family with spin probability ≥0.6.
- Otherwise “Stroke unclear · estimate”; these reps count as uncertain in the session totals.
- Last-rep cards, including tennis reps without a correction cue, and summary rep rows show the estimate. Session totals group both backhand variants as backhands. Every tag/count heading explicitly says estimate.

Inference makes no API calls. Browser sessions/exports retain their estimates locally. iPhone session files retain estimates; `SessionIn.forUpload` strips them from the ordinary session upload without mutating the stored payload. On this iPhone, synced detail views use the locally stored rep estimates when available. Another device does not receive them. Old reps without the optional field still decode.

## Verification

| Check | Result |
|---|---|
| `.venv/bin/python -m pytest ml/tests -q` from repo root | **75 passed**, two existing NumPy deprecation warnings |
| New `test_web_strokes_match_python` / `test_swift_strokes_match_python` | PASS |
| `--strokes <file>` in both check executables | **37/37 descriptors and all task probability maps match**, absolute tolerance 1e-6, same argmax labels |
| Fixtures | 31 cases: held-out `stroke_examples.json` descriptors; tennis CASES replayed by each native engine at 30/60 fps, front/side/back, right/left handedness; missing events/off-wrist/optional joints; all-missing inference |
| `npm run build` | PASS |
| `node web/scripts/check-strokes-ui.ts` | PASS — confidence boundaries, weak classes, spin applicability, hidden serve type, grouped counts |
| `node web/scripts/check-storage.ts` | PASS — existing batch-10 storage regressions |
| Chrome `channel: chrome`, 390×844 and 1280×800 | PASS — tennis sample/live tag/summary rows/counts/fix opening, plus basketball absence of tags/counts; no page errors or cross-origin classifier requests |
| iOS Debug build-for-testing | PASS |
| iOS Release simulator build | PASS |
| iPhone 16 Pro / iOS 18.5 UI tests | Tennis live/summary estimate flow and existing basketball correction flow pass; confidence-policy test passes — three selected tests, zero failures |
| Additional iOS codec/privacy test run | Confidence-policy + local-save/upload exclusion tests pass — two tests, zero failures |
| `git diff --check` | PASS |

Swift scratch target `/tmp/formcoach-codex/batch5/formcore-build` exists, preserving the existing `ios/FormCore/.build` symlink. No Python reference code, shared model/profile files, web config or beta gate were modified.

Browser UI tests are reproducible with Playwright installed, a built preview, and `BETA_PASSWORD` supplied:

```sh
# Start in web/: npx vite preview --host 127.0.0.1 --port 18100 --strictPort
# From repo root; PLAYWRIGHT_MODULE may point to an installed Playwright module.
BASE_URL=http://127.0.0.1:18100/posture-correction/ \
STROKE_ARTIFACT_DIR=/tmp/formcoach-codex/batch11/web \
node web/scripts/validate-strokes-ui.cjs

node web/scripts/check.ts --strokes /tmp/formcoach-codex/batch11/strokes-parity.json
/tmp/formcoach-codex/batch5/formcore-build/release/formcore-check --strokes /tmp/formcoach-codex/batch11/strokes-parity.json
```

## Screenshots and logs

Reviewed browser live/summary screenshots at both sizes and iPhone live/summary/scrolled rep screenshots. Tags wrap within cards and rows; counts wrap normally on narrow screens. Scratch paths are ephemeral.

- Web live: `/tmp/formcoach-codex/batch11/web/tennis-live-390.png`, `tennis-live-1280.png` in the same directory.
- Web summary: `/tmp/formcoach-codex/batch11/web/tennis-summary-390.png`, `tennis-summary-1280.png` in the same directory.
- Web assertion/request evidence: `/tmp/formcoach-codex/batch11/web/results.json`.
- iPhone live: `/tmp/formcoach-codex/batch11/ios-screenshots/6EA2B287-8AAE-4B37-B981-9550D803106C.png`.
- iPhone summary: `/tmp/formcoach-codex/batch11/ios-screenshots/6FE33DBD-C5B9-40D2-84EB-B97731F2A814.png`.
- iPhone rep rows: `/tmp/formcoach-codex/batch11/ios-screenshots/1097661F-6946-4593-932F-42804385D71D.png`.
- Screenshot attachment map: `/tmp/formcoach-codex/batch11/ios-screenshots/manifest.json`.
- UI results: `/tmp/formcoach-codex/batch11/ui-tests.xcresult`, `ui-tests.log` in the same directory.
- Privacy results: `/tmp/formcoach-codex/batch11/privacy-tests.xcresult`, `privacy-tests.log` in the same directory.
- Build logs: `/tmp/formcoach-codex/batch11/build-final.log`, `build-privacy.log`, `release-build.log` in the same directory.
- Exact parity fixture: `/tmp/formcoach-codex/batch11/strokes-parity.json`.

## Model limits observed

Both apps produce identical estimates on the synthetic tennis demo: one forehand, one uncertain stroke and one smash. The final motion was generated as a serve; the model's smash probability exceeds the required 0.75 threshold. This is a model misclassification, not a port discrepancy, and the UI keeps its estimate label. The Python report documents serve/smash confusion and the model's front-view research-dataset limits. Confidence is a model probability, not a guarantee of correctness. Phone-camera classification accuracy and real iPhone capture were not re-measured in this batch; simulator tests use the existing pose replay. The experimental serve subtype remains completely hidden.
