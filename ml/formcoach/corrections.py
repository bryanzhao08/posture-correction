"""Corrected poses for "replay with fix": the player's own pose at the key moment of a rep, with only
the faulty body part moved to where the coaching cue says it should be.

Keeping the player's proportions and everything else unchanged makes the ghost skeleton show the fix
itself rather than a different body. Bone lengths of every moved limb are preserved.

All points are in the engine's units: (x, y) in image-height units, y down; `torso` is the torso
length in those units. `pose` and `ref` are dicts of joint name -> (x, y).
"""
from __future__ import annotations

import math

# metric id -> (event at which to show the fix, reference event or None). Metrics about timing or
# whole-swing paths (tempo, rhythm, hold, swing-through) have no single-pose fix and are absent, and
# so are rotations (shoulder turn) and racket-sport head stability: in 2D, turning and head movement
# blur together, so a flat ghost reads wrong. Those cues rely on the 3D hologram demo instead.
EVENTS = {
    "golf": {
        "lead_arm_top": ("top", None), "head_sway": ("impact", "address"), "head_lift": ("impact", "address"),
        "hip_sway": ("top", "address"), "finish_balance": ("finish", None),
    },
    "basketball": {
        "elbow_extension": ("release", None), "elbow_flare": ("set", None), "release_height": ("release", None),
        "arm_verticality": ("release", None), "guide_hand_gap": ("release", None), "lateral_drift": ("end", "start"),
    },
    "racket": {
        "finish_height": ("follow_through", None), "elbow_finish": ("follow_through", None),
        "off_hand_reach": ("backswing", None), "spacing": ("contact", None), "contact_front": ("contact", "backswing"),
        "back_load": ("backswing", "contact"), "weight_shift": ("contact", "backswing"), "contact_arm": ("contact", None),
        "contact_height": ("contact", None), "stance_height": ("contact", None),
        "ready_height": ("start", None), "backswing_size": ("backswing", None),
    },
}

