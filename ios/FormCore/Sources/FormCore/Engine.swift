import Foundation

// Port of ml/formcoach/engine.py. Keep the two in step; `swift run formcore-check` verifies it.

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

struct Sample {
    let t: Double
    let pts: [String: Point]
    let torso: Double
    let hip: Point
    let rx: Double
    let ry: Double
    let speed: Double
}

struct SegmentStats {
    let duration, peakSpeed, pathLen, extent, verticalRange, horizontalRange, startY, minY: Double
}

func emaAlpha(_ dt: Double, _ tau: Double) -> Double {
    tau > 0 ? 1.0 - exp(-dt / tau) : 1.0
}

func segmentStats(_ seg: [Sample]) -> SegmentStats {
    var path = 0.0
    var extent = 0.0
    var minX = seg[0].rx, maxX = seg[0].rx, minY = seg[0].ry, maxY = seg[0].ry
    var peak = seg[0].speed
    for i in 1..<max(seg.count, 1) {
        path += hypot(seg[i].rx - seg[i - 1].rx, seg[i].ry - seg[i - 1].ry)
        extent = max(extent, hypot(seg[i].rx - seg[0].rx, seg[i].ry - seg[0].ry))
        minX = min(minX, seg[i].rx)
        maxX = max(maxX, seg[i].rx)
        minY = min(minY, seg[i].ry)
        maxY = max(maxY, seg[i].ry)
        peak = max(peak, seg[i].speed)
    }
    return SegmentStats(duration: seg[seg.count - 1].t - seg[0].t, peakSpeed: peak, pathLen: path,
                        extent: extent, verticalRange: maxY - minY, horizontalRange: maxX - minX,
                        startY: seg[0].ry, minY: minY)
}

func gateFailure(_ st: SegmentStats, _ g: Gates) -> String {
    if st.duration < g.minDurationS { return "too_short" }
    if st.duration > g.maxDurationS { return "too_long" }
    if st.peakSpeed < g.minPeakSpeed { return "too_slow" }
    if st.pathLen < g.minPathLen { return "too_small" }
    if st.verticalRange < g.minVerticalRange { return "too_small" }
    if st.horizontalRange < g.minHorizontalRange { return "too_small" }
    if let v = g.minExtent, st.extent < v { return "too_small" }
    if let v = g.minPathRatio, st.pathLen < v * st.extent { return "one_way" }
    if let v = g.startHandMinY, st.startY < v { return "bad_start" }
    if let v = g.peakHandMaxY, st.minY > v { return "not_high_enough" }
    return ""
}

/// Streaming state machine: push one pose frame at a time, get back counted reps.
///
/// A motion is counted only when it is fast enough to trigger, passes every gate in the sport
/// profile, and has the shape of the sport's movement. Everything else is reported as a
/// rejected motion, never as a rep.
public final class FormEngine {
    public private(set) var state: EngineState = .noPerson
    public private(set) var reps: [Rep] = []
    public private(set) var rejected: [String: Int] = [:]
    public private(set) var activeSeconds = 0.0
    public private(set) var passiveSeconds = 0.0

    let sport: String
    public let view: String
    public let focus: String?
    let profile: SportProfile
    let dom: String
    let off: String
    private let cfg: Preprocess
    private let scoring: ScoringConfig
    private let joints: [String]
    private var det: Detect { profile.detect }
    private var gates: Gates { profile.gates }

    private var buf: [Sample] = []
    private var sm: [String: (x: Double, y: Double, t: Double)] = [:]
    private var torso: Double?
    private var prevRel: Point?
    private var prevT: Double?
    private var speed = 0.0
    private var lastVisibleT: Double?
    private var quietSince: Double?
    private var lastRestT: Double?
    private var armed = false
    private var fastSince: Double?
    private var belowSince: Double?
    private var segStartT = 0.0
    private var cooldownUntil = -1.0
    private var lastSegEndT = -1.0
    private var dips: [Double] = []
    private var inDip = false
    private var visibleSince: Double?
    private var peakV = 0.0
    private var peakT = 0.0
    /// Slow average of (dominant shoulder x - other shoulder x) / torso: which image side the
    /// dominant shoulder is on while the player faces the camera.
    private(set) var facing = 0.0

    public init(profiles: Profiles, sport: String, handedness: Handedness, view: String? = nil, focus: String? = nil) {
        guard let profile = profiles.sports[sport] else {
            preconditionFailure("unknown sport \(sport)")
        }
        self.sport = sport
        self.view = (view?.isEmpty == false ? view : nil) ?? profile.defaultView ?? "front"
        self.focus = focus
        self.profile = profile.effective(for: self.view)
        cfg = profiles.preprocess
        scoring = profiles.scoring
        joints = profiles.joints
        dom = handedness == .right ? "r" : "l"
        off = handedness == .right ? "l" : "r"
    }

