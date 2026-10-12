import Foundation

// Port of ml/formcoach/personalize.py. Keep the two in step; `swift run formcore-check` verifies it.

/// Optional player profile. Without one the engine scores against the fitted pro ranges.
public struct Player: Codable, Equatable {
    public var heightCm: Double?
    public var level: String?
    public init(heightCm: Double? = nil, level: String? = nil) {
        self.heightCm = heightCm
        self.level = level
    }
    enum CodingKeys: String, CodingKey { case heightCm = "height_cm", level }
}

public struct PlayerLevel: Decodable {
    public let label: String
    public let about: String
    let tolScale, stdScale: Double
    enum CodingKeys: String, CodingKey { case label, about, tolScale = "tol_scale", stdScale = "std_scale" }
}

public struct PlayerConfig: Decodable {
    public let referenceHeightCm, minHeightCm, maxHeightCm, torsoFraction: Double
    public let defaultLevel: String
    public let levels: [String: PlayerLevel]
    /// Levels from most forgiving to strictest.
    public var levelOrder: [String] { ["beginner", "intermediate", "advanced", "pro"].filter { levels[$0] != nil } }
    enum CodingKeys: String, CodingKey {
        case referenceHeightCm = "reference_height_cm", minHeightCm = "min_height_cm", maxHeightCm = "max_height_cm"
        case torsoFraction = "torso_fraction", defaultLevel = "default_level", levels
    }

    /// Shoulder-to-hip length in metres estimated from standing height, for showing real units.
    public func torsoMeters(heightCm: Double?) -> Double? {
        guard let h = heightCm, h > 0 else { return nil }
        return h / 100.0 * torsoFraction
    }
}

public struct Drill: Decodable, Identifiable {
    public let id: String
    public let label: String
    public let about: String
    public let goalReps: Int
    public let types: [String]?
    public let emphasis: [String: Double]?
    public let trainings: [String]?
    public let tip: String?
    enum CodingKeys: String, CodingKey {
        case id, label, about, types, emphasis, trainings, tip
        case goalReps = "goal_reps"
    }
}

public extension SportProfile {
    /// Drills offered for a tennis training type (or all drills for sports without training types).
    func drills(for training: String?) -> [Drill] {
        (drills ?? []).filter { d in training == nil || d.trainings == nil || d.trainings!.contains(training!) }
    }
}

func personalize(_ profile: SportProfile, _ cfg: PlayerConfig?, _ player: Player?, _ drillID: String?) -> SportProfile {
    let drill = drillID.flatMap { id in profile.drills?.first { $0.id == id } }
    if player == nil && drill == nil { return profile }
    var out = profile
    let level = player?.level.flatMap { cfg?.levels[$0] }
    let height = player?.heightCm
    let emphasis = drill?.emphasis ?? [:]
    out.metrics = profile.metrics.map { original in
        var spec = original
        func adjust(_ f: (inout Double, inout Double, inout Double) -> Void) {
            // copies: passing three properties of the captured `spec` inout at once is an access conflict
            var (mean, std, tol) = (spec.mean, spec.std, spec.tol)
            f(&mean, &std, &tol)
            (spec.mean, spec.std, spec.tol) = (mean, std, tol)
            if let byType = spec.byType {
                spec.byType = byType.mapValues { entry in
                    guard var t = entry else { return nil }
                    f(&t.mean, &t.std, &t.tol)
                    return t
                }
            }
        }
        if let level = level {
            adjust { _, std, tol in
                tol = tol * level.tolScale
                std = std * level.stdScale
            }
        }
        if let shift = spec.heightShift, let h = height, h != 0, let cfg = cfg {
            let steps = max(-shift.maxSteps, min(shift.maxSteps, (cfg.referenceHeightCm - h) / 10.0))
            adjust { mean, _, _ in mean = mean + shift.per10cm * steps }
        }
        if let mult = emphasis[spec.id] {
            spec.weight = spec.weight * mult
            spec.focus = mult > 1.0
        }
        return spec
    }
    out.drill = drill
    return out
}

public extension Profiles {
    /// The profile a session is scored with: camera view, then the player's level and height, then the drill.
    func scoringProfile(sport: String, view: String?, player: Player?, drill: String?) -> SportProfile? {
        guard let base = sports[sport] else { return nil }
        return personalize(base.effective(for: view ?? base.defaultView), self.player, player, drill)
    }
}
