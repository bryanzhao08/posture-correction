"""The exported stroke model loads, gives valid probabilities and keeps its labels on held-out reps."""
import json
import math
from pathlib import Path

import numpy as np
import pytest

import strokes

EXAMPLES = Path(__file__).resolve().parent / "data" / "stroke_examples.json"


@pytest.fixture(scope="module")
def model():
    return strokes.load_model()


@pytest.fixture(scope="module")
def examples():
    return json.loads(EXAMPLES.read_text())["examples"]


def test_model_json_is_consistent(model):
    nf = len(model["features"])
    assert model["features"] == strokes.FEATURES
    for key in ("impute", "mean", "std"):
        assert len(model["normalization"][key]) == nf
    assert all(s > 0 for s in model["normalization"]["std"])
    assert {"coarse", "fine", "groundstroke_spin", "serve_type"} <= set(model["tasks"])
    for task in model["tasks"].values():
        assert len(task["weights"]) == len(task["classes"]) == len(task["bias"])
        assert all(len(w) == nf for w in task["weights"])
    assert model["tasks"]["coarse"]["classes"] == strokes.COARSE_CLASSES
    assert model["tasks"]["fine"]["classes"] == strokes.FINE_CLASSES
    assert "research" in model["training_data"]["licence_note"]
    assert model["version"]


def _check_probs(out):
    for task in out.values():
        p = list(task["probs"].values())
        assert all(0.0 <= v <= 1.0 and math.isfinite(v) for v in p)
        assert abs(sum(p) - 1.0) < 1e-9
        assert task["label"] == max(task["probs"], key=task["probs"].get)


def test_predict_returns_probabilities(model, examples):
    for ex in examples:
        _check_probs(strokes.predict(ex["features"], model))
    # ordered list input gives the same answer as the dict
    ex = examples[0]
    a = strokes.predict(ex["features"], model)
    b = strokes.predict([ex["features"][n] for n in model["features"]], model)
    assert a["fine"]["probs"] == pytest.approx(b["fine"]["probs"])


def test_missing_values_are_imputed(model):
    out = strokes.predict({}, model)                 # every feature missing -> the training medians
    _check_probs(out)
    with pytest.raises(ValueError):
        strokes.predict([0.0] * 3, model)


def test_labels_stable_on_held_out_reps(model, examples):
    held_out = set(model["training_data"]["players_held_out"])
    assert len(examples) >= 4
    for ex in examples:
        assert ex["subject"] in held_out
        out = strokes.predict(ex["features"], model)
        assert out["fine"]["label"] == ex["fine"], ex["name"]
        assert out["coarse"]["label"] == ex["coarse"], ex["name"]


def test_features_recomputed_from_poses_match(examples):
    """When the THETIS poses are present, the engine + rep_features reproduce the stored descriptors."""
    import datasets
    by_name = {ex["name"]: ex for ex in examples}
    folders = {f: c for f, c in strokes.THETIS_FOLDERS.items() if c in {ex["fine"] for ex in examples}}
    if not any((datasets.DATA / "poses" / "thetis" / f).exists() for f in folders):
        pytest.skip("THETIS poses not downloaded")
    checked = 0
    for name, rec, _ in datasets.thetis(folders):
        if name not in by_name:
            continue
        eng, samples = strokes.analyze_with_samples(rec)
        rep = max(eng.reps, key=lambda r: r.peak_speed)
        f = strokes.rep_features(samples, rep, "r")
        want = by_name[name]["features"]
        for k in strokes.FEATURES:
            if want[k] is None:
                assert f[k] is None, k
            else:
                assert f[k] == pytest.approx(want[k], rel=1e-9, abs=1e-9), k
        checked += 1
    assert checked == len(examples)


def test_rep_features_shape():
    """Synthetic engine samples: the descriptor has every feature and the dominant side is +x."""
    from formcoach.engine import Sample
    samples = []
    for i in range(20):
        t = i / 20
        x = 0.4 - 0.04 * i                     # right wrist sweeping across the body (image right to left)
        pts = {"l_shoulder": (0.6, 0.4), "r_shoulder": (0.4, 0.4), "l_hip": (0.55, 0.7), "r_hip": (0.45, 0.7),
               "r_wrist": (0.5 + x, 0.6), "l_wrist": (0.6, 0.65), "r_elbow": (0.45, 0.5), "l_elbow": (0.6, 0.55)}
        samples.append(Sample(t, pts, 0.3, (0.5, 0.7), x / 0.3, -0.1 / 0.3, 3.0))
    rep = {"t_start": 0.0, "t_end": 0.95, "type": "forehand",
           "events": {"backswing": 0.0, "contact": 0.5, "finish": 0.95}, "metrics": {"contact_arm": 150.0}}
    f = strokes.rep_features(samples, rep, "r")
    assert set(f) == set(strokes.FEATURES)
    # the right shoulder is on image left, so the wrist starting right of the hip in the image is on
    # the player's non-dominant side (-x) and ends on the dominant side (+x)
    assert f["dom_x_0"] < 0 < f["dom_x_15"]
    assert f["m_contact_arm"] == 150.0 and f["m_spacing"] is None
    assert np.isfinite(strokes.vectorize(f, strokes.load_model())).all()
