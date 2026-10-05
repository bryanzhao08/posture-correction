import Foundation

// Port of ml/formcoach/sports.py. Keep the two in step; `swift run formcore-check` verifies it.

struct Analysis {
    let type: String
    let events: [String: Double]
    let metrics: [String: Double]
}

func mid(_ a: Point, _ b: Point) -> Point {
    Point(x: (a.x + b.x) / 2.0, y: (a.y + b.y) / 2.0)
}

func dist(_ a: Point, _ b: Point) -> Double {
    hypot(a.x - b.x, a.y - b.y)
}

func angle(_ a: Point?, _ b: Point?, _ c: Point?) -> Double? {
    guard let a = a, let b = b, let c = c else { return nil }
    let v1 = Point(x: a.x - b.x, y: a.y - b.y)
    let v2 = Point(x: c.x - b.x, y: c.y - b.y)
    let n = hypot(v1.x, v1.y) * hypot(v2.x, v2.y)
    if n < 1e-9 { return nil }
    let cosv = max(-1.0, min(1.0, (v1.x * v2.x + v1.y * v2.y) / n))
    return acos(cosv) * (180.0 / Double.pi)
}

func median(_ vals: [Double]) -> Double {
    let v = vals.sorted()
    let n = v.count
    return n % 2 == 1 ? v[n / 2] : (v[n / 2 - 1] + v[n / 2]) / 2.0
}

/// Index of the first maximum in vals[lo...hi].
func argmax(_ vals: [Double], _ lo: Int, _ hi: Int) -> Int {
    var best = lo
    if hi >= lo {
        for i in lo...hi where vals[i] > vals[best] { best = i }
    }
    return best
}

func argmin(_ vals: [Double], _ lo: Int, _ hi: Int) -> Int {
    var best = lo
    if hi >= lo {
        for i in lo...hi where vals[i] < vals[best] { best = i }
    }
    return best
}

private func armAngle(_ s: Sample, _ side: String) -> Double? {
    angle(s.pts[side + "_shoulder"], s.pts[side + "_elbow"], s.pts[side + "_wrist"])
}

private func shoulderWidth(_ s: Sample) -> Double {
    dist(s.pts["l_shoulder"]!, s.pts["r_shoulder"]!)
}

private func degrees(_ x: Double) -> Double { x * (180.0 / Double.pi) }

func analyzeGolf(_ seg: [Sample], _ ctx: FormEngine) -> Analysis? {
    let n = seg.count
    if n < 5 { return nil }
    let ry = seg.map { $0.ry }
    let sp = seg.map { $0.speed }
    // Impact is the deepest valley in hand height: hands low, flanked by hands high at the top
    // of the backswing before it and in the follow-through after it.
    var pre = [Double](repeating: 0, count: n)
    var suf = [Double](repeating: 0, count: n)
    for i in 1..<n { pre[i] = i == 1 ? ry[0] : min(pre[i - 1], ry[i - 1]) }
    for i in stride(from: n - 2, through: 0, by: -1) { suf[i] = i == n - 2 ? ry[n - 1] : min(suf[i + 1], ry[i + 1]) }
    var depth = [Double](repeating: 0, count: n)
    for i in 1..<(n - 1) { depth[i] = ry[i] - max(pre[i], suf[i]) }
    let impact = argmax(depth, 1, n - 2)
    if depth[impact] < (ctx.profile.pattern?["min_valley"] ?? 0.6) { return nil }
    var lo = impact
    while lo > 0 && seg[impact].t - seg[lo - 1].t <= 1.0 { lo -= 1 }
    var hi = impact
    while hi < n - 1 && seg[hi + 1].t - seg[impact].t <= 1.5 { hi += 1 }
    let top = argmin(ry, lo, impact)
    let fin = argmin(ry, impact, hi)
    if sp[argmax(sp, top, fin)] < ctx.profile.gates.minPeakSpeed { return nil }
    // Takeaway: the last moment before the top that the hands were still at their address
    // position (median position of the stillest low-hand samples).
    lo = top
    while lo > 0 && seg[top].t - seg[lo - 1].t <= 2.5 { lo -= 1 }
    var low: [Int] = []
    for i in lo..<max(top, lo) where ry[i] - ry[top] >= 0.6 { low.append(i) }
    if low.isEmpty { return nil }
    low.sort { sp[$0] != sp[$1] ? sp[$0] < sp[$1] : $0 < $1 }
    let still = Array(low.prefix(max(3, low.count / 3)))
    let ax = median(still.map { seg[$0].rx })
    let ay = median(still.map { seg[$0].ry })
    var start = lo
    for i in stride(from: top - 1, through: lo, by: -1) where hypot(seg[i].rx - ax, seg[i].ry - ay) < 0.15 {
        start = i
        break
    }
    let back = seg[top].t - seg[start].t
    let down = seg[impact].t - seg[top].t
    if back < 0.2 || down < 0.06 { return nil }

    let a = seg[start], tp = seg[top], im = seg[impact], fi = seg[fin]
    // The backswing goes toward the trail side, so its direction tells us the lead arm. This holds
    // for a mirrored image too, because mirroring flips both the direction and the pose labels.
    let lead = tp.rx < a.rx ? "l" : "r"
    var m: [String: Double] = ["tempo_ratio": back / down]
    m["lead_arm_top"] = armAngle(tp, lead)
    if let nose0 = a.pts["nose"] {
        var sway = 0.0
        for i in start...impact {
            if let nz = seg[i].pts["nose"] { sway = max(sway, abs(nz.x - nose0.x) / seg[i].torso) }
        }
        m["head_sway"] = sway
        if let nz = im.pts["nose"] { m["head_lift"] = (nz.y - nose0.y) / im.torso }
    }
    m["hip_sway"] = abs(tp.hip.x - a.hip.x) / tp.torso
    m["shoulder_turn"] = shoulderWidth(tp) / max(shoulderWidth(a), 1e-6)
    if let ankle = fi.pts[lead + "_ankle"] { m["finish_balance"] = abs(fi.hip.x - ankle.x) / fi.torso }
    let ev = ["address": a.t, "top": tp.t, "impact": im.t, "finish": fi.t]
    return Analysis(type: "swing", events: ev, metrics: m)
}

