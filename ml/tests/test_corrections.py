"""Corrected poses must fix the faulty metric and keep the player's limb lengths."""
import math

import pytest

from formcoach import corrections as cx


def L(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def base_pose():
    # right-handed player facing the camera, image units, torso 0.2
    return {
        "nose": (0.50, 0.28), "l_shoulder": (0.565, 0.35), "r_shoulder": (0.435, 0.35),
        "l_elbow": (0.60, 0.46), "r_elbow": (0.40, 0.46), "l_wrist": (0.62, 0.56), "r_wrist": (0.36, 0.52),
        "l_hip": (0.54, 0.55), "r_hip": (0.46, 0.55), "l_knee": (0.56, 0.70), "r_knee": (0.44, 0.70),
        "l_ankle": (0.60, 0.86), "r_ankle": (0.40, 0.86),
    }


T = 0.2


def lengths(p, side):
    return L(p[side + "_shoulder"], p[side + "_elbow"]), L(p[side + "_elbow"], p[side + "_wrist"])


def angle(p, side):
    s, e, w = p[side + "_shoulder"], p[side + "_elbow"], p[side + "_wrist"]
    v1, v2 = (s[0] - e[0], s[1] - e[1]), (w[0] - e[0], w[1] - e[1])
    return math.degrees(math.acos((v1[0] * v2[0] + v1[1] * v2[1]) / (math.hypot(*v1) * math.hypot(*v2))))


def test_straightening_keeps_bone_lengths():
    p = base_pose()
    before = lengths(p, "r")
    q = cx.corrected_pose("basketball", "elbow_extension", 175, p, None, T, "r")
    assert angle(q, "r") > 179
    assert lengths(q, "r") == pytest.approx(before)
    assert q["l_wrist"] == p["l_wrist"]          # nothing else moved


def test_elbow_raised_to_nose_level():
    p = base_pose()
    q = cx.corrected_pose("racket", "elbow_finish", 0.0, p, None, T, "r")
    assert q["r_elbow"][1] == pytest.approx(p["nose"][1], abs=1e-6)
    assert lengths(q, "r") == pytest.approx(lengths(p, "r"))


def test_finish_height_lifts_wrist_above_opposite_shoulder():
    p = base_pose()
    q = cx.corrected_pose("racket", "finish_height", 0.3, p, None, T, "r")
    assert (q["l_shoulder"][1] - q["r_wrist"][1]) / T == pytest.approx(0.3, abs=0.02)


def test_weight_shift_moves_hips_forward_but_keeps_feet():
    p = base_pose()
    back = dict(p, r_wrist=(0.30, 0.50))       # swing goes toward +x: the right ankle is the back foot
    q = cx.corrected_pose("racket", "weight_shift", 0.5, p, back, T, "r")
    width = 0.60 - 0.40
    hip0 = (back["l_hip"][0] + back["r_hip"][0]) / 2
    hip1 = (q["l_hip"][0] + q["r_hip"][0]) / 2
    assert (hip1 - hip0) / width == pytest.approx(0.5, abs=1e-6)
    assert q["l_ankle"] == p["l_ankle"] and q["r_ankle"] == p["r_ankle"]


def test_lowering_hips_bends_knees_with_planted_feet():
    p = base_pose()
    q = cx.corrected_pose("racket", "stance_height", 1.2, p, None, T, "r")
    hip = ((q["l_hip"][1] + q["r_hip"][1]) / 2)
    assert (0.86 - hip) / T == pytest.approx(1.2, abs=1e-6)
    for s in ("l", "r"):
        assert L(q[s + "_hip"], q[s + "_knee"]) == pytest.approx(L(p[s + "_hip"], p[s + "_knee"]))
        assert L(q[s + "_knee"], q[s + "_ankle"]) == pytest.approx(L(p[s + "_knee"], p[s + "_ankle"]))


def test_rotation_cues_have_no_flat_ghost():
    assert cx.corrected_pose("racket", "shoulder_turn", 0.4, base_pose(), base_pose(), T, "r") is None
    assert cx.corrected_pose("golf", "shoulder_turn", 0.4, base_pose(), base_pose(), T, "r") is None


def test_elbow_raise_keeps_the_hand_when_reachable():
    p = base_pose()
    p["r_wrist"] = (0.47, 0.30)                     # hand up by the face after the finish
    q = cx.corrected_pose("racket", "elbow_finish", 0.0, p, None, T, "r")
    assert q["r_elbow"][1] == pytest.approx(p["nose"][1], abs=1e-6)
    assert L(q["r_elbow"], q["r_wrist"]) == pytest.approx(L(p["r_elbow"], p["r_wrist"]))
    assert L(q["r_wrist"], p["r_wrist"]) < 0.06      # hand barely moves, never thrown above the head


def test_racket_head_stability_has_no_flat_ghost():
    assert cx.corrected_pose("racket", "head_stability", 0.0, base_pose(), base_pose(), T, "r") is None


def test_golf_head_lift_moves_whole_body_without_stretching():
    p, ref = base_pose(), dict(base_pose(), nose=(0.50, 0.24))
    q = cx.corrected_pose("golf", "head_lift", 0.0, p, ref, T, "r")
    torso = lambda z: L(((z["l_shoulder"][0] + z["r_shoulder"][0]) / 2, (z["l_shoulder"][1] + z["r_shoulder"][1]) / 2),
                        ((z["l_hip"][0] + z["r_hip"][0]) / 2, (z["l_hip"][1] + z["r_hip"][1]) / 2))
    assert torso(q) == pytest.approx(torso(p))
    assert q["nose"][1] < p["nose"][1]


def test_timing_metrics_have_no_pose_fix():
    assert cx.corrected_pose("golf", "tempo_ratio", 3.0, base_pose(), None, T, "r") is None
    assert cx.corrected_pose("basketball", "shot_rhythm", 0.4, base_pose(), None, T, "r") is None


def test_every_rule_runs_on_a_full_pose():
    p, ref = base_pose(), dict(base_pose(), r_wrist=(0.30, 0.50))
    for analyzer, rules in cx.EVENTS.items():
        for metric in rules:
            assert cx.corrected_pose(analyzer, metric, 0.5, p, ref, T, "r") is not None, (analyzer, metric)
