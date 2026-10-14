"""The Swift engine (ios/FormCore) must produce the same reps, metrics and scores as this one."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

import datasets
from formcoach.engine import PROFILES_PATH, analyze_recording, load_profiles
from formcoach.scoring import summarize
from formcoach.synth import recording
from tests.test_engine import CASES

PKG = Path(__file__).resolve().parents[2] / "ios" / "FormCore"
WEB = Path(__file__).resolve().parents[2] / "web"
# SWIFT_SCRATCH redirects the Swift build directory (e.g. when ios/FormCore/.build is not writable)
SCRATCH = Path(os.environ.get("SWIFT_SCRATCH") or PKG / ".build")


def build_swift():
    build = subprocess.run(["swift", "build", "-c", "release", "--package-path", str(PKG), "--scratch-path", str(SCRATCH)],
                           capture_output=True, text=True)
    assert build.returncode == 0, build.stderr[-4000:] + build.stdout[-4000:]
    return SCRATCH / "release" / "formcore-check"


def fixture(name, rec, profiles):
    eng = analyze_recording(rec, profiles)
    reps = [r.to_dict() for r in eng.reps]
    summ = summarize(rec["sport"], reps, eng.rejected, eng.profile["metrics"],
                     profiles["scoring"], eng.active_s, eng.passive_s)
    return {"name": name, "recording": rec,
            "expected": {"reps": reps, "rejected": eng.rejected, "score": summ["score"]}}


def real_samples(per_dataset=12):
    """A few real recordings from each dataset, when the datasets have been downloaded."""
    out = []
    for loader in (datasets.golfdb, datasets.spl, datasets.thetis):
        try:
            for i, item in enumerate(loader()):
                if i % 7 == 0:
                    out.append(item[:2])
                if len(out) % per_dataset == 0 and i % 7 == 0 and i > 0:
                    break
        except (FileNotFoundError, ImportError, KeyError):
            continue
    return out


def view_samples(every=4):
    """Real tennis clips filmed from the front, side and behind, analysed with that camera view."""
    out = []
    try:
        for i, (name, rec, truth) in enumerate(datasets.penn_action({"tennis_forehand", "tennis_serve"})):
            if i % every == 0:
                out.append((f"{name}-{truth['view']}", dict(rec, sport="tennis", view=truth["view"],
                                                            focus="serve" if truth["action"] == "tennis_serve" else None)))
    except (FileNotFoundError, ImportError):
        pass
    return out


@pytest.mark.skipif(shutil.which("swift") is None, reason="Swift toolchain not installed")
def test_swift_engine_matches_python(tmp_path):
    path = tmp_path / "fixtures.json"
    path.write_text(json.dumps(engine_fixtures()))
    exe = build_swift()
    run = subprocess.run([str(exe), str(path), str(PROFILES_PATH)], capture_output=True, text=True)
    print(run.stdout)
    assert run.returncode == 0, run.stdout[-6000:] + run.stderr[-2000:]


def engine_fixtures():
    profiles = load_profiles()
    fx = []
    for name, (sport, script, _) in CASES.items():
        hand = "left" if name.startswith("left") else "right"
        for noise, seed in ((0.0015, 1), (0.004, 7)):
            fx.append(fixture(f"{name}-{seed}", recording(sport, script, noise=noise, seed=seed, handedness=hand),
                              profiles))
    fx += [fixture(n, r, profiles) for n, r in real_samples()]
    fx += [fixture(n, r, profiles) for n, r in view_samples()]
    fx += personalized_fixtures(profiles)
    return fx


def personalized_fixtures(profiles):
    """Every drill and level, plus heights that shift (and clamp) the height-adjusted metrics."""
    out = []
    levels = list(profiles["player"]["levels"])
    heights = (None, 150.0, 175.0, 199.0, 230.0)
    for name, (sport, script, _) in CASES.items():
        if not name.endswith(("3_swings", "2_shots", "mixed", "dinks")):
            continue
        hand = "left" if name.startswith("left") else "right"
        base = recording(sport, script, noise=0.003, seed=3, handedness=hand)
        for i, d in enumerate(profiles["sports"][sport]["drills"]):
            player = {"level": levels[i % len(levels)], "height_cm": heights[i % len(heights)]}
            out.append(fixture(f"{name}-{d['id']}-{player['level']}", dict(base, drill=d["id"], player=player), profiles))
    return out


@pytest.mark.skipif(shutil.which("node") is None, reason="Node.js not installed")
def test_web_engine_matches_python(tmp_path):
    """The browser demo (web/src/engine, TypeScript run directly by Node 23+) must agree too."""
    path = tmp_path / "fixtures.json"
    path.write_text(json.dumps(engine_fixtures()))
    run = subprocess.run(["node", str(WEB / "scripts" / "check.ts"), str(path), str(PROFILES_PATH)],
                         capture_output=True, text=True)
    print(run.stdout)
    assert run.returncode == 0, run.stdout[-6000:] + run.stderr[-2000:]


def correction_fixtures():
    """Every correction rule applied to a few real poses, with the Python result as the expectation."""
    from formcoach import corrections as cx
    from tests.test_corrections import base_pose
    poses = [base_pose()]
    try:
        for i, (_, rec, _) in enumerate(datasets.thetis()):
            if i % 40 == 0:
                fr = rec["frames"][len(rec["frames"]) // 2]["j"]
                if all(j[2] > 0.3 for j in fr):
                    poses.append({n: (j[0] * rec["aspect"], j[1]) for n, j in zip(load_profiles()["joints"], fr)})
            if len(poses) >= 4:
                break
    except (FileNotFoundError, ImportError):
        pass
    out = []
    for k, pose in enumerate(poses):
        ref = {n: (x + 0.03 * ((hash(n) % 5) - 2), y) for n, (x, y) in pose.items()}
        for analyzer, rules in cx.EVENTS.items():
            for metric in rules:
                for target in (0.0, 0.4, 1.1):
                    t = 160.0 if metric in ("elbow_extension", "contact_arm") else (8.0 if metric == "arm_verticality" else target)
                    got = cx.corrected_pose(analyzer, metric, t, pose, ref, 0.2, "r")
                    out.append({"analyzer": analyzer, "metric": metric, "target": t, "pose": pose, "ref": ref,
                                "torso": 0.2, "dom": "r", "expected": got})
    return out


@pytest.mark.skipif(shutil.which("node") is None, reason="Node.js not installed")
def test_web_corrections_match_python(tmp_path):
    path = tmp_path / "corrections.json"
    path.write_text(json.dumps(correction_fixtures()))
    run = subprocess.run(["node", str(WEB / "scripts" / "check.ts"), "--corrections", str(path)],
                         capture_output=True, text=True)
    print(run.stdout)
    assert run.returncode == 0, run.stdout[-6000:] + run.stderr[-2000:]


@pytest.mark.skipif(shutil.which("swift") is None, reason="Swift toolchain not installed")
def test_swift_corrections_match_python(tmp_path):
    path = tmp_path / "corrections.json"
    path.write_text(json.dumps(correction_fixtures()))
    run = subprocess.run([str(build_swift()), "--corrections", str(path)],
                         capture_output=True, text=True)
    print(run.stdout)
    assert run.returncode == 0, run.stdout[-6000:] + run.stderr[-2000:]


def strokes_fixtures():
    """Held-out descriptors plus native engine replays (left/right, views and sample rates)."""
    import strokes
    model = strokes.load_model()
    examples = json.loads((Path(__file__).parent / "data" / "stroke_examples.json").read_text())["examples"]
    cases = []
    def expected(features):
        return {"features": features, "prediction": strokes.predict(features, model)}
    for ex in examples:
        cases.append({"name": ex["name"], "features": ex["features"], "expected": expected(ex["features"])})
    cases.append({"name": "all_missing", "features": {}, "expected": expected({})})
    profiles = load_profiles()
    for name, (sport, script, _) in CASES.items():
        if sport != "tennis":
            continue
        for fps in (30.0, 60.0):
            for view in ("front", "side", "back"):
                hand = "left" if name.startswith("left") else "right"
                rec = dict(recording(sport, script, fps=fps, noise=0.003, seed=7, handedness=hand), view=view)
                eng, samples = strokes.analyze_with_samples(rec, profiles)
                dom = "l" if hand == "left" else "r"
                cases.append({"name": f"{name}-{fps}-{view}", "recording": rec,
                              "expected": [expected(strokes.rep_features(samples, rep, dom)) for rep in eng.reps]})
                if name == "tennis_mixed" and fps == 30.0 and view == "front":
                    # Missing events, optional joints and the off wrist exercise imputation/filling.
                    from dataclasses import replace
                    rep = eng.reps[0].to_dict()
                    rep["events"] = {}
                    sparse = [replace(s, pts={k: v for k, v in s.pts.items() if k not in ("l_wrist", "nose", "l_ankle")}) for s in samples]
                    f = strokes.rep_features(sparse, rep, dom)
                    cases.append({"name": "missing_events_off_wrist_optional_joints", "samples": [vars(s) for s in sparse],
                                  "rep": rep, "dom": dom, "expected": expected(f)})
    return {"model_path": str(strokes.MODEL_PATH), "profiles": profiles, "cases": cases}


@pytest.mark.skipif(shutil.which("node") is None, reason="Node.js not installed")
def test_web_strokes_match_python(tmp_path):
    path = tmp_path / "strokes.json"
    path.write_text(json.dumps(strokes_fixtures()))
    run = subprocess.run(["node", str(WEB / "scripts" / "check.ts"), "--strokes", str(path)], capture_output=True, text=True)
    assert run.returncode == 0, run.stdout + run.stderr


@pytest.mark.skipif(shutil.which("swift") is None, reason="Swift toolchain not installed")
def test_swift_strokes_match_python(tmp_path):
    path = tmp_path / "strokes.json"
    path.write_text(json.dumps(strokes_fixtures()))
    run = subprocess.run([str(build_swift()), "--strokes", str(path)], capture_output=True, text=True)
    assert run.returncode == 0, run.stdout + run.stderr