func analyzeBasketball(_ seg: [Sample], _ ctx: FormEngine) -> Analysis? {
    let n = seg.count
    let d = ctx.dom
    let ry = seg.map { $0.ry }
    let apex = argmin(ry, 0, n - 1)
    let ea = seg.map { armAngle($0, d) }
    var best: Double? = nil
    for i in 0...apex { if let e = ea[i], best == nil || e > best! { best = e } }
    guard let bestAngle = best else { return nil }
    var release = apex
    for i in 0...apex {
        if let e = ea[i], e >= bestAngle - 5.0, seg[i].pts[d + "_wrist"]!.y < seg[i].pts[d + "_shoulder"]!.y {
            release = i
            break
        }
    }
    var setI = 0
    for i in stride(from: release, through: 0, by: -1) where seg[i].pts[d + "_wrist"]!.y >= seg[i].pts[d + "_shoulder"]!.y {
        setI = min(i + 1, release)
        break
    }
    if release < 1 { return nil }
    // A shot loads the elbow and then snaps it straight; simply raising an arm does neither.
    var load: Double? = nil
    var snap = 0.0
    for i in 0...release {
        guard let e = ea[i] else { continue }
        if load == nil || e < load! { load = e }
        var k = i - 1
        while k >= 0 {
            if seg[i].t - seg[k].t >= 0.1 {
                if let ek = ea[k] { snap = max(snap, (e - ek) / (seg[i].t - seg[k].t)) }
                break
            }
            k -= 1
        }
    }
    let pat = ctx.profile.pattern ?? [:]
    if load! > (pat["max_load_elbow"] ?? 180.0) || snap < (pat["min_extension_speed"] ?? 0.0) { return nil }
    // ...and finishes with the arm close to straight; reaching up to stretch or scratch does not.
    guard let releaseElbow = ea[release], releaseElbow >= (pat["min_release_elbow"] ?? 0.0) else { return nil }

    // Face-on, the knees bend toward the camera, so knee flexion is invisible in 2D. The hips
    // dropping and then rising is what the camera can see.
    let hy = seg.map { $0.hip.y }
    let dip = argmax(hy, 0, release)
    let rel = seg[release], st = seg[setI]
    let sh = rel.pts[d + "_shoulder"]!
    let wr = rel.pts[d + "_wrist"]!
    var m: [String: Double] = [
        "leg_drive": (hy[dip] - hy[release]) / seg[release].torso,
        "release_height": (sh.y - wr.y) / rel.torso,
        "arm_verticality": degrees(atan2(abs(wr.x - sh.x), max(sh.y - wr.y, 1e-6))),
        "lateral_drift": abs(seg[n - 1].hip.x - seg[0].hip.x) / seg[n - 1].torso,
        "shot_rhythm": rel.t - seg[dip].t,
        "elbow_load": load!,
        "extension_speed": snap,
    ]
    m["elbow_extension"] = ea[release]
    if let el = st.pts[d + "_elbow"] {
        m["elbow_flare"] = abs(el.x - st.pts[d + "_shoulder"]!.x) / max(shoulderWidth(seg[0]), 1e-6)
    }
    var holdEnd = release
    for i in release..<n {
        let s = seg[i]
        let headY = s.pts["nose"]?.y ?? (s.pts[d + "_shoulder"]!.y - 0.3 * s.torso)
        if s.pts[d + "_wrist"]!.y < headY { holdEnd = i } else { break }
    }
    m["follow_through_hold"] = seg[holdEnd].t - rel.t
    if let gw = rel.pts[ctx.off + "_wrist"] {
        let gap = dist(gw, wr) / rel.torso
        m["guide_hand_gap"] = gap
        // Both arms locked straight overhead with the hands wide apart is a barbell press or a
        // pull-up, not a shot: a shooter's hands are never more than about 0.7 torso apart.
        if gap > (pat["max_hand_gap"] ?? 99.0), let offEl = armAngle(rel, ctx.off), offEl >= 150.0,
           (rel.pts[ctx.off + "_shoulder"]!.y - gw.y) / rel.torso >= 0.6 { return nil }
    }
    let ev = ["dip": seg[dip].t, "set": st.t, "release": rel.t]
    return Analysis(type: "shot", events: ev, metrics: m)
}

