"""Verification batch: measure the engine on data that fit_reference.py never saw.

Writes ml/reports/validation.md. Counting is judged against each dataset's ground truth (one
labelled motion per clip); scoring is judged by how held-out skilled performers score and, for
tennis, whether experts out-score beginners.
"""
from __future__ import annotations

import statistics as st
import sys
from pathlib import Path

import datasets
from fit_reference import TRAIN, true_reps
from formcoach.engine import analyze_recording, load_profiles

OUT = Path(__file__).parent / "reports" / "validation.md"


def pct(a: int, b: int) -> str:
    return f"{a}/{b} ({100 * a / b:.0f}%)" if b else "0/0"


def quant(vals: list, q: float) -> float:
    v = sorted(vals)
    return v[min(len(v) - 1, int(q * len(v)))]


def auc(pos: list, neg: list) -> float:
    """Probability that a random positive out-scores a random negative."""
    wins = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return wins / (len(pos) * len(neg))


def score_line(label: str, scores: list) -> str:
    if not scores:
        return f"| {label} | 0 | | | |"
    return f"| {label} | {len(scores)} | {st.median(scores):.0f} | {quant(scores, 0.1):.0f} | {quant(scores, 0.9):.0f} |"


SCORE_HEAD = "| group | reps | median score | p10 | p90 |\n|---|---|---|---|---|"


def golf(P: dict) -> list:
    rows = {"verify": [], "train": []}
    for _, rec, truth in datasets.golfdb():
        eng = analyze_recording(rec, P)
        rows["train" if TRAIN["golf"](truth) else "verify"].append((truth, eng, true_reps("golf", eng, truth)))
    out = ["## Golf (GolfDB, face-on real-time pro swings)", ""]
    out += ["| split | clips | labelled swing counted | other swings counted |", "|---|---|---|---|"]
    for name in ("verify", "train"):
        r = rows[name]
        found = sum(1 for _, _, g in r if g)
        extra = sum(len(e.reps) - len(g) for _, e, g in r)
        out.append(f"| {name} | {len(r)} | {pct(found, len(r))} | {extra} |")
    out += ["", "\"Other swings\" are swings counted away from the labelled one. Clips include the",
            "pre-shot routine, where pros make real practice swings, so these are not all errors.", "",
            "Event timing against the human labels (verification split):", "",
            "| event | median error | 90% within |", "|---|---|---|"]
    ver = [(t, g[0]) for t, _, g in rows["verify"] if g]
    for ev in ("address", "top", "impact", "finish"):
        err = [abs(r.events[ev] - t["events"][ev]) * 1000 for t, r in ver]
        out.append(f"| {ev} | {st.median(err):.0f} ms | {quant(err, 0.9):.0f} ms |")
    out += ["", SCORE_HEAD, score_line("held-out pros", [r.score for _, r in ver]),
            score_line("training pros", [g[0].score for _, _, g in rows["train"] if g]), ""]
    return out


def basketball(P: dict) -> list:
    rows = {"verify": [], "train": []}
    for _, rec, truth in datasets.spl():
        eng = analyze_recording(rec, P)
        rows["train" if TRAIN["basketball"](truth) else "verify"].append((truth, eng))
    out = ["## Basketball (SPL free throws, 3D motion capture projected to a face-on phone view)", "",
           "| split | trials | counted exactly once | missed | double-counted |", "|---|---|---|---|---|"]
    for name in ("verify", "train"):
        r = rows[name]
        n = [len(e.reps) for _, e in r]
        out.append(f"| {name} | {len(r)} | {pct(n.count(1), len(r))} | {n.count(0)} | {sum(1 for x in n if x > 1)} |")
    rej = {}
    for _, e in rows["verify"] + rows["train"]:
        for k, v in e.rejected.items():
            rej[k] = rej.get(k, 0) + v
    out += ["", f"Motions correctly ignored across all trials (dribbles, catching the ball, lowering the arms): "
                f"{sum(rej.values())} ({', '.join(f'{k} {v}' for k, v in sorted(rej.items()))}).", "", SCORE_HEAD]
    ver = [(t, e.reps[0]) for t, e in rows["verify"] if e.reps]
    out += [score_line("held-out athletes", [r.score for _, r in ver]),
            score_line("training athletes", [e.reps[0].score for _, e in rows["train"] if e.reps]), ""]
    made = [r.score for t, r in ver if t["result"] == "made"]
    miss = [r.score for t, r in ver if t["result"] != "made"]
    if made and miss:
        out += [f"Form score vs shot result on held-out athletes: AUC {auc(made, miss):.2f} "
                f"(0.50 = no relationship). The score measures technique, not whether the ball goes in.", ""]
    return out


