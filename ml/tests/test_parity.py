"""The Swift engine (ios/FormCore) must produce the same reps, metrics and scores as this one."""
import json
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


def fixture(name, rec, profiles):
    eng = analyze_recording(rec, profiles)
    reps = [r.to_dict() for r in eng.reps]
    summ = summarize(rec["sport"], reps, eng.rejected, profiles["sports"][rec["sport"]]["metrics"],
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
    profiles = load_profiles()
    fx = []
    for name, (sport, script, _) in CASES.items():
        hand = "left" if name.startswith("left") else "right"
        for noise, seed in ((0.0015, 1), (0.004, 7)):
            fx.append(fixture(f"{name}-{seed}", recording(sport, script, noise=noise, seed=seed, handedness=hand),
                              profiles))
    fx += [fixture(n, r, profiles) for n, r in real_samples()]
    fx += [fixture(n, r, profiles) for n, r in view_samples()]
    path = tmp_path / "fixtures.json"
    path.write_text(json.dumps(fx))
    build = subprocess.run(["swift", "build", "-c", "release", "--package-path", str(PKG)],
                           capture_output=True, text=True)
    assert build.returncode == 0, build.stderr[-4000:] + build.stdout[-4000:]
    exe = PKG / ".build" / "release" / "formcore-check"
    run = subprocess.run([str(exe), str(path), str(PROFILES_PATH)], capture_output=True, text=True)
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


@pytest.mark.skipif(shutil.which("swift") is None, reason="Swift toolchain not installed")
@pytest.mark.xfail(reason="Swift port of corrections pending (Codex batch 7 removes this mark)", strict=False)
def test_swift_corrections_match_python(tmp_path):
    path = tmp_path / "corrections.json"
    path.write_text(json.dumps(correction_fixtures()))
    build = subprocess.run(["swift", "build", "-c", "release", "--package-path", str(PKG)], capture_output=True, text=True)
    assert build.returncode == 0, build.stderr[-4000:]
    run = subprocess.run([str(PKG / ".build" / "release" / "formcore-check"), "--corrections", str(path)],
                         capture_output=True, text=True)
    print(run.stdout)
    assert run.returncode == 0, run.stdout[-6000:] + run.stderr[-2000:]