func analyzeRacket(_ seg: [Sample], _ ctx: FormEngine) -> Analysis? {
    let n = seg.count
    let d = ctx.dom
    let sp = seg.map { $0.speed }
    let ry = seg.map { $0.ry }
    let side = ctx.facing >= 0 ? 1.0 : -1.0
    let lat = seg.map { $0.rx * side }      // positive = wrist on the dominant side of the body
    let pat = ctx.profile.pattern ?? [:]
    let apex = argmin(ry, 0, n - 1)
    let fastest = argmax(sp, 0, n - 1)
    var contact: Int
    var back: Int
    var thru: Int
    let repType: String
    if ry[apex] <= -1.7 && seg[apex].t - seg[fastest].t <= 0.2 {
        // Serve or smash: the hand is fastest at or after full reach, and comes back down through
        // the ball. A groundstroke that finishes high was fastest well before it got up there.
        contact = apex
        if contact < 1 || ry[apex...].max()! - ry[apex] < (pat["min_overhead_drop"] ?? 0) { return nil }
        let far = seg.map { hypot($0.rx - seg[contact].rx, $0.ry - seg[contact].ry) }
        back = argmax(far, 0, contact)
        thru = argmax(lat.map { abs($0 - lat[back]) }, contact, n - 1)
        repType = ctx.sport == "tennis" ? "serve" : "overhead"
    } else {
        // Groundstroke: the forward swing is the widest sweep of the hand across the body.
        back = 0
        thru = 0
        var sweep = 0.0
        var lo = 0, hi = 0
        for j in 1..<max(n, 1) {
            if lat[j - 1] < lat[lo] { lo = j - 1 }
            if lat[j - 1] > lat[hi] { hi = j - 1 }
            if lat[j] - lat[lo] > sweep {
                back = lo; thru = j; sweep = lat[j] - lat[lo]
            }
            if lat[hi] - lat[j] > sweep {
                back = hi; thru = j; sweep = lat[hi] - lat[j]
            }
        }
        if sweep < (pat["min_sweep"] ?? 0) { return nil }
        // A real stroke carries the hand across the body's midline.
        let cross = pat["min_cross"] ?? 0
        if min(lat[back], lat[thru]) > -cross || max(lat[back], lat[thru]) < cross { return nil }
        contact = argmax(sp, back, thru)
        if contact <= back { contact = back + 1 }
        repType = ctx.view == "side" ? (ctx.focus == "backhand" ? "backhand" : "forehand") : (lat[back] > lat[thru] ? "forehand" : "backhand")
    }
    let c = seg[contact]
    let reach = abs(lat[thru] - lat[back])
    // Jumping jacks move both hands as mirror images and take both above the head; a stroke never does both.
    let o = ctx.off
    var dot = 0.0, nd = 0.0, no = 0.0
    var bothUp = false
    if thru >= max(back, 1) {
        for i in max(back, 1)...thru {
            guard let a0 = seg[i - 1].pts[d + "_wrist"], let a1 = seg[i].pts[d + "_wrist"],
                  let b0 = seg[i - 1].pts[o + "_wrist"], let b1 = seg[i].pts[o + "_wrist"] else { continue }
            let dx = a1.x - a0.x, dy = a1.y - a0.y
            let mx = -(b1.x - b0.x), my = b1.y - b0.y
            dot += dx * mx + dy * my
            nd += dx * dx + dy * dy
            no += mx * mx + my * my
            let hip = seg[i].hip
            if (a1.y - hip.y) / seg[i].torso < -1.3 && (b1.y - hip.y) / seg[i].torso < -1.3 { bothUp = true }
        }
    }
    if bothUp && nd > 0 && no > 0 && dot / (nd * no).squareRoot() > (pat["max_mirror"] ?? 2.0) { return nil }
    let b = seg[back]
    var stance: Double? = nil
    for i in 0...contact {
        if let la = seg[i].pts["l_ankle"], let ra = seg[i].pts["r_ankle"] {
            let h = ((la.y + ra.y) / 2.0 - seg[i].hip.y) / seg[i].torso
            if stance == nil || h < stance! { stance = h }
        }
    }
    let w0 = max(shoulderWidth(seg[0]), 1e-6)
    var turnMin = shoulderWidth(seg[0])
    for i in 0...contact { turnMin = min(turnMin, shoulderWidth(seg[i])) }
    var m: [String: Double] = [
        "contact_height": c.ry,
        "swing_through": reach,
        "shoulder_turn": turnMin / w0,
        "swing_tempo": c.t - b.t,
        "backswing_size": hypot(b.rx, b.ry + 0.5),
        "ready_height": seg[0].ry,
    ]
    m["stance_height"] = stance
    m["contact_arm"] = armAngle(c, d)
    if let nose0 = b.pts["nose"] {
        var move = 0.0
        for i in back...contact {
            if let nz = seg[i].pts["nose"] { move = max(move, dist(nz, nose0) / seg[i].torso) }
        }
        m["head_stability"] = move
    }
    let fh = argmin(ry, contact, n - 1)
    let f = seg[fh]
    m["finish_height"] = (f.pts[o + "_shoulder"]!.y - f.pts[d + "_wrist"]!.y) / f.torso
    if let el = f.pts[d + "_elbow"], let nz = f.pts["nose"] { m["elbow_finish"] = (nz.y - el.y) / f.torso }
    var offReach: Double?
    for i in 0...contact {
        if let ow = seg[i].pts[o + "_wrist"], let osh = seg[i].pts[o + "_shoulder"] {
            let r = dist(ow, osh) / seg[i].torso
            offReach = max(offReach ?? r, r)
        }
    }
    m["off_hand_reach"] = offReach
    m["spacing"] = abs(c.rx)
    let fwd = c.rx >= b.rx ? 1.0 : -1.0
    m["contact_front"] = c.rx * fwd
    if let la = c.pts["l_ankle"], let ra = c.pts["r_ankle"] {
        m["contact_front"] = (c.pts[d + "_wrist"]!.x * fwd - max(la.x * fwd, ra.x * fwd)) / c.torso
    }
    m["extension_through"] = seg[contact...].map { $0.rx * fwd }.max()! - c.rx * fwd
    if let la = b.pts["l_ankle"], let ra = b.pts["r_ankle"], abs(la.x - ra.x) / b.torso >= 0.3 {
        let backX = la.x * fwd <= ra.x * fwd ? la.x : ra.x
        let frontX = la.x * fwd <= ra.x * fwd ? ra.x : la.x
        let width = (frontX - backX) * fwd
        m["back_load"] = (b.hip.x - backX) * fwd / width
        m["weight_shift"] = (c.hip.x - b.hip.x) * fwd / width
    }
    let ev = ["backswing": b.t, "contact": c.t, "finish": seg[thru].t, "follow_through": f.t]
    return Analysis(type: repType, events: ev, metrics: m)
}
