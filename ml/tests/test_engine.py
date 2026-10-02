import pytest

from formcoach.engine import analyze_recording, load_profiles
from formcoach.synth import recording

P = load_profiles()

# (sport, script, expected rep types)
CASES = {
    "golf_3_swings": ("golf", [("rest", 1.5), ("golf_swing",), ("rest", 1.5), ("golf_swing",),
                               ("rest", 1.0), ("golf_swing",), ("rest", 1.5)], ["swing"] * 3),
    "golf_waggles_then_swing": ("golf", [("rest", 1.0), ("golf_waggle",), ("golf_waggle",), ("rest", 0.8),
                                         ("golf_swing",), ("rest", 1.5)], ["swing"]),
    "golf_idle_walk_stretch": ("golf", [("rest", 2.0), ("walk", 3.0), ("rest", 1.0), ("stretch",),
                                        ("rest", 1.0), ("scratch_head",), ("rest", 1.0)], []),
    "basketball_2_shots": ("basketball", [("rest", 1.0), ("basketball_shot",), ("rest", 1.2),
                                          ("basketball_shot",), ("rest", 1.0)], ["shot"] * 2),
    "basketball_dribble_then_shot": ("basketball", [("rest", 1.0), ("basketball_dribble",),
                                                    ("basketball_dribble",), ("rest", 0.5),
                                                    ("basketball_shot",), ("rest", 1.0)], ["shot"]),
    "basketball_idle": ("basketball", [("rest", 1.5), ("walk", 3.0), ("rest", 0.5), ("scratch_head",),
                                       ("stretch",), ("rest", 1.0)], []),
    "tennis_mixed": ("tennis", [("rest", 1.0), ("tennis_forehand",), ("rest", 0.6), ("tennis_backhand",),
                                ("rest", 0.6), ("tennis_serve",), ("rest", 1.0)],
                     ["forehand", "backhand", "serve"]),
    "tennis_idle": ("tennis", [("rest", 1.5), ("walk", 3.0), ("rest", 1.0), ("scratch_head",),
                               ("rest", 1.0)], []),
    "pickleball_dinks": ("pickleball", [("rest", 1.0), ("pickleball_dink",), ("rest", 0.4),
                                        ("pickleball_dink",), ("rest", 0.4), ("pickleball_dink",),
                                        ("rest", 1.0)], ["forehand"] * 3),
    "pickleball_idle": ("pickleball", [("rest", 1.5), ("walk", 3.0), ("rest", 1.0), ("scratch_head",),
                                   ("rest", 1.0), ("stretch",), ("rest", 1.0)], []),
    "left_handed_forehand": ("tennis", [("rest", 1.0), ("tennis_forehand",), ("rest", 1.0)], ["forehand"]),
}


def run(name, **kw):
    sport, script, expected = CASES[name]
    if name.startswith("left_handed"):
        kw["handedness"] = "left"
    return analyze_recording(recording(sport, script, **kw), P), expected


@pytest.mark.parametrize("name", CASES)
@pytest.mark.parametrize("fps", [30.0, 60.0])
def test_counts(name, fps):
    eng, expected = run(name, fps=fps)
    assert [r.type for r in eng.reps] == expected, eng.rejected


@pytest.mark.parametrize("name", CASES)
def test_counts_survive_pose_noise(name):
    eng, expected = run(name, noise=0.004, seed=7)
    assert len(eng.reps) == len(expected), eng.rejected


def test_person_leaving_frame_mid_swing_is_not_counted():
    rec = recording("golf", [("rest", 1.5), ("golf_swing",), ("rest", 1.0)])
    for fr in rec["frames"]:
        if 2.6 < fr["t"] < 4.2:
            fr["j"] = [[0, 0, 0.0]] * 13
    eng = analyze_recording(rec, P)
    assert eng.reps == []


def test_golf_metrics_are_plausible():
    eng, _ = run("golf_3_swings")
    m = eng.reps[0].metrics
    assert 1.5 < m["tempo_ratio"] < 4.5
    assert m["head_sway"] < 0.1
    assert 0 <= eng.reps[0].score <= 100


def test_active_and_passive_time_are_tracked():
    eng, _ = run("golf_3_swings")
    assert 4.0 < eng.active_s < 9.0
    assert eng.passive_s > 4.0
