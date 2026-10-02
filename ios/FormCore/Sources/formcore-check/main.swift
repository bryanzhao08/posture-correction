import Foundation
import FormCore

// Replays recordings through the Swift engine and compares with the Python reference output.
// usage: formcore-check <fixtures.json> <sport_profiles.json>
// fixtures: [{"name", "recording": {"sport","handedness","aspect","frames":[{"t","j"}]},
//             "expected": {"reps": [Rep JSON], "rejected": {reason: n}, "score": Double?}}]

let args = CommandLine.arguments
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
    let engine = FormEngine(profiles: profiles, sport: rec["sport"] as! String, handedness: hand)
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
