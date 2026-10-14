import Foundation

// On-device port of ml/strokes.py; never changes the counting/scoring gates.
public typealias StrokeFeatures = [String: Double?]
public struct StrokeTaskPrediction: Codable {
    public let label: String
    public let probs: [String: Double]
    public init(label: String, probs: [String: Double]) { self.label = label; self.probs = probs }
}
public typealias StrokePrediction = [String: StrokeTaskPrediction]
public struct StrokeModel: Decodable {
    public let features: [String]
    public let normalization: Normalization
    public let tasks: [String: Task]
    public struct Normalization: Decodable { public let impute, mean, std: [Double] }
    public struct Task: Decodable { public let classes: [String]; public let weights: [[Double]]; public let bias: [Double] }
    public static func load(from data: Data) throws -> StrokeModel { try JSONDecoder().decode(Self.self, from: data) }
    public func predict(_ features: StrokeFeatures, tasks selected: [String]? = nil) -> StrokePrediction {
        let z = self.features.enumerated().map { i, name -> Double in
            let value = features[name] ?? nil
            let x = value.flatMap { $0.isFinite ? $0 : nil } ?? normalization.impute[i]
            return (x - normalization.mean[i]) / normalization.std[i]
        }
        var result: StrokePrediction = [:]
        for (name, task) in tasks {
            if let selected = selected, !selected.contains(name) { continue }
            let logits = task.weights.enumerated().map { i, row in
                zip(row, z).reduce(0.0) { $0 + $1.0 * $1.1 } + task.bias[i]
            }
            let maximum = logits.max()!
            let expValues = logits.map { exp($0 - maximum) }, total = expValues.reduce(0, +)
            let probs = expValues.map { $0 / total }
            var best = 0
            for i in probs.indices where probs[i] > probs[best] { best = i }
            result[name] = StrokeTaskPrediction(label: task.classes[best], probs: Dictionary(uniqueKeysWithValues: zip(task.classes, probs)))
        }
        return result
    }
    public func predict(_ values: [Double?], tasks: [String]? = nil) throws -> StrokePrediction {
        guard values.count == features.count else { throw StrokeError.invalidFeatureCount }
        return predict(Dictionary(uniqueKeysWithValues: zip(features, values)), tasks: tasks)
    }
}
public enum StrokeError: Error { case insufficientSamples, missingWrist, invalidFeatureCount }
private let strokeEvents = ["backswing", "contact", "finish"]
private let strokeMetrics = ["stance_height", "contact_arm", "contact_height", "swing_through", "shoulder_turn", "swing_tempo", "backswing_size", "ready_height", "head_stability", "finish_height", "elbow_finish", "off_hand_reach", "spacing", "extension_through"]
private func strokeAngle(_ a: Point?, _ b: Point?, _ c: Point?) -> Double? {
    guard let a = a, let b = b, let c = c else { return nil }
    let x = Point(x: a.x-b.x, y: a.y-b.y), y = Point(x: c.x-b.x, y: c.y-b.y)
    let n = hypot(x.x,x.y) * hypot(y.x,y.y)
    return n < 1e-9 ? nil : acos(max(-1,min(1,(x.x*y.x+x.y*y.y)/n))) * 180 / Double.pi
}
private func strokeFilled(_ values: [Point?]) -> [Point?] {
    var out = values, last: Point? = nil
    for i in out.indices { if out[i] == nil { out[i] = last } else { last = out[i] } }
    last = nil
    for i in out.indices.reversed() { if out[i] == nil { out[i] = last } else { last = out[i] } }
    return out
}
private func strokeResample(_ ts: [Double], _ values: [Double], _ t0: Double, _ t1: Double) -> [Double] {
    var j = 0, out: [Double] = []
    for i in 0..<16 {
        let t = t0 + (t1-t0) * Double(i) / 15
        while j < ts.count-2 && ts[j+1] < t { j += 1 }
        if ts.count == 1 || t <= ts[0] { out.append(values[0]) }
        else if t >= ts.last! { out.append(values.last!) }
        else { let w = ts[j+1] > ts[j] ? (t-ts[j])/(ts[j+1]-ts[j]) : 0; out.append(values[j]+w*(values[j+1]-values[j])) }
    }
    return out
}
public func repFeatures(_ samples: [Sample], rep: Rep, dominant dom: String = "r") throws -> StrokeFeatures {
    let off = dom == "r" ? "l" : "r"
    let seg = samples.filter { rep.tStart-1e-6 <= $0.t && $0.t <= rep.tEnd+1e-6 }
    guard seg.count >= 2 else { throw StrokeError.insufficientSamples }
    let side = seg.reduce(0.0) { $0 + ($1.pts[dom+"_shoulder"]!.x-$1.pts[off+"_shoulder"]!.x)/$1.torso } >= 0 ? 1.0 : -1.0
    func rel(_ s: Sample, _ name: String) -> Point? { s.pts[name].map { Point(x:($0.x-s.hip.x)/s.torso*side,y:($0.y-s.hip.y)/s.torso) } }
    let ts = seg.map(\.t), t0 = ts[0], t1 = ts.last!, duration = max(t1-t0,1e-6)
    let dw = strokeFilled(seg.map { rel($0,dom+"_wrist") })
    guard dw[0] != nil else { throw StrokeError.missingWrist }
    var ow = strokeFilled(seg.map { rel($0,off+"_wrist") }); if ow[0] == nil { ow = dw }
    let d = dw.map { $0! }, o = ow.map { $0! }
    var f: StrokeFeatures = [:]
    func put(_ key: String, _ value: Double?) { f.updateValue(value, forKey:key) }
    for (name, traj) in [("dom",d),("off",o)] {
        for (axis, values) in [("x",traj.map(\.x)),("y",traj.map(\.y))] {
            for (i,v) in strokeResample(ts,values,t0,t1).enumerated() { put("\(name)_\(axis)_\(i)",v) }
        }
    }
    func at(_ t: Double) -> Int { var best = 0; for i in seg.indices where abs(seg[i].t-t) < abs(seg[best].t-t) { best = i }; return best }
    var idx: [String: Int?] = [:]
    for e in strokeEvents { idx.updateValue(rep.events[e].map(at),forKey:e) }
    if (idx["contact"] ?? nil) == nil { var best = 0; for i in seg.indices where seg[i].speed > seg[best].speed { best = i }; idx["contact"] = best }
    for e in strokeEvents {
        let i = idx[e] ?? nil, s = i.map { seg[$0] }
        put("dom_elbow_\(e)",s.flatMap { strokeAngle($0.pts[dom+"_shoulder"],$0.pts[dom+"_elbow"],$0.pts[dom+"_wrist"]) })
        put("off_elbow_\(e)",s.flatMap { strokeAngle($0.pts[off+"_shoulder"],$0.pts[off+"_elbow"],$0.pts[off+"_wrist"]) })
        put("dom_wrist_y_\(e)",i.map { d[$0].y }); put("dom_wrist_x_\(e)",i.map { d[$0].x })
    }
    let c = (idx["contact"] ?? nil)!; var lo = (idx["backswing"] ?? nil) ?? 0, hi = (idx["finish"] ?? nil) ?? seg.count-1
    if hi < lo { swap(&lo,&hi) }
    func gap(_ i: Int) -> Double { hypot(d[i].x-o[i].x,d[i].y-o[i].y) }
    let gaps = (lo...hi).map(gap)
    put("hands_gap_min",gaps.min()); put("hands_gap_mean",gaps.reduce(0,+)/Double(gaps.count)); put("hands_gap_contact",gap(c)); put("hands_close_frac",Double(gaps.filter { $0 < 0.5 }.count)/Double(gaps.count))
    put("duration",duration); put("peak_speed",seg.map(\.speed).max()); put("contact_frac",(seg[c].t-t0)/duration); put("backswing_frac",(seg[lo].t-t0)/duration)
    func apex(_ a: [Point]) -> Int { var k = 0; for i in a.indices where a[i].y < a[k].y { k = i }; return k }
    let da = apex(d), oa = apex(o)
    put("dom_apex_y",d[da].y); put("off_apex_y",o[oa].y); put("toss_lead",(seg[da].t-seg[oa].t)/duration); put("off_apex_x",o[oa].x)
    let nose = rel(seg[c],"nose"), la = seg[c].pts["l_ankle"], ra = seg[c].pts["r_ankle"]
    put("nose_x_contact",nose?.x); put("nose_y_contact",nose?.y); put("ankle_gap_contact",la != nil && ra != nil ? abs(la!.x-ra!.x)/seg[c].torso : nil)
    let end = seg.last!
    put("hip_dx",(end.hip.x-seg[0].hip.x)/end.torso*side); put("hip_dy",(end.hip.y-seg[0].hip.y)/end.torso)
    func width(_ s: Sample) -> Double { hypot(s.pts["l_shoulder"]!.x-s.pts["r_shoulder"]!.x,s.pts["l_shoulder"]!.y-s.pts["r_shoulder"]!.y) }
    put("shoulder_width_min",seg.map(width).min()!/max(width(seg[0]),1e-6))
    put("dom_path_len",(1..<d.count).reduce(0.0) { $0+hypot(d[$1].x-d[$1-1].x,d[$1].y-d[$1-1].y) })
    let a = max(c-1,0), b = min(c+1,seg.count-1), dt = max(seg[b].t-seg[a].t,1e-6)
    put("dom_vx_contact",(d[b].x-d[a].x)/dt); put("dom_vy_contact",(d[b].y-d[a].y)/dt)
    for type in ["forehand","backhand","serve"] { put("type_\(type)",rep.type == type ? 1 : 0) }
    for key in strokeMetrics { put("m_\(key)",rep.metrics[key]) }
    return f
}
public struct StrokeEstimate {
    public let key, family, text: String
    public static func display(_ prediction: StrokePrediction?) -> StrokeEstimate? {
        let families = ["forehand":"Forehand","backhand_one":"One-handed backhand","backhand_two":"Two-handed backhand","serve":"Serve","volley":"Volley","smash":"Smash"]
        guard let c = prediction?["coarse"], let family = families[c.label],
              (c.probs[c.label] ?? 0) >= (["volley","smash"].contains(c.label) ? 0.75 : 0.6) else { return nil }
        var words = [family]
        if ["forehand","backhand_one","backhand_two"].contains(c.label), let spin = prediction?["groundstroke_spin"], (spin.probs[spin.label] ?? 0) >= 0.6 {
            if spin.label == "slice" { words.append("slice") }
            else if spin.label == "flat_topspin" { words.append("topspin/flat") }
        }
        words.append("estimate")
        return StrokeEstimate(key:c.label,family:family,text:words.joined(separator:" · "))
    }
    public static func counts(_ reps: [Rep]) -> String {
        var counts: [String:Int] = [:]
        for rep in reps { let e = display(rep.strokeEstimate); let key = e?.key.hasPrefix("backhand_") == true ? "backhand" : (e?.key ?? "uncertain"); counts[key,default:0] += 1 }
        return ["forehand","backhand","serve","volley","smash","uncertain"].filter { counts[$0] != nil }.map { key in
            let n = counts[key]!; return "\(n) \(key == "uncertain" ? key : key + (n == 1 ? "" : "s"))"
        }.joined(separator:" · ")
    }
}
