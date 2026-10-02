"""Per-sport event detection and form metrics for one validated motion segment.

Each analyzer takes (seg, ctx) where seg is a list of engine.Sample and ctx has .dom/.off
("l"/"r") and .det; it returns (rep_type, events, metrics) or None when the motion does not
have the shape of the sport's movement (the engine then rejects it as "bad_pattern").
"""
from __future__ import annotations

import math


def mid(a, b):
    return ((a[0] + b[0]) / 2.0, (a[1] + b[1]) / 2.0)


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def angle(a, b, c):
    """Interior angle at b in degrees, or None if any point is missing."""
    if a is None or b is None or c is None:
        return None
    v1 = (a[0] - b[0], a[1] - b[1])
    v2 = (c[0] - b[0], c[1] - b[1])
    n = math.hypot(*v1) * math.hypot(*v2)
    if n < 1e-9:
        return None
    cos = max(-1.0, min(1.0, (v1[0] * v2[0] + v1[1] * v2[1]) / n))
    return math.degrees(math.acos(cos))


def median(vals):
    v = sorted(vals)
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2.0


def argmax(vals, lo, hi):
    """Index of the first maximum in vals[lo..hi] inclusive."""
    best = lo
    for i in range(lo, hi + 1):
        if vals[i] > vals[best]:
            best = i
    return best


def argmin(vals, lo, hi):
    best = lo
    for i in range(lo, hi + 1):
        if vals[i] < vals[best]:
            best = i
    return best


def _p(s, name):
    return s.pts.get(name)


def _arm_angle(s, side):
    return angle(_p(s, side + "_shoulder"), _p(s, side + "_elbow"), _p(s, side + "_wrist"))


def _shoulder_width(s):
    return dist(s.pts["l_shoulder"], s.pts["r_shoulder"])