def tennis(P: dict) -> list:
    groups = {"held-out experts": [], "beginners": [], "training experts": []}
    for _, rec, truth in datasets.thetis():
        eng = analyze_recording(rec, P)
        key = "training experts" if TRAIN["tennis"](truth) else "held-out experts" if truth["expert"] else "beginners"
        groups[key].append((truth, eng))
    out = ["## Tennis (THETIS, shadow swings facing a Kinect at 17 fps)", "",
           "| group | clips | counted exactly once | missed | over-counted | stroke type correct |",
           "|---|---|---|---|---|---|"]
    for name, r in groups.items():
        n = [len(e.reps) for _, e in r]
        ok = sum(1 for t, e in r if len(e.reps) == 1 and e.reps[0].type == t["stroke"])
        out.append(f"| {name} | {len(r)} | {pct(n.count(1), len(r))} | {n.count(0)} | "
                   f"{sum(1 for x in n if x > 1)} | {pct(ok, n.count(1))} |")
    out += ["", SCORE_HEAD]
    scores = {}
    for name, r in groups.items():
        scores[name] = [g.score for t, e in r for g in true_reps("tennis", e, t)]
        out.append(score_line(name, scores[name]))
    if scores["held-out experts"] and scores["beginners"]:
        out += ["", f"Held-out experts vs beginners: AUC {auc(scores['held-out experts'], scores['beginners']):.2f} "
                    f"(0.50 = the score cannot tell them apart, 1.00 = perfect separation).", ""]
    return out


EVERYDAY = {"squat", "jumping_jacks", "pushup", "pullup", "situp", "jump_rope", "bench_press", "strum_guitar",
            "clean_and_jerk"}
SPORT_ACTIONS = {"golf": {"golf_swing"}, "tennis": {"tennis_forehand", "tennis_serve"},
                 "pickleball": {"tennis_forehand"}, "basketball": set()}


def face_on(rec: dict) -> bool:
    """Shoulders appear wide relative to the torso when the person faces the camera."""
    import math
    a = rec["aspect"]
    for fr in rec["frames"]:
        ls, rs, lh, rh = (fr["j"][k] for k in (1, 2, 7, 8))
        if min(ls[2], rs[2], lh[2], rh[2]) < 0.3:
            continue
        sw = math.hypot((ls[0] - rs[0]) * a, ls[1] - rs[1])
        tor = math.hypot(((ls[0] + rs[0]) - (lh[0] + rh[0])) * a / 2, ((ls[1] + rs[1]) - (lh[1] + rh[1])) / 2)
        return sw / max(tor, 1e-6) >= 0.55
    return False


def penn(P: dict) -> list:
    clips = list(datasets.penn_action())
    out = ["## Real-world check (Penn Action, human-labelled joints, never used for fitting)", "",
           "YouTube clips of people of all levels. Each sport's engine is run on every clip: its own",
           "action should be counted (face-on clips only, since the app films face-on); everything",
           "else should not. \"Everyday movements\" are squats, jumping jacks, push-ups, pull-ups,",
           "sit-ups, jump rope, bench press, guitar and barbell lifts.", "",
           "| engine | own action counted | everyday movements counted | other sports' swings counted |",
           "|---|---|---|---|"]
    for sport in ("golf", "basketball", "tennis", "pickleball"):
        own = [0, 0]
        every = [0, 0]
        other = [0, 0]
        for _, rec, t in clips:
            eng = analyze_recording(dict(rec, sport=sport), P)
            hit = 1 if eng.reps else 0
            if t["action"] in SPORT_ACTIONS[sport]:
                if face_on(rec):
                    own[0] += 1
                    own[1] += hit
            elif t["action"] in EVERYDAY:
                every[0] += 1
                every[1] += hit
            else:
                other[0] += 1
                other[1] += hit
        label = {"pickleball": "tennis forehands (proxy)", "basketball": "none in dataset"}.get(sport, "yes")
        own_s = pct(own[1], own[0]) if own[0] else "n/a"
        out.append(f"| {sport} ({label}) | {own_s} | {pct(every[1], every[0])} | {pct(other[1], other[0])} |")
    out += ["", "Penn Action has no frame rate on record; clips are assumed to be 30 fps.", ""]
    return out


if __name__ == "__main__":
    P = load_profiles()
    sections = {"golf": golf, "basketball": basketball, "tennis": tennis, "penn": penn}
    lines = ["# FormCoach validation report", "",
             "Generated by `ml/validate.py`. Reference ranges were fitted on the training split only",
             "(`ml/fit_reference.py`); the verification rows below use data the fit never saw.", ""]
    for name in sys.argv[1:] or list(sections):
        lines += sections[name](P)
    lines += ["## Pickleball", "",
              "No public pickleball stroke or pose dataset exists, so pickleball has no verification batch.",
              "It uses the tennis analyser with coaching-prior ranges until opted-in app recordings provide data.", ""]
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text("\n".join(lines))
    print("\n".join(lines))