UPPER = ("nose", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist")


def _len(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def _mid(a, b):
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)


def _shift(p: dict, names, dx: float, dy: float):
    for n in names:
        if n in p:
            p[n] = (p[n][0] + dx, p[n][1] + dy)


def _ik(root, target, l1, l2, bend_ref):
    """Two-bone IK: middle joint for a chain root->mid->end reaching target, bending to the same side
    as bend_ref (the current middle joint). Clamps an unreachable target onto the reach circle."""
    dx, dy = target[0] - root[0], target[1] - root[1]
    d = math.hypot(dx, dy)
    reach = (l1 + l2) * 0.999
    if d < 1e-9:
        return bend_ref, target
    if d > reach:
        target = (root[0] + dx / d * reach, root[1] + dy / d * reach)
        dx, dy, d = target[0] - root[0], target[1] - root[1], reach
    d = max(d, abs(l1 - l2) + 1e-6)
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    mx, my = root[0] + a * dx / d, root[1] + a * dy / d
    cands = [(mx - h * dy / d, my + h * dx / d), (mx + h * dy / d, my - h * dx / d)]
    side = (dx * (bend_ref[1] - root[1]) - dy * (bend_ref[0] - root[0])) >= 0
    mid = cands[0] if ((dx * (cands[0][1] - root[1]) - dy * (cands[0][0] - root[0])) >= 0) == side else cands[1]
    return mid, target


def _place_wrist(p: dict, side: str, target):
    s, e, w = p[side + "_shoulder"], p[side + "_elbow"], p[side + "_wrist"]
    mid, end = _ik(s, target, _len(s, e), _len(e, w), e)
    p[side + "_elbow"], p[side + "_wrist"] = mid, end


def _straighten(p: dict, side: str):
    s, e, w = p[side + "_shoulder"], p[side + "_elbow"], p[side + "_wrist"]
    l1, l2 = _len(s, e), _len(e, w)
    d = _len(s, w)
    if d < 1e-9:
        return
    ux, uy = (w[0] - s[0]) / d, (w[1] - s[1]) / d
    p[side + "_elbow"] = (s[0] + ux * l1, s[1] + uy * l1)
    p[side + "_wrist"] = (s[0] + ux * (l1 + l2), s[1] + uy * (l1 + l2))


def _elbow_to_height(p: dict, side: str, y: float):
    """Swing the upper arm about the shoulder so the elbow sits at height y. The hand stays where it
    was when the forearm can still reach it; otherwise it moves the least distance that keeps the
    forearm its length."""
    s, e, w = p[side + "_shoulder"], p[side + "_elbow"], p[side + "_wrist"]
    l1, l2 = _len(s, e), _len(e, w)
    dy = max(-l1, min(l1, y - s[1]))
    dx = math.sqrt(max(l1 * l1 - dy * dy, 0.0)) * (1 if e[0] >= s[0] else -1)
    ne = (s[0] + dx, s[1] + dy)
    d = _len(ne, w)
    p[side + "_elbow"] = ne
    if d > 1e-9:
        p[side + "_wrist"] = (ne[0] + (w[0] - ne[0]) * l2 / d, ne[1] + (w[1] - ne[1]) * l2 / d)


def _hips(p: dict):
    return _mid(p["l_hip"], p["r_hip"])


def _move_body_x(p: dict, dx: float):
    """Shift the body over the feet: upper body and hips fully, knees half, ankles stay planted."""
    _shift(p, UPPER + ("l_hip", "r_hip"), dx, 0.0)
    _shift(p, ("l_knee", "r_knee"), dx / 2.0, 0.0)


def _lower_hips(p: dict, dy: float):
    legs = {s: (_len(p[s + "_hip"], p[s + "_knee"]), _len(p[s + "_knee"], p[s + "_ankle"]))
            for s in ("l", "r") if all(s + j in p for j in ("_hip", "_knee", "_ankle"))}
    _shift(p, UPPER + ("l_hip", "r_hip"), 0.0, dy)
    for s, (thigh, shin) in legs.items():
        mid, _ = _ik(p[s + "_hip"], p[s + "_ankle"], thigh, shin, p[s + "_knee"])
        p[s + "_knee"] = mid


def corrected_pose(analyzer: str, metric: str, target: float, pose: dict, ref: dict | None,
                   torso: float, dom: str, rep_type: str = "") -> dict | None:
    """The pose with the fault for `metric` corrected to `target` (the metric's reference mean).
    Returns None when the metric has no single-pose correction or a needed joint is missing."""
    rule = EVENTS.get(analyzer, {}).get(metric)
    if rule is None:
        return None
    p = dict(pose)
    off = "l" if dom == "r" else "r"
    T = torso
    try:
        if analyzer == "golf":
            lead = off
            if metric == "lead_arm_top":
                _straighten(p, lead)
            elif metric == "head_sway":
                p["nose"] = (ref["nose"][0], p["nose"][1])
            elif metric == "head_lift":
                # stay in posture: the whole body returns to its address height, knees re-bent
                dy = ref["nose"][1] + target * T - p["nose"][1]
                _lower_hips(p, max(-0.3 * T, min(0.3 * T, dy)))
            elif metric == "hip_sway":
                hx, rx = _hips(p)[0], _hips(ref)[0]
                want = rx + math.copysign(target * T, hx - rx)
                _shift(p, ("l_hip", "r_hip"), want - hx, 0.0)
                _shift(p, ("l_knee", "r_knee"), (want - hx) / 2.0, 0.0)
            elif metric == "finish_balance":
                ankle = p[lead + "_ankle"]
                hx = _hips(p)[0]
                want = ankle[0] + math.copysign(target * T, hx - ankle[0])
                _move_body_x(p, want - hx)
        elif analyzer == "basketball":
            s = p[dom + "_shoulder"]
            if metric == "elbow_extension":
                _straighten(p, dom)
            elif metric == "elbow_flare":
                width = _len(p["l_shoulder"], p["r_shoulder"])
                e = p[dom + "_elbow"]
                want = s[0] + math.copysign(target * width, e[0] - s[0])
                _shift(p, (dom + "_elbow", dom + "_wrist"), want - e[0], 0.0)
            elif metric == "release_height":
                _place_wrist(p, dom, (p[dom + "_wrist"][0], s[1] - target * T))
            elif metric == "arm_verticality":
                w = p[dom + "_wrist"]
                L = _len(s, p[dom + "_elbow"]) + _len(p[dom + "_elbow"], w)
                a = math.radians(target)
                sign = 1 if w[0] >= s[0] else -1
                _place_wrist(p, dom, (s[0] + sign * L * math.sin(a), s[1] - L * math.cos(a)))
            elif metric == "guide_hand_gap":
                w = p[dom + "_wrist"]
                side = 1 if p[off + "_shoulder"][0] >= s[0] else -1
                _place_wrist(p, off, (w[0] + side * target * T, w[1] + 0.15 * T))
            elif metric == "lateral_drift":
                hx, rx = _hips(p)[0], _hips(ref)[0]
                want = rx + math.copysign(target * T, hx - rx)
                _move_body_x(p, want - hx)
        else:  # racket sports
            hip = _hips(p)
            w = p[dom + "_wrist"]
            if metric == "finish_height":
                _place_wrist(p, dom, (w[0], p[off + "_shoulder"][1] - target * T))
            elif metric == "elbow_finish":
                _elbow_to_height(p, dom, p["nose"][1] - target * T)
            elif metric == "off_hand_reach":
                _straighten(p, off)
            elif metric == "spacing":
                _place_wrist(p, dom, (hip[0] + math.copysign(target * T, w[0] - hip[0]), w[1]))
            elif metric in ("contact_front", "weight_shift", "back_load"):
                contact, back = (p, ref) if metric != "back_load" else (ref, p)
                fwd = 1.0 if contact[dom + "_wrist"][0] >= back[dom + "_wrist"][0] else -1.0
                la, ra = p["l_ankle"], p["r_ankle"]
                back_x, front_x = sorted((la[0], ra[0]), key=lambda v: v * fwd)
                if metric == "contact_front":
                    _place_wrist(p, dom, (front_x + fwd * target * T, w[1]))
                else:
                    width = (front_x - back_x) * fwd
                    if width <= 0:
                        return None
                    if metric == "back_load":
                        want = back_x + fwd * target * width
                    else:
                        want = _hips(ref)[0] + fwd * target * width
                    _move_body_x(p, want - hip[0])
            elif metric == "contact_arm":
                _straighten(p, dom)
            elif metric == "contact_height":
                _place_wrist(p, dom, (w[0], hip[1] + target * T))
            elif metric == "stance_height":
                ankles = _mid(p["l_ankle"], p["r_ankle"])
                _lower_hips(p, (ankles[1] - target * T) - hip[1])
            elif metric == "ready_height":
                _place_wrist(p, dom, (w[0], hip[1] + target * T))
            elif metric == "backswing_size":
                c = (hip[0], hip[1] - 0.5 * T)
                d = _len(w, c)
                if d < 1e-9:
                    return None
                k = target * T / d
                _place_wrist(p, dom, (c[0] + (w[0] - c[0]) * k, c[1] + (w[1] - c[1]) * k))
    except (KeyError, TypeError):
        return None
    return p
