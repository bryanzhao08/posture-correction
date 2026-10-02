"""Synthetic stick-figure recordings with known ground truth, for tests and Swift parity fixtures."""
from __future__ import annotations

import math
import random

JOINTS = ["nose", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist",
          "l_hip", "r_hip", "l_knee", "r_knee", "l_ankle", "r_ankle"]

TORSO = 0.20
UPPER, FORE = 0.125, 0.115
THIGH = SHIN = 0.15
ASPECT = 9.0 / 16.0

# Hand keyframes: (seconds to reach, x, y, knee_drop) in torso units relative to mid-hip.
# +x is the person's right side (image left when facing an unmirrored camera).
MOTIONS = {
    "golf_swing": [(0.85, 1.0, -1.25, 0.0), (0.27, 0.0, 0.35, 0.0), (0.45, -1.0, -1.35, 0.0),
                   (0.6, -1.0, -1.35, 0.0), (1.2, 0.0, 0.35, 0.0)],
    "golf_waggle": [(0.4, 0.25, 0.25, 0.0), (0.4, 0.0, 0.35, 0.0)],
    "basketball_shot": [(0.35, 0.3, -0.4, 0.25), (0.35, 0.3, -2.15, 0.0), (0.6, 0.3, -2.15, 0.0),
                        (0.9, 0.4, 0.2, 0.0)],
    "basketball_dribble": [(0.2, 0.5, 0.5, 0.05), (0.2, 0.5, 0.0, 0.05), (0.2, 0.5, 0.5, 0.05),
                           (0.2, 0.5, 0.0, 0.0)],
    "tennis_forehand": [(0.5, 1.35, -0.55, 0.2), (0.22, 0.25, -0.35, 0.1), (0.25, -1.0, -1.1, 0.0),
                        (0.3, -1.0, -1.1, 0.0), (0.7, 0.3, -0.3, 0.0)],
    "tennis_backhand": [(0.5, -1.1, -0.5, 0.2), (0.22, 0.2, -0.35, 0.1), (0.25, 1.3, -1.0, 0.0),
                        (0.3, 1.3, -1.0, 0.0), (0.7, 0.3, -0.3, 0.0)],
    "tennis_serve": [(0.7, 0.9, -1.3, 0.25), (0.2, 0.35, -2.15, 0.0), (0.3, -0.5, 0.0, 0.0),
                     (0.3, -0.5, 0.0, 0.0), (0.7, 0.3, -0.3, 0.0)],
    "pickleball_dink": [(0.3, 0.75, -0.2, 0.2), (0.18, 0.3, -0.3, 0.2), (0.2, -0.3, -0.75, 0.15),
                        (0.25, -0.3, -0.75, 0.1), (0.4, 0.2, -0.45, 0.0)],
    "stretch": [(1.5, 0.6, -2.0, 0.0), (1.0, 0.6, -2.0, 0.0), (1.5, 0.3, 0.3, 0.0)],
    "scratch_head": [(0.7, 0.2, -1.4, 0.0), (0.8, 0.2, -1.4, 0.0), (0.7, 0.3, 0.3, 0.0)],
}

REST = {"golf": (0.0, 0.35), "basketball": (0.4, 0.2), "tennis": (0.3, -0.3), "pickleball": (0.2, -0.45)}


def _smooth(u: float) -> float:
    return u * u * (3 - 2 * u)


def _ik(sh, wr, bend):
    """Elbow for a two-bone arm; clamps the wrist to arm's reach."""
    dx, dy = wr[0] - sh[0], wr[1] - sh[1]
    d = math.hypot(dx, dy)
    reach = (UPPER + FORE) * 0.999
    if d > reach:
        wr = (sh[0] + dx / d * reach, sh[1] + dy / d * reach)
        dx, dy, d = wr[0] - sh[0], wr[1] - sh[1], reach
    d = max(d, 1e-6)
    a = (UPPER ** 2 - FORE ** 2 + d ** 2) / (2 * d)
    h = math.sqrt(max(UPPER ** 2 - a ** 2, 0.0))
    mx, my = sh[0] + a * dx / d, sh[1] + a * dy / d
    return (mx - bend * h * dy / d, my + bend * h * dx / d), wr


