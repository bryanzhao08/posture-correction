import Foundation
import FormCore

// Replays recordings through the Swift engine and compares with the Python reference output.
// usage: formcore-check <fixtures.json> <sport_profiles.json>
// fixtures: [{"name", "recording": {"sport","handedness","aspect","frames":[{"t","j"}]},
//             "expected": {"reps": [Rep JSON], "rejected": {reason: n}, "score": Double?}}]

let args = CommandLine.arguments
if args.count == 3, args[1] == "--strokes" {
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
    let model = try StrokeModel.load(from: Data(contentsOf: URL(fileURLWithPath: object["model_path"] as! String)))
    let profiles = try Profiles.load(from: JSONSerialization.data(withJSONObject: object["profiles"]!))
    let cases = object["cases"] as! [[String: Any]]
    var total = 0, bad = 0
    func features(_ value: Any) -> StrokeFeatures {
        (value as! [String: Any]).mapValues { $0 as? Double }
    }
    func check(_ name: String, _ actual: StrokeFeatures, _ expected: [String: Any]) {
        total += 1
        let f = features(expected["features"]!)
        var ok = Set(actual.keys) == Set(f.keys)
        for key in f.keys {
            let a = actual[key] ?? nil, e = f[key] ?? nil
            if let a = a, let e = e { if !a.isFinite || !e.isFinite || abs(a-e) > 1e-6 { ok = false; print("feature \(key): \(a) vs \(e)") } }
            else if (a == nil) != (e == nil) { ok = false }
        }
        let got = model.predict(actual)
        for (task, result) in expected["prediction"] as! [String: [String: Any]] {
            if got[task]?.label != result["label"] as? String { ok = false }
            for (label, p) in result["probs"] as! [String: Double] {
                if abs((got[task]?.probs[label] ?? -1)-p) > 1e-6 { ok = false }
            }
        }
        if !ok { bad += 1; print("MISMATCH stroke \(name)") }
    }
    for c in cases {
        let name = c["name"] as! String
        if let rec = c["recording"] as? [String: Any] {
            let hand: Handedness = rec["handedness"] as? String == "left" ? .left : .right
            let eng = FormEngine(profiles: profiles,sport:"tennis",handedness:hand,view:rec["view"] as? String,focus:rec["focus"] as? String)
            var samples: [Sample] = []
            for fr in rec["frames"] as! [[String: Any]] {
                let joints = (fr["j"] as! [[Double]]).map { Optional(JointObservation(x:$0[0],y:$0[1],confidence:$0[2])) }
                let before = eng.lastSample?.t
                _ = eng.push(t:fr["t"] as! Double,joints:joints,aspect:rec["aspect"] as? Double ?? 1)
                if let s = eng.lastSample, s.t != before { samples.append(s) }
            }
            let expected = c["expected"] as! [[String: Any]]
            if eng.reps.count != expected.count { bad += 1; print("MISMATCH \(name) rep count"); continue }
            for (i,rep) in eng.reps.enumerated() { check("\(name)/\(i)",try repFeatures(samples,rep:rep,dominant:hand == .left ? "l" : "r"),expected[i]) }
        } else if let data = c["samples"] as? [[String: Any]] {
            let samples = data.map { s -> Sample in
                let pts = (s["pts"] as! [String: [Double]]).mapValues { Point(x:$0[0],y:$0[1]) }
                let hip = s["hip"] as! [Double]
                return Sample(t:s["t"] as! Double,pts:pts,torso:s["torso"] as! Double,hip:Point(x:hip[0],y:hip[1]),rx:s["rx"] as! Double,ry:s["ry"] as! Double,speed:s["speed"] as! Double)
            }
            let rep = try JSONDecoder().decode(Rep.self,from:JSONSerialization.data(withJSONObject:c["rep"]!))
            check(name,try repFeatures(samples,rep:rep,dominant:c["dom"] as! String),c["expected"] as! [String: Any])
        } else { check(name,features(c["features"]!),c["expected"] as! [String: Any]) }
    }
    print("\(total-bad)/\(total) stroke descriptors and probabilities match (absolute 1e-6)")
    exit(bad == 0 ? 0 : 1)
}