    public func summary() -> SessionSummary {
        summarize(sport: sport, reps: reps, rejected: rejected, specs: profile.metrics, scoring: scoring,
                  activeS: activeSeconds, passiveS: passiveSeconds)
    }

    // MARK: preprocessing

    private func smooth(_ t: Double, _ obs: [JointObservation?], _ aspect: Double) -> [String: Point] {
        let dt = prevT.map { t - $0 } ?? 0.0
        let a = dt > 0 ? emaAlpha(dt, cfg.jointTauS) : 1.0
        var pts: [String: Point] = [:]
        for (i, name) in joints.enumerated() where i < obs.count {
            let prev = sm[name]
            if let j = obs[i], j.confidence >= cfg.minConf {
                var x = j.x * aspect
                var y = j.y
                if let p = prev, t - p.t <= cfg.holdS {
                    x = p.x + a * (x - p.x)
                    y = p.y + a * (y - p.y)
                }
                sm[name] = (x, y, t)
                pts[name] = Point(x: x, y: y)
            } else if let p = prev, t - p.t <= cfg.holdS {
                pts[name] = Point(x: p.x, y: p.y)
            }
        }
        return pts
    }

    private func hand(_ pts: [String: Point]) -> Point? {
        if profile.tracker == "hands_mid" {
            let ws = ["l_wrist", "r_wrist"].compactMap { pts[$0] }
            if ws.isEmpty { return nil }
            let n = Double(ws.count)
            return Point(x: ws.reduce(0) { $0 + $1.x } / n, y: ws.reduce(0) { $0 + $1.y } / n)
        }
        return pts[dom + "_wrist"]
    }

    private func sample(_ t: Double, _ obs: [JointObservation?], _ aspect: Double) -> Sample? {
        let pts = smooth(t, obs, aspect)
        guard let ls = pts["l_shoulder"], let rs = pts["r_shoulder"], let lh = pts["l_hip"],
              let rh = pts["r_hip"], let hand = hand(pts) else { return nil }
        let sh = mid(ls, rs)
        let hip = mid(lh, rh)
        let torsoNow = dist(sh, hip)
        if torsoNow < 0.02 { return nil }
        let dt = prevT.map { t - $0 } ?? 0.0
        var tor = torso ?? torsoNow
        if torso != nil, dt > 0 {
            tor += emaAlpha(dt, cfg.torsoTauS) * (torsoNow - tor)
        }
        torso = tor
        let rel = Point(x: (hand.x - hip.x) / tor, y: (hand.y - hip.y) / tor)
        // Averaged slowly so that turning side-on during a stroke does not flip it.
        if let ds = pts[dom + "_shoulder"], let os = pts[off + "_shoulder"] {
            let across = (ds.x - os.x) / tor
            facing += (dt > 0 ? emaAlpha(dt, cfg.facingTauS) : 1.0) * (across - facing)
        }
        if let p = prevRel, dt > 0 {
            let raw = dist(rel, p) / dt
            speed += emaAlpha(dt, cfg.speedTauS) * (raw - speed)
        } else {
            speed = 0.0
        }
        prevRel = rel
        return Sample(t: t, pts: pts, torso: tor, hip: hip, rx: rel.x, ry: rel.y, speed: speed)
    }

    // MARK: state machine

