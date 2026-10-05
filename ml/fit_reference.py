"""Training batch: fit each metric's professional reference range from the training split and
write it into shared/sport_profiles.json. Run validate.py afterwards on the held-out split.

Splits (the verification data is never used here):
  golf        GolfDB face-on real-time pro swings, dataset splits 1-3   (verify: split 4)
  basketball  SPL free throws, athletes P0001-P0003                     (verify: P0004-P0005)
  tennis      THETIS expert players p32-p49                              (verify: p50-p55 + all beginners)
  pickleball  no public pose/stroke dataset exists; its ranges stay as coaching priors
"""
from __future__ import annotations

import json
import statistics as st
import sys

import datasets
from formcoach.engine import PROFILES_PATH, analyze_recording, load_profiles

TRAIN = {
    "golf": lambda t: t["split"] in (1, 2, 3),
    "basketball": lambda t: t["participant"] in ("P0001", "P0002", "P0003"),
    "tennis": lambda t: t["expert"] and t["subject"] <= 49,
}
LOADERS = {"golf": datasets.golfdb, "basketball": datasets.spl, "tennis": datasets.thetis}

# Camera views fitted on Penn Action's human-labelled tennis clips (one clip in four held out).
PENN_TENNIS = {"tennis_forehand": "forehand", "tennis_serve": "serve"}


def penn_train(name: str) -> bool:
    return int(name.split("_")[-1]) % 4 != 0


def penn_view_reps(view: str, profiles: dict, keep) -> list:
    reps = []
    for name, rec, truth in datasets.penn_action(set(PENN_TENNIS)):
        if truth["view"] != view or not keep(name):
            continue
        stroke = PENN_TENNIS[truth["action"]]
        eng = analyze_recording(dict(rec, sport="tennis", view=view, focus="serve" if stroke == "serve" else None), profiles)
        reps.extend(r for r in eng.reps if r.type == stroke)
    return reps


SOURCES = {"golf": "GolfDB pros", "basketball": "SPL free throws", "tennis": "THETIS experts"}


def true_reps(sport: str, eng, truth: dict) -> list:
    """Only reps that match the labelled motion are used (e.g. not a practice swing)."""
    if sport == "golf":
        return [r for r in eng.reps if abs(r.events["impact"] - truth["events"]["impact"]) < 0.25][:1]
    if sport == "tennis":
        return [r for r in eng.reps if r.type == truth["stroke"]]
    return eng.reps[:1]


def robust(values: list) -> tuple[float, float]:
    med = st.median(values)
    mad = st.median(abs(v - med) for v in values)
    return med, 1.4826 * mad


def collect(sport: str, profiles: dict, keep) -> list:
    reps = []
    for _, rec, truth in LOADERS[sport]():
        if keep(truth):
            reps.extend(true_reps(sport, analyze_recording(rec, profiles), truth))
    return reps


def fit(sport: str, profiles: dict, view: str | None = None) -> None:
    if view:
        reps = penn_view_reps(view, profiles, penn_train)
        specs = profiles["sports"][sport]["views"][view]["metrics"]
        source = f"Penn Action tennis, {view} view"
    else:
        reps = collect(sport, profiles, TRAIN[sport])
        specs = profiles["sports"][sport]["metrics"]
        source = SOURCES[sport]
    print(f"\n{sport}{' / ' + view if view else ''}: {len(reps)} training reps")
    for spec in specs:
        targets = [(spec, None)] + [(o, k) for k, o in (spec.get("by_type") or {}).items() if o is not None]
        skip = set((spec.get("by_type") or {}).keys())
        for tgt, rep_type in targets:
            vals = [r.metrics[spec["id"]] for r in reps
                    if r.metrics.get(spec["id"]) is not None
                    and (r.type == rep_type if rep_type else r.type not in skip)]
            if len(vals) < 20:
                print(f"  {spec['id']:22s} {rep_type or '':9s} only {len(vals)} samples, keeping prior")
                continue
            mean, std = robust(vals)
            std = max(std, 0.05 * abs(mean), 0.02)
            tgt.update(mean=round(mean, 3), std=round(std, 3), tol=round(0.5 * std, 3))
            if rep_type is None:
                spec["source"] = f"{source} (n={len(vals)})"
            print(f"  {spec['id']:22s} {rep_type or '':9s} mean {mean:8.3f}  std {std:7.3f}  n={len(vals)}")


if __name__ == "__main__":
    profiles = load_profiles()
    for target in sys.argv[1:] or list(TRAIN) + ["tennis/back", "tennis/side"]:
        sport, _, view = target.partition("/")
        fit(sport, profiles, view or None)
    PROFILES_PATH.write_text(json.dumps(profiles, indent=2) + "\n")
    print(f"\nwrote {PROFILES_PATH}")