def pose(cx: float, hand_r, hand_l, knee_drop: float, rng, noise: float, conf: float = 0.9):
    """Returns 13 joints [x, y, c] normalised 0..1 for a figure centred at cx (height units)."""
    drop = knee_drop * TORSO
    hip = (cx, 0.56 + drop)
    pts = {
        "nose": (cx, hip[1] - TORSO - 0.075),
        "r_shoulder": (cx - 0.065, hip[1] - TORSO), "l_shoulder": (cx + 0.065, hip[1] - TORSO),
        "r_hip": (cx - 0.04, hip[1]), "l_hip": (cx + 0.04, hip[1]),
        "r_ankle": (cx - 0.06, 0.86), "l_ankle": (cx + 0.06, 0.86),
    }
    for side, sgn in (("r", -1), ("l", 1)):
        hp, an = pts[side + "_hip"], pts[side + "_ankle"]
        d = math.hypot(an[0] - hp[0], an[1] - hp[1])
        h = math.sqrt(max(THIGH ** 2 - (d / 2) ** 2, 0.0))
        pts[side + "_knee"] = ((hp[0] + an[0]) / 2 + sgn * h, (hp[1] + an[1]) / 2)
    for side, hand, bend in (("r", hand_r, 1), ("l", hand_l, -1)):
        # +x torso units is the person's right = image left
        target = (hip[0] - hand[0] * TORSO, hip[1] + hand[1] * TORSO)
        el, wr = _ik(pts[side + "_shoulder"], target, bend)
        pts[side + "_elbow"], pts[side + "_wrist"] = el, wr
    out = []
    for name in JOINTS:
        x, y = pts[name]
        out.append([(x + rng.gauss(0, noise)) / ASPECT, y + rng.gauss(0, noise), conf])
    return out


def recording(sport: str, script: list, fps: float = 30.0, noise: float = 0.0015,
              seed: int = 1, handedness: str = "right") -> dict:
    """script: list of ("rest", seconds) | ("walk", seconds) | (motion_name,) items."""
    rng = random.Random(seed)
    two_hands = sport == "golf"
    rest = REST[sport]
    off_rest = (-0.45, 0.3)
    frames = []
    t = 0.0
    dt = 1.0 / fps
    cx = ASPECT / 2
    hand = rest
    knee = 0.0

    def emit(h, k, x):
        if handedness == "left" and not two_hands:
            h = (-h[0], h[1])
        other = h if two_hands else off_rest
        r, l = (h, other) if handedness == "right" else ((0.45, 0.3), h)
        if two_hands:
            r = l = h
        frames.append({"t": round(t, 4), "j": pose(x, r, l, k, rng, noise)})

    for item in script:
        if item[0] == "rest":
            for _ in range(int(item[1] * fps)):
                emit(hand, knee, cx)
                t += dt
        elif item[0] == "walk":
            n = int(item[1] * fps)
            for i in range(n):
                ph = i / fps
                cx = ASPECT / 2 + 0.12 * math.sin(2 * math.pi * ph / item[1])
                swing = (rest[0] + 0.15 * math.sin(2 * math.pi * ph * 1.8), rest[1])
                emit(swing, 0.03 * abs(math.sin(2 * math.pi * ph * 1.8)), cx)
                t += dt
            cx = ASPECT / 2
        else:
            for dur, x, y, k in MOTIONS[item[0]]:
                n = max(1, int(round(dur * fps)))
                h0, k0 = hand, knee
                for i in range(1, n + 1):
                    u = _smooth(i / n)
                    hand = (h0[0] + (x - h0[0]) * u, h0[1] + (y - h0[1]) * u)
                    knee = k0 + (k - k0) * u
                    emit(hand, knee, cx)
                    t += dt
            hand, knee = rest, 0.0
    return {"sport": sport, "handedness": handedness, "fps": fps, "aspect": ASPECT, "frames": frames}