def golf(seg, ctx):
    n = len(seg)
    ry = [s.ry for s in seg]
    sp = [s.speed for s in seg]
    # Impact is the deepest valley in hand height: hands low, flanked by hands high at the top
    # of the backswing before it and in the follow-through after it.
    pre = [0.0] * n
    suf = [0.0] * n
    for i in range(1, n):
        pre[i] = ry[i - 1] if i == 1 else min(pre[i - 1], ry[i - 1])
    for i in range(n - 2, -1, -1):
        suf[i] = ry[i + 1] if i == n - 2 else min(suf[i + 1], ry[i + 1])
    if n < 5:
        return None
    depth = [0.0] + [ry[i] - max(pre[i], suf[i]) for i in range(1, n - 1)] + [0.0]
    impact = argmax(depth, 1, n - 2)
    if depth[impact] < 0.6:
        return None
    lo = impact
    while lo > 0 and seg[impact].t - seg[lo - 1].t <= 1.0:
        lo -= 1
    hi = impact
    while hi < n - 1 and seg[hi + 1].t - seg[impact].t <= 1.5:
        hi += 1
    top = argmin(ry, lo, impact)
    fin = argmin(ry, impact, hi)
    if sp[argmax(sp, top, fin)] < ctx.gates["min_peak_speed"]:
        return None
    # Takeaway: the last moment before the top that the hands were still at their address
    # position. Address is the median position of the stillest low-hand samples, which ignores
    # waggles and tracking jitter better than a speed threshold does.
    lo = top
    while lo > 0 and seg[top].t - seg[lo - 1].t <= 2.5:
        lo -= 1
    low = [i for i in range(lo, top) if ry[i] - ry[top] >= 0.6]
    if not low:
        return None
    low.sort(key=lambda i: (sp[i], i))
    still = low[:max(3, len(low) // 3)]
    ax = median([seg[i].rx for i in still])
    ay = median([seg[i].ry for i in still])
    start = lo
    for i in range(top - 1, lo - 1, -1):
        if math.hypot(seg[i].rx - ax, seg[i].ry - ay) < 0.15:
            start = i
            break
    back = seg[top].t - seg[start].t
    down = seg[impact].t - seg[top].t
    if back < 0.2 or down < 0.08:
        return None

    a, tp, im, fi = seg[start], seg[top], seg[impact], seg[fin]
    # The backswing goes toward the trail side, so its direction tells us the lead arm. This holds
    # for a mirrored image too, because mirroring flips both the direction and the pose labels.
    lead = "l" if tp.rx < a.rx else "r"
    m = {"tempo_ratio": back / down, "lead_arm_top": _arm_angle(tp, lead)}
    nose0 = _p(a, "nose")
    if nose0 is not None:
        sway = 0.0
        for i in range(start, impact + 1):
            nz = _p(seg[i], "nose")
            if nz is not None:
                sway = max(sway, abs(nz[0] - nose0[0]) / seg[i].torso)
        m["head_sway"] = sway
        nz = _p(im, "nose")
        m["head_lift"] = (nz[1] - nose0[1]) / im.torso if nz is not None else None
    m["hip_sway"] = abs(tp.hip[0] - a.hip[0]) / tp.torso
    m["shoulder_turn"] = _shoulder_width(tp) / max(_shoulder_width(a), 1e-6)
    ankle = _p(fi, lead + "_ankle")
    m["finish_balance"] = abs(fi.hip[0] - ankle[0]) / fi.torso if ankle is not None else None
    ev = {"address": a.t, "top": tp.t, "impact": im.t, "finish": fi.t}
    return "swing", ev, m


def basketball(seg, ctx):
    n = len(seg)
    d = ctx.dom
    ry = [s.ry for s in seg]
    apex = argmin(ry, 0, n - 1)
    ea = [_arm_angle(s, d) for s in seg]
    best = None
    for i in range(0, apex + 1):
        if ea[i] is not None and (best is None or ea[i] > best):
            best = ea[i]
    if best is None:
        return None
    release = apex
    for i in range(0, apex + 1):
        sh = _p(seg[i], d + "_shoulder")
        if ea[i] is not None and ea[i] >= best - 5.0 and seg[i].pts[d + "_wrist"][1] < sh[1]:
            release = i
            break
    set_i = 0
    for i in range(release, -1, -1):
        if seg[i].pts[d + "_wrist"][1] >= _p(seg[i], d + "_shoulder")[1]:
            set_i = min(i + 1, release)
            break
    if release < 1:
        return None
    # A shot loads the elbow and then snaps it straight; simply raising an arm does neither.
    load = None
    snap = 0.0
    for i in range(0, release + 1):
        if ea[i] is None:
            continue
        if load is None or ea[i] < load:
            load = ea[i]
        for k in range(i - 1, -1, -1):
            if seg[i].t - seg[k].t >= 0.1:
                if ea[k] is not None:
                    snap = max(snap, (ea[i] - ea[k]) / (seg[i].t - seg[k].t))
                break
    pat = ctx.profile.get("pattern", {})
    if load > pat.get("max_load_elbow", 180.0) or snap < pat.get("min_extension_speed", 0.0):
        return None

    # Face-on, the knees bend toward the camera, so knee flexion is invisible in 2D. The hips
    # dropping and then rising is what the camera can see.
    hy = [x.hip[1] for x in seg]
    dip = argmax(hy, 0, release)

    rel, st = seg[release], seg[set_i]
    sh = _p(rel, d + "_shoulder")
    wr = rel.pts[d + "_wrist"]
    m = {
        "leg_drive": (hy[dip] - hy[release]) / seg[release].torso,
        "elbow_extension": ea[release],
        "release_height": (sh[1] - wr[1]) / rel.torso,
        "arm_verticality": math.degrees(math.atan2(abs(wr[0] - sh[0]), max(sh[1] - wr[1], 1e-6))),
        "lateral_drift": abs(seg[-1].hip[0] - seg[0].hip[0]) / seg[-1].torso,
        "shot_rhythm": rel.t - seg[dip].t,
        "elbow_load": load,
        "extension_speed": snap,
    }
    el = _p(st, d + "_elbow")
    m["elbow_flare"] = (abs(el[0] - _p(st, d + "_shoulder")[0]) / max(_shoulder_width(seg[0]), 1e-6)
                        if el is not None else None)
    hold_end = release
    for i in range(release, n):
        s = seg[i]
        nose = _p(s, "nose")
        head_y = nose[1] if nose is not None else _p(s, d + "_shoulder")[1] - 0.3 * s.torso
        if s.pts[d + "_wrist"][1] < head_y:
            hold_end = i
        else:
            break
    m["follow_through_hold"] = seg[hold_end].t - rel.t
    ev = {"dip": seg[dip].t, "set": st.t, "release": rel.t}
    return "shot", ev, m


def racket(seg, ctx):
    n = len(seg)
    d = ctx.dom
    sp = [s.speed for s in seg]
    ry = [s.ry for s in seg]
    side = 1.0 if ctx.facing >= 0 else -1.0
    lat = [s.rx * side for s in seg]     # positive = wrist on the dominant side of the body
    pat = ctx.profile["pattern"]
    apex = argmin(ry, 0, n - 1)
    fastest = argmax(sp, 0, n - 1)
    if ry[apex] <= -1.7 and seg[apex].t - seg[fastest].t <= 0.2:
        # Serve or smash: the hand is fastest at or after full reach, and comes back down through
        # the ball. A groundstroke that finishes high was fastest well before it got up there.
        contact = apex
        if contact < 1 or max(ry[apex:]) - ry[apex] < pat["min_overhead_drop"]:
            return None
        far = [math.hypot(s.rx - seg[contact].rx, s.ry - seg[contact].ry) for s in seg]
        back = argmax(far, 0, contact)
        thru = argmax([abs(v - lat[back]) for v in lat], contact, n - 1)
        rep_type = "serve" if ctx.sport == "tennis" else "overhead"
    else:
        # Groundstroke: the forward swing is the widest sweep of the hand across the body. The
        # take-back is always a shorter sweep, so this finds the swing even when the take-back
        # is the faster movement (slow or shadow swings).
        back, thru, sweep = 0, 0, 0.0
        lo, hi = 0, 0
        for j in range(1, n):
            if lat[j - 1] < lat[lo]:
                lo = j - 1
            if lat[j - 1] > lat[hi]:
                hi = j - 1
            if lat[j] - lat[lo] > sweep:
                back, thru, sweep = lo, j, lat[j] - lat[lo]
            if lat[hi] - lat[j] > sweep:
                back, thru, sweep = hi, j, lat[hi] - lat[j]
        if sweep < pat["min_sweep"]:
            return None
        # A real stroke carries the hand across the body's midline; taking the racket back from
        # the ready position sweeps to one side only.
        if min(lat[back], lat[thru]) > -pat["min_cross"] or max(lat[back], lat[thru]) < pat["min_cross"]:
            return None
        contact = argmax(sp, back, thru)
        if contact <= back:
            contact = back + 1
        rep_type = "forehand" if lat[back] > lat[thru] else "backhand"
    c = seg[contact]
    reach = abs(lat[thru] - lat[back])

    b = seg[back]
    stance = None
    for i in range(0, contact + 1):
        la, ra = _p(seg[i], "l_ankle"), _p(seg[i], "r_ankle")
        if la is not None and ra is not None:
            h = ((la[1] + ra[1]) / 2.0 - seg[i].hip[1]) / seg[i].torso
            if stance is None or h < stance:
                stance = h
    w0 = max(_shoulder_width(seg[0]), 1e-6)
    turn = min(_shoulder_width(seg[i]) for i in range(0, contact + 1)) / w0
    m = {
        "stance_height": stance,
        "contact_arm": _arm_angle(c, d),
        "contact_height": c.ry,
        "swing_through": reach,
        "shoulder_turn": turn,
        "swing_tempo": c.t - b.t,
        "backswing_size": math.hypot(b.rx, b.ry + 0.5),
        "ready_height": seg[0].ry,
    }
    nose0 = _p(b, "nose")
    if nose0 is not None:
        move = 0.0
        for i in range(back, contact + 1):
            nz = _p(seg[i], "nose")
            if nz is not None:
                move = max(move, dist(nz, nose0) / seg[i].torso)
        m["head_stability"] = move
    ev = {"backswing": b.t, "contact": c.t, "finish": seg[thru].t}
    return rep_type, ev, m


ANALYZERS = {"golf": golf, "basketball": basketball, "racket": racket}
