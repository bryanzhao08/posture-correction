"""Train and evaluate the tennis stroke classifier on THETIS; export shared/stroke_model.json.

    ../.venv/bin/python train_strokes.py            # uses the feature cache when present
    ../.venv/bin/python train_strokes.py --rebuild  # re-run the engine over every clip

Splits are by player: a fixed 20% of players (stratified beginner/expert) is held out entirely,
and model selection uses 5-fold grouped CV over the remaining players. The exported model is the
one fitted on the 80% development players, so the held-out numbers describe the shipped weights.
Writes ml/reports/strokes.md and the test fixture ml/tests/data/stroke_examples.json.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score
from sklearn.model_selection import GroupKFold
from sklearn.neighbors import KNeighborsClassifier

import datasets
import strokes

HERE = Path(__file__).resolve().parent
CACHE = HERE / "data" / "strokes_features.json"
REPORT = HERE / "reports" / "strokes.md"
EXAMPLES = HERE / "tests" / "data" / "stroke_examples.json"
SEED = 0
TASKS = {
    "coarse": strokes.COARSE_CLASSES,
    "fine": strokes.FINE_CLASSES,
    "groundstroke_spin": ["flat_topspin", "slice"],
    "serve_type": ["flat", "kick", "slice"],
}
APPLIES_TO = {"coarse": None, "fine": None, "groundstroke_spin": ["forehand", "backhand_one", "backhand_two"],
              "serve_type": ["serve"]}
LR_C = [0.01, 0.03, 0.1, 0.3, 1.0]
RELIABILITY = {"serve_type": ("experimental: close to chance (33%) in grouped CV; do not show to users as a "
                              "verdict. Flat/kick/slice differ mostly in racket-face and ball-toss details "
                              "a front-view 2D wrist track cannot see.")}


# ---- data ------------------------------------------------------------------------------------
def build_rows() -> list[dict]:
    rows = []
    t0 = time.time()
    for name, rec, truth in datasets.thetis(strokes.THETIS_FOLDERS):
        fine = truth["stroke"]
        eng, samples = strokes.analyze_with_samples(rec)
        row = {"name": name, "subject": truth["subject"], "expert": truth["expert"], "fine": fine,
               "n_reps": len(eng.reps), "engine_type": None, "features": None}
        if eng.reps:
            # one stroke per clip: when the engine counts more than one motion, the fastest is the stroke
            rep = max(eng.reps, key=lambda r: r.peak_speed)
            row["engine_type"] = rep.type
            row["features"] = strokes.rep_features(samples, rep, "r")
        rows.append(row)
        if len(rows) % 200 == 0:
            print(f"  {len(rows)} clips, {time.time() - t0:.0f}s", flush=True)
    return rows


def load_rows(rebuild: bool) -> list[dict]:
    if CACHE.exists() and not rebuild:
        rows = json.loads(CACHE.read_text())
        if rows and set(rows[0].get("features") or {}) in (set(), set(strokes.FEATURES)):
            return rows
    rows = build_rows()
    CACHE.write_text(json.dumps(rows))
    return rows


def held_out_players(rows) -> set[int]:
    rng = np.random.default_rng(SEED)
    out = set()
    for expert in (False, True):
        ps = sorted({r["subject"] for r in rows if r["expert"] == expert})
        out |= set(int(p) for p in rng.choice(ps, size=round(0.2 * len(ps)), replace=False))
    return out


def matrix(rows) -> np.ndarray:
    return np.array([[np.nan if r["features"][n] is None else r["features"][n] for n in strokes.FEATURES]
                     for r in rows], dtype=float)


def task_labels(rows, task):
    return [strokes.labels(r["fine"])[task] for r in rows]


class Norm:
    """Median imputation then standardisation, fitted on training rows only."""

    def fit(self, X):
        self.impute = np.nanmedian(X, axis=0)
        self.impute = np.where(np.isfinite(self.impute), self.impute, 0.0)
        Xi = np.where(np.isfinite(X), X, self.impute)
        self.mean = Xi.mean(axis=0)
        self.std = Xi.std(axis=0)
        self.std = np.where(self.std > 1e-9, self.std, 1.0)
        return self

    def __call__(self, X):
        return (np.where(np.isfinite(X), X, self.impute) - self.mean) / self.std


def make_model(kind, C=0.1):
    if kind == "logreg":
        return LogisticRegression(C=C, max_iter=5000)
    if kind == "gbt":
        return GradientBoostingClassifier(n_estimators=50, max_depth=3, learning_rate=0.1, subsample=0.8,
                                          random_state=SEED)
    if kind == "knn":
        return KNeighborsClassifier(n_neighbors=7, weights="distance")
    raise ValueError(kind)


def subset(rows, X, task):
    keep = [i for i, r in enumerate(rows) if strokes.labels(r["fine"])[task] is not None]
    return [rows[i] for i in keep], X[keep]


def fit_predict(kind, Xtr, ytr, Xte, C=0.1):
    norm = Norm().fit(Xtr)
    m = make_model(kind, C).fit(norm(Xtr), ytr)
    return m.predict(norm(Xte)), m, norm


def cv(kind, rows, X, task, C=0.1, folds=5):
    rows, X = subset(rows, X, task)
    y = np.array(task_labels(rows, task))
    g = np.array([r["subject"] for r in rows])
    pred = np.empty(len(y), dtype=object)
    accs, f1s = [], []
    for tr, te in GroupKFold(n_splits=folds).split(X, y, g):
        p, _, _ = fit_predict(kind, X[tr], y[tr], X[te], C)
        pred[te] = p
        accs.append(accuracy_score(y[te], p))
        f1s.append(f1_score(y[te], p, average="macro", labels=TASKS[task], zero_division=0))
    return {"acc": float(np.mean(accs)), "acc_sd": float(np.std(accs)), "f1": float(np.mean(f1s)),
            "f1_sd": float(np.std(f1s)), "pred": pred, "y": y, "rows": rows}


def score(y, p, task):
    return accuracy_score(y, p), f1_score(y, p, average="macro", labels=TASKS[task], zero_division=0)


# ---- export ------------------------------------------------------------------------------------
def export(models: dict, norm: Norm, dev_players, test_players, n_train: dict, headline: dict) -> dict:
    tasks = {}
    for task, m in models.items():
        classes = [str(c) for c in m.classes_]
        W, b = m.coef_, m.intercept_
        if len(classes) == 2:                       # sklearn stores a binary model as one row
            W = np.vstack([np.zeros_like(W[0]), W[0]])
            b = np.array([0.0, b[0]])
        order = [classes.index(c) for c in TASKS[task]]
        tasks[task] = {
            "type": "multinomial_logistic_regression",
            "classes": TASKS[task],
            "applies_to_coarse": APPLIES_TO[task],
            "weights": [[round(float(v), 6) for v in W[k]] for k in order],
            "bias": [round(float(b[k]), 6) for k in order],
            "C": float(m.C),
            "n_train": n_train[task],
            "eval": {"held_out_accuracy": round(headline[task][0], 4), "held_out_macro_f1": round(headline[task][1], 4),
                     "cv_accuracy": round(headline[task][3], 4)},
        }
        if task in RELIABILITY:
            tasks[task]["reliability"] = RELIABILITY[task]
    return {
        "name": "formcoach-tennis-strokes",
        "version": "1.0.0",
        "created": time.strftime("%Y-%m-%d"),
        "sport": "tennis",
        "input": ("Descriptor of one rep counted by the FormCoach engine, computed by ml/strokes.py "
                  "rep_features() from the engine's Samples; ports must compute the same features in "
                  "the same order. Missing (null/NaN) values are replaced by normalization.impute."),
        "inference": "z = (x_imputed - mean) / std; for each task p = softmax(weights @ z + bias)",
        "n_points": strokes.N_POINTS,
        "features": strokes.FEATURES,
        "normalization": {"impute": [round(float(v), 6) for v in norm.impute],
                          "mean": [round(float(v), 6) for v in norm.mean],
                          "std": [round(float(v), 6) for v in norm.std]},
        "tasks": tasks,
        "training_data": {
            "dataset": "THETIS (Three dimEnsional TennIs Shots)",
            "citation": ("S. Gourgari, G. Goudelis, K. Karpouzis, S. Kollias. THETIS: Three Dimensional Tennis "
                         "Shots, a human action dataset. CVPR Workshops (CVPRW), 2013, pp. 676-681."),
            "url": "https://github.com/THETIS-dataset/dataset",
            "licence_note": ("THETIS is distributed for research purposes. This model was trained on it for "
                             "research/prototyping; check the dataset's terms (and contact the authors) before "
                             "any commercial use, and retrain on licensed data for a product release."),
            "input_pipeline": ("RGB videos (Kinect, 640x480, mirrored; un-mirrored here) -> MediaPipe Pose "
                               "(ml/extract_pose.py) -> FormCoach engine (shared/sport_profiles.json tennis, "
                               "front view, right-handed)"),
            "players_train": sorted(int(p) for p in dev_players),
            "players_held_out": sorted(int(p) for p in test_players),
        },
    }


# ---- report helpers ----------------------------------------------------------------------------
def pct(x):
    return f"{100 * x:.1f}%"


def confusion_md(y, p, classes):
    cm = confusion_matrix(y, p, labels=classes)
    short = [c.replace("backhand", "bh").replace("forehand", "fh").replace("serve", "srv")
             .replace("_handed", "").replace("_stance", "") for c in classes]
    out = ["| true \\ predicted | " + " | ".join(short) + " | recall |",
           "|---|" + "---|" * (len(classes) + 1)]
    for i, c in enumerate(short):
        n = cm[i].sum()
        out.append(f"| **{c}** | " + " | ".join(str(v) if v else "." for v in cm[i])
                   + f" | {pct(cm[i, i] / n) if n else '-'} |")
    return out


def group_acc(rows, y, p):
    out = {}
    for name, flag in (("beginners", False), ("experts", True)):
        idx = [i for i, r in enumerate(rows) if r["expert"] == flag]
        out[name] = (accuracy_score(y[idx], p[idx]) if idx else float("nan"), len(idx))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rebuild", action="store_true")
    args = ap.parse_args()
    rows_all = load_rows(args.rebuild)
    rows = [r for r in rows_all if r["features"] is not None]
    test_players = held_out_players(rows_all)
    dev = [r for r in rows if r["subject"] not in test_players]
    test = [r for r in rows if r["subject"] in test_players]
    dev_players = sorted({r["subject"] for r in rows_all} - test_players)
    Xdev, Xtest = matrix(dev), matrix(test)
    print(f"{len(rows_all)} clips, {len(rows)} with a counted rep; dev {len(dev)} / held-out {len(test)} "
          f"({len(test_players)} players: {sorted(test_players)})")

    rep = []
    # Coverage
    rep += ["## Data and coverage", "",
            "Every THETIS RGB clip (12 classes x 55 players x ~3 takes; p1-p31 beginners, p32-p55 experts) was run "
            "through MediaPipe Pose and the unchanged FormCoach engine (tennis profile, front view, right-handed). "
            "Only clips in which the engine counted a rep give a training example; when it counted more than one, "
            "the fastest rep is taken as the stroke.", "",
            "| class | clips | engine counted >=1 rep | >1 rep | engine type (fh / bh / serve) |", "|---|---|---|---|---|"]
    for fine in strokes.FINE_CLASSES:
        rs = [r for r in rows_all if r["fine"] == fine]
        got = [r for r in rs if r["features"] is not None]
        ty = [sum(1 for r in got if r["engine_type"] == t) for t in ("forehand", "backhand", "serve")]
        rep.append(f"| {fine} | {len(rs)} | {len(got)} ({pct(len(got) / max(len(rs), 1))}) | "
                   f"{sum(1 for r in rs if r['n_reps'] > 1)} | {ty[0]} / {ty[1]} / {ty[2]} |")
    nb = sum(1 for r in rows_all if not r["expert"])
    rep += ["", f"Total: {len(rows_all)} clips, {len(rows)} examples ({pct(len(rows) / len(rows_all))}). "
            f"Beginner clips: {nb}, expert clips: {len(rows_all) - nb}.", "",
            f"Held-out players (20%, stratified, seed {SEED}): {sorted(test_players)} "
            f"-> {len(test)} examples; development players: {len(dev_players)} -> {len(dev)} examples.", ""]

    # Model comparison
    results = {}
    best_C = {}
    print("grouped CV ...")
    rep += ["## Model comparison (5-fold grouped CV over development players)", "",
            "Accuracy and macro-F1, mean +/- sd across folds; no player is in both the training and the test fold.", "",
            "| task | classes | logistic regression | gradient-boosted trees (50 stages, depth 3) | k-NN (k=7) |",
            "|---|---|---|---|---|"]
    for task in TASKS:
        cells = []
        lr_runs = {C: cv("logreg", dev, Xdev, task, C) for C in LR_C}
        best_C[task] = max(lr_runs, key=lambda C: (lr_runs[C]["f1"], -C))
        results[(task, "logreg")] = lr_runs[best_C[task]]
        results[(task, "gbt")] = cv("gbt", dev, Xdev, task)
        results[(task, "knn")] = cv("knn", dev, Xdev, task)
        for kind in ("logreg", "gbt", "knn"):
            r = results[(task, kind)]
            extra = f" (C={best_C[task]})" if kind == "logreg" else ""
            cells.append(f"{pct(r['acc'])} +/- {100 * r['acc_sd']:.1f} / F1 {r['f1']:.3f}{extra}")
        rep.append(f"| {task} | {len(TASKS[task])} | " + " | ".join(cells) + " |")
        print(" ", task, [f"{k}:{results[(task, k)]['acc']:.3f}" for k in ("logreg", "gbt", "knn")], flush=True)
    rep += ["", "Logistic-regression C was chosen per task by the same grouped CV "
            f"(grid {LR_C}). For the variant tasks the examples are only the matching strokes "
            "(groundstroke_spin: the four groundstroke classes plus both slices; serve_type: the three serves), "
            "i.e. the truth stroke family is assumed known.", ""]

    # Held-out evaluation
    rep += ["## Held-out players (never seen in training or model selection)", "",
            "| task | model | accuracy | macro-F1 | beginners | experts |", "|---|---|---|---|---|---|"]
    final, final_pred = {}, {}
    norm = Norm().fit(Xdev)
    n_train = {}
    for task in TASKS:
        drows, dX = subset(dev, Xdev, task)
        trows, tX = subset(test, Xtest, task)
        ytr, yte = np.array(task_labels(drows, task)), np.array(task_labels(trows, task))
        n_train[task] = len(ytr)
        for kind in ("logreg", "gbt", "knn"):
            p, m, _ = fit_predict(kind, dX, ytr, tX, best_C[task])
            acc, f1 = score(yte, p, task)
            ga = group_acc(trows, yte, p)
            rep.append(f"| {task} | {kind} | {pct(acc)} | {f1:.3f} | {pct(ga['beginners'][0])} (n={ga['beginners'][1]}) "
                       f"| {pct(ga['experts'][0])} (n={ga['experts'][1]}) |")
        # exported model: logistic regression on the shared normalisation (fitted on all dev rows)
        m = make_model("logreg", best_C[task]).fit(norm(dX), ytr)
        final[task] = m
        final_pred[task] = (trows, yte, m.predict(norm(tX)))
    rep += ["", "The exported logistic regressions share one normalisation fitted on all development examples; "
            "their held-out numbers below can differ from the table above by a few tenths of a percent for "
            "the variant tasks, whose table rows normalise on the subset.", ""]

    # Exported model details
    rep += ["## Exported model (shared/stroke_model.json): held-out results", "",
            "| task | accuracy | macro-F1 | beginners | experts | CV accuracy (dev) | CV beginners | CV experts |",
            "|---|---|---|---|---|---|---|---|"]
    headline = {}
    for task in TASKS:
        trows, yte, p = final_pred[task]
        acc, f1 = score(yte, p, task)
        ga = group_acc(trows, yte, p)
        r = results[(task, "logreg")]
        gc = group_acc(r["rows"], r["y"], r["pred"])
        headline[task] = (acc, f1, ga, r["acc"], gc)
        rep.append(f"| {task} | {pct(acc)} | {f1:.3f} | {pct(ga['beginners'][0])} | {pct(ga['experts'][0])} "
                   f"| {pct(r['acc'])} | {pct(gc['beginners'][0])} | {pct(gc['experts'][0])} |")
    # Engine baseline for the 3 coarse families it already distinguishes
    fam = {"forehand": "forehand", "backhand_one": "backhand", "backhand_two": "backhand", "serve": "serve"}
    tr = [r for r in test if strokes.COARSE[r["fine"]] in fam]
    eng_acc = np.mean([r["engine_type"] == fam[strokes.COARSE[r["fine"]]] for r in tr])
    trows, yte, p = final_pred["coarse"]
    fam_pred = [fam.get(x, "other") for x in p]
    fam_true = [fam[x] for x in yte if x in fam]
    ours = np.mean([fp == ft for fp, ft, x in zip(fam_pred, [fam.get(x) for x in yte], yte) if x in fam])
    rep += ["", f"For reference, on the held-out forehand / backhand / serve clips (volley and smash excluded, "
            f"n={len(fam_true)}) the engine's own rep type is right {pct(eng_acc)} of the time; the coarse model "
            f"collapsed to the same three families gets {pct(ours)} (it can also answer volley/smash, which costs "
            f"some of these).", ""]

    for task in TASKS:
        trows, yte, p = final_pred[task]
        r = results[(task, "logreg")]
        rep += [f"### Confusion: {task} (held-out players, n={len(yte)})", ""]
        rep += confusion_md(yte, p, TASKS[task])
        rep += ["", f"Pooled out-of-fold over the development players (n={len(r['y'])}):", ""]
        rep += confusion_md(r["y"], r["pred"], TASKS[task])
        rep += [""]

    # Fine model also judged on coarse: how often a fine error is within the family
    trows, yte, p = final_pred["fine"]
    same_family = np.mean([strokes.COARSE[a] == strokes.COARSE[b] for a, b in zip(yte, p) if a != b]) if any(yte != p) else 1.0
    rep += [f"Of the fine-model errors on held-out players, {pct(same_family)} stay within the right coarse family.", ""]

    model = export(final, norm, dev_players, test_players, n_train, headline)
    out = strokes.MODEL_PATH
    out.write_text(json.dumps(model, indent=1))
    print("wrote", out, f"{out.stat().st_size / 1024:.0f} KB")

    # Fixture: a few held-out reps (different classes) that the exported model gets right and confidently.
    strokes.load_model.cache_clear()
    ex, seen = [], set()
    for r in test:
        if r["fine"] in seen:
            continue
        pr = strokes.predict(r["features"], model)
        if pr["fine"]["label"] == r["fine"] and pr["fine"]["probs"][r["fine"]] > 0.6 and pr["coarse"]["label"] == strokes.COARSE[r["fine"]]:
            seen.add(r["fine"])
            ex.append({"name": r["name"], "subject": r["subject"], "fine": r["fine"],
                       "coarse": strokes.COARSE[r["fine"]], "features": r["features"]})
        if len(ex) >= 6:
            break
    EXAMPLES.parent.mkdir(parents=True, exist_ok=True)
    EXAMPLES.write_text(json.dumps({"model_version": model["version"], "examples": ex}, indent=1))

    head = ["# Tennis stroke classification (THETIS)", "",
            "Generated by `ml/train_strokes.py`; model in `shared/stroke_model.json`, inference in `ml/strokes.py` "
            "(`rep_features` + `predict`, numpy only).", "",
            "## Headline (held-out players, exported logistic-regression model)", "",
            "| task | accuracy | macro-F1 | beginners | experts |", "|---|---|---|---|---|"]
    for task, (acc, f1, ga, _, _) in headline.items():
        head.append(f"| {task} ({len(TASKS[task])} classes) | {pct(acc)} | {f1:.3f} | {pct(ga['beginners'][0])} | {pct(ga['experts'][0])} |")
    head += ["", f"Descriptor: {len(strokes.FEATURES)} numbers per rep (16-point dominant and other wrist trajectories "
             "relative to the mid-hip in torso units, dominant side +x; elbow angles and wrist positions at "
             "backswing/contact/finish; two-hand-ness; duration; peak speed; toss apex; engine metrics and rep type). "
             "Percentages are of clips the engine counted; see coverage below for what it missed.", ""]
    REPORT.write_text("\n".join(head + rep) + "\n" + LIMITATIONS)
    print("wrote", REPORT)
    for task, (acc, f1, ga, cva, gc) in headline.items():
        print(f"  {task:18s} held-out acc {acc:.3f} F1 {f1:.3f}  beg {ga['beginners'][0]:.3f} exp {ga['experts'][0]:.3f}  CV {cva:.3f}")


if __name__ == "__main__":
    sys.exit(main())