if args.count == 3, args[1] == "--corrections" {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let fixtures = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    func points(_ value: Any?) -> [String: Point]? {
        guard let object = value as? [String: [Double]] else { return nil }
        return object.mapValues { Point(x: $0[0], y: $0[1]) }
    }
    var failures = 0
    for (i, f) in fixtures.enumerated() {
        let actual = correctedPose(analyzer: f["analyzer"] as! String, metric: f["metric"] as! String,
            target: f["target"] as! Double, pose: points(f["pose"])!, ref: points(f["ref"]),
            torso: f["torso"] as! Double, dominant: f["dom"] as! String, repType: f["rep_type"] as? String ?? "")
        let expected = points(f["expected"])
        let agrees: Bool
        if let a = actual, let e = expected {
            agrees = Set(a.keys) == Set(e.keys) && e.allSatisfy { name, p in
                abs(a[name]!.x - p.x) <= 1e-6 && abs(a[name]!.y - p.y) <= 1e-6
            }
        } else { agrees = actual == nil && expected == nil }
        if !agrees { failures += 1; print("MISMATCH correction \(i): \(f["analyzer"]!) \(f["metric"]!)") }
    }
    print("\(failures == 0 ? "OK" : "FAILED"): \(fixtures.count) corrections, \(failures) mismatches")
    exit(failures == 0 ? 0 : 1)
}
guard args.count == 3,
      let fixtureData = FileManager.default.contents(atPath: args[1]),
      let profileData = FileManager.default.contents(atPath: args[2]) else {
    print("usage: formcore-check <fixtures.json> <sport_profiles.json>")
    exit(2)
}
let profiles = try Profiles.load(from: profileData)
guard let fixtures = try JSONSerialization.jsonObject(with: fixtureData) as? [[String: Any]] else {
    print("fixtures must be a JSON array")
    exit(2)
}

var failures: [String] = []

func close(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) <= 1e-6 * max(1.0, abs(a), abs(b))
}

func compareDict(_ name: String, _ what: String, _ swift: [String: Double], _ py: [String: Any]) {
    let pyVals = py.compactMapValues { $0 as? Double }
    if Set(swift.keys) != Set(pyVals.keys) {
        failures.append("\(name) \(what) keys: swift \(swift.keys.sorted()) python \(pyVals.keys.sorted())")
        return
    }
    for (k, v) in pyVals where !close(swift[k]!, v) {
        failures.append("\(name) \(what).\(k): swift \(swift[k]!) python \(v)")
    }
}

var repTotal = 0
for fx in fixtures {
    let name = fx["name"] as! String
    let rec = fx["recording"] as! [String: Any]
    let exp = fx["expected"] as! [String: Any]
    let hand: Handedness = (rec["handedness"] as? String) == "left" ? .left : .right
    let pl = rec["player"] as? [String: Any]
    let player = pl.map { Player(heightCm: $0["height_cm"] as? Double, level: $0["level"] as? String) }
    let engine = FormEngine(profiles: profiles, sport: rec["sport"] as! String, handedness: hand, view: rec["view"] as? String,
                            focus: rec["focus"] as? String, player: player, drill: rec["drill"] as? String)
    let aspect = rec["aspect"] as? Double ?? 1.0
    for fr in rec["frames"] as! [[String: Any]] {
        let joints: [JointObservation?] = (fr["j"] as! [[Double]]).map {
            JointObservation(x: $0[0], y: $0[1], confidence: $0[2])
        }
        _ = engine.push(t: fr["t"] as! Double, joints: joints, aspect: aspect)
    }
    let expReps = exp["reps"] as! [[String: Any]]
    repTotal += expReps.count
    if engine.reps.count != expReps.count {
        failures.append("\(name): swift counted \(engine.reps.count) reps, python \(expReps.count)")
        continue
    }
    for (i, (r, e)) in zip(engine.reps, expReps).enumerated() {
        let tag = "\(name) rep \(i)"
        if r.type != e["type"] as! String { failures.append("\(tag) type: swift \(r.type) python \(e["type"]!)") }
        if !close(r.score, e["score"] as! Double) { failures.append("\(tag) score: swift \(r.score) python \(e["score"]!)") }
        compareDict(tag, "events", r.events, e["events"] as! [String: Any])
        compareDict(tag, "metrics", r.metrics, e["metrics"] as! [String: Any])
        compareDict(tag, "scores", r.scores, e["scores"] as! [String: Any])
        if r.cues != e["cues"] as! [String] { failures.append("\(tag) cues differ") }
    }
    let summary = engine.summary()
    let rejected = (exp["rejected"] as! [String: Any]).compactMapValues { $0 as? Int }
    if summary.rejected != rejected { failures.append("\(name) rejected: swift \(summary.rejected) python \(rejected)") }
    if let s = exp["score"] as? Double {
        if summary.score == nil || !close(summary.score!, s) { failures.append("\(name) session score: swift \(String(describing: summary.score)) python \(s)") }
    } else if summary.score != nil {
        failures.append("\(name) session score: swift \(summary.score!) python nil")
    }
}

if failures.isEmpty {
    print("OK: \(fixtures.count) recordings, \(repTotal) reps match the Python reference")
} else {
    failures.prefix(40).forEach { print("MISMATCH \($0)") }
    print("FAILED: \(failures.count) mismatches")
    exit(1)
}
