import Foundation

// Port of ml/formcoach/scoring.py. Keep the two in step; `swift run formcore-check` verifies it.

struct Target {
    let mean, std, tol: Double
}

func targetFor(_ spec: MetricSpec, _ repType: String) -> Target? {
    if let only = spec.onlyTypes, !only.contains(repType) { return nil }
    if let entry = spec.byType?[repType] {
        guard let o = entry else { return nil }
        return Target(mean: o.mean, std: o.std, tol: o.tol)
    }
    return Target(mean: spec.mean, std: spec.std, tol: spec.tol)
}

func metricScore(_ value: Double, _ spec: MetricSpec, _ repType: String, _ zScale: Double) -> Double? {
    guard let tgt = targetFor(spec, repType) else { return nil }
    let dev = value - tgt.mean
    if (spec.oneSided == "high" && dev < 0) || (spec.oneSided == "low" && dev > 0) {
        return 100.0
    }
    let z = max(0.0, abs(dev) - tgt.tol) / tgt.std
    return 100.0 * exp(-0.5 * pow(z / zScale, 2))
}

struct RepScore {
    let scores: [String: Double]
    let total: Double?
    let cues: [String]
}

func scoreRep(_ metrics: [String: Double], _ repType: String, _ specs: [MetricSpec],
              _ scoring: ScoringConfig) -> RepScore {
    var scores: [String: Double] = [:]
    var wsum = 0.0
    var total = 0.0
    var worst: [(Double, String)] = []
    for spec in specs {
        guard let v = metrics[spec.id], let s = metricScore(v, spec, repType, scoring.zScale) else { continue }
        scores[spec.id] = s
        wsum += spec.weight
        total += spec.weight * s
        if s < 75.0, let tgt = targetFor(spec, repType) {
            let cue = v > tgt.mean ? spec.cueHigh : spec.cueLow
            if !cue.isEmpty { worst.append((s, cue)) }
        }
    }
    if wsum == 0 { return RepScore(scores: scores, total: nil, cues: []) }
    // stable sort by score, matching Python's list.sort
    let ordered = worst.enumerated().sorted { a, b in
        a.element.0 != b.element.0 ? a.element.0 < b.element.0 : a.offset < b.offset
    }
    return RepScore(scores: scores, total: total / wsum, cues: ordered.prefix(2).map { $0.element.1 })
}

func summarize(sport: String, reps: [Rep], rejected: [String: Int], specs: [MetricSpec],
               scoring: ScoringConfig, activeS: Double, passiveS: Double) -> SessionSummary {
    var metrics: [String: MetricSummary] = [:]
    var cons: [Double] = []
    for spec in specs {
        var vals: [Double] = []
        var scs: [Double] = []
        for r in reps {
            if let s = r.scores[spec.id], let v = r.metrics[spec.id] {
                vals.append(v)
                scs.append(s)
            }
        }
        if vals.isEmpty { continue }
        let m = vals.reduce(0, +) / Double(vals.count)
        let sd = sqrt(vals.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(vals.count))
        metrics[spec.id] = MetricSummary(mean: m, sd: sd, score: scs.reduce(0, +) / Double(scs.count),
                                         n: vals.count)
        if vals.count >= 3 {
            cons.append(100.0 * exp(-0.5 * pow(sd / (scoring.zScale * spec.std), 2)))
        }
    }
    let form: Double? = reps.isEmpty ? nil : reps.reduce(0) { $0 + $1.score } / Double(reps.count)
    let consistency: Double? = cons.isEmpty ? nil : cons.reduce(0, +) / Double(cons.count)
    var score: Double? = nil
    if let f = form {
        if let c = consistency {
            score = scoring.formWeight * f + scoring.consistencyWeight * c
        } else {
            score = f
        }
    }
    var cueCounts: [String: Int] = [:]
    var types: [String: Int] = [:]
    for r in reps {
        for c in r.cues { cueCounts[c, default: 0] += 1 }
        types[r.type, default: 0] += 1
    }
    let top = cueCounts.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
    return SessionSummary(sport: sport, repCount: reps.count, rejected: rejected, types: types,
                          score: score, formScore: form, consistency: consistency, metrics: metrics,
                          topCues: top.prefix(3).map { $0.key }, activeS: activeS, passiveS: passiveS)
}