    /// Call once per camera frame from a single serial queue. `joints` follows `Profiles.joints`
    /// order with normalised top-left-origin coordinates; `aspect` is frame width / height.
    public func push(t: Double, joints obs: [JointObservation?], aspect: Double) -> [EngineEvent] {
        var events: [EngineEvent] = []
        let dt = prevT.map { t - $0 } ?? 0.0
        let sampled = sample(t, obs, aspect)
        prevT = t

        guard let s = sampled else {
            prevRel = nil
            visibleSince = nil
            let lostFor = lastVisibleT.map { t - $0 } ?? 1e9
            if lostFor >= cfg.noPersonS && state != .noPerson {
                if state == .active { events.append(reject("lost_tracking")) }
                resetMotion()
                state = .noPerson
            }
            return events
        }

        lastVisibleT = t
        buf.append(s)
        let horizon = det.maxLookbackS + gates.maxDurationS + 2.0
        while let first = buf.first, t - first.t > horizon { buf.removeFirst() }

        if state == .noPerson { state = .moving }
        if visibleSince == nil { visibleSince = t }
        // Normally stillness arms the counter; someone who never stands quite still is armed after
        // being in view for a while, and the gates and pattern checks do the filtering.
        if let v = visibleSince, t - v >= cfg.armAfterS { armed = true }

        if s.speed < det.restSpeed {
            if quietSince == nil { quietSince = t }
            if let q = quietSince, t - q >= det.restMs / 1000.0 {
                lastRestT = t
                armed = true
            }
        } else {
            quietSince = nil
        }

        if state == .active {
            activeSeconds += dt
            if s.speed < det.exitSpeed {
                if belowSince == nil { belowSince = t }
                if let b = belowSince, t - b >= det.settleMs / 1000.0 { events.append(finalize(t)) }
            } else {
                belowSince = nil
            }
            if s.speed > peakV {
                peakV = s.speed
                peakT = t
            }
            // People often keep moving after the swing (recoil, walking off). Once a fast enough
            // phase is post_peak_s behind us, judge the motion without waiting for stillness.
            if state == .active && peakV >= gates.minPeakSpeed && t - peakT >= det.postPeakS {
                events.append(finalize(t))
            }
            if s.speed < det.restSpeed {
                if !inDip { dips.append(t) }
                inDip = true
            } else {
                inDip = false
            }
            if state == .active && t - segStartT > gates.maxDurationS {
                // Fidgeting (waggles, bouncing the ball) can run straight into the real motion.
                // Drop the oldest movement up to the next momentary pause rather than the lot.
                let later = dips.filter { $0 > segStartT }
                if let first = later.first {
                    segStartT = first
                    dips = Array(later.dropFirst())
                    peakV = 0.0
                    peakT = t
                    for x in buf where x.t >= segStartT && x.speed > peakV {
                        peakV = x.speed
                        peakT = x.t
                    }
                } else {
                    events.append(reject("too_long"))
                    armed = false
                    visibleSince = t
                    endSegment(t)
                }
            }
        } else {
            passiveSeconds += dt
            if s.speed >= det.enterSpeed {
                if fastSince == nil { fastSince = t }
                let longEnough = t - (fastSince ?? t) >= det.enterMs / 1000.0
                if longEnough && armed && t >= cooldownUntil {
                    var start = t - det.maxLookbackS
                    if let r = lastRestT, t - r <= det.maxLookbackS {
                        start = r - det.restMs / 1000.0
                    }
                    segStartT = max(start, lastSegEndT)
                    belowSince = nil
                    dips = []
                    inDip = false
                    peakV = s.speed
                    peakT = t
                    state = .active
                }
            } else {
                fastSince = nil
            }
            if state != .active { state = armed ? .ready : .moving }
        }
        return events
    }

    private func resetMotion() {
        quietSince = nil
        lastRestT = nil
        armed = false
        fastSince = nil
        belowSince = nil
        speed = 0.0
    }

    private func endSegment(_ t: Double) {
        fastSince = nil
        belowSince = nil
        state = armed ? .ready : .moving
    }

    private func reject(_ reason: String) -> EngineEvent {
        rejected[reason, default: 0] += 1
        return .rejected(reason: reason)
    }

    private func finalize(_ t: Double) -> EngineEvent {
        let seg = buf.filter { $0.t >= segStartT }
        endSegment(t)
        guard !seg.isEmpty else { return reject("too_short") }
        let stats = segmentStats(seg)
        let reason = gateFailure(stats, gates)
        if !reason.isEmpty { return reject(reason) }
        guard let result = analyze(seg) else { return reject("bad_pattern") }
        let scored = scoreRep(result.metrics, result.type, profile.metrics, scoring)
        guard let total = scored.total else { return reject("no_metrics") }
        let rep = Rep(tStart: seg[0].t, tEnd: seg[seg.count - 1].t, type: result.type, events: result.events,
                      metrics: result.metrics, scores: scored.scores, score: total, cues: scored.cues,
                      peakSpeed: stats.peakSpeed)
        reps.append(rep)
        // only a counted rep closes off its frames; a rejected take-back may belong to the next motion
        lastSegEndT = t
        cooldownUntil = t + det.refractoryMs / 1000.0
        return .rep(rep)
    }

    private func analyze(_ seg: [Sample]) -> Analysis? {
        switch profile.analyzer {
        case "golf": return analyzeGolf(seg, self)
        case "basketball": return analyzeBasketball(seg, self)
        case "racket": return analyzeRacket(seg, self)
        default: return nil
        }
    }
}
