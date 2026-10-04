import Foundation

public struct JointObservation {
    public var x: Double
    public var y: Double
    public var confidence: Double
    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public enum Handedness: String, Codable { case right, left }

public enum EngineState: String {
    case noPerson = "no_person"
    case moving
    case ready
    case active
}

public struct Profiles: Decodable {
    public let joints: [String]
    public let sports: [String: SportProfile]
    let preprocess: Preprocess
    let scoring: ScoringConfig

    public static func load(from data: Data) throws -> Profiles {
        try JSONDecoder().decode(Profiles.self, from: data)
    }
}

struct Preprocess: Decodable {
    let minConf, holdS, jointTauS, speedTauS, torsoTauS, noPersonS, armAfterS, facingTauS: Double
    enum CodingKeys: String, CodingKey {
        case minConf = "min_conf", holdS = "hold_s", jointTauS = "joint_tau_s"
        case speedTauS = "speed_tau_s", torsoTauS = "torso_tau_s", noPersonS = "no_person_s"
        case armAfterS = "arm_after_s", facingTauS = "facing_tau_s"
    }
}

struct ScoringConfig: Decodable {
    let zScale, formWeight, consistencyWeight: Double
    enum CodingKeys: String, CodingKey {
        case zScale = "z_scale", formWeight = "form_weight", consistencyWeight = "consistency_weight"
    }
}

struct Detect: Decodable {
    let restSpeed, restMs, enterSpeed, enterMs, exitSpeed, settleMs, maxLookbackS, refractoryMs, postPeakS: Double
    enum CodingKeys: String, CodingKey {
        case restSpeed = "rest_speed", restMs = "rest_ms", enterSpeed = "enter_speed", enterMs = "enter_ms"
        case exitSpeed = "exit_speed", settleMs = "settle_ms", maxLookbackS = "max_lookback_s"
        case refractoryMs = "refractory_ms", postPeakS = "post_peak_s"
    }
}

struct Gates: Decodable {
    let minPeakSpeed, minDurationS, maxDurationS, minPathLen, minVerticalRange, minHorizontalRange: Double
    let minExtent, minPathRatio, startHandMinY, peakHandMaxY: Double?
    enum CodingKeys: String, CodingKey {
        case minPeakSpeed = "min_peak_speed", minDurationS = "min_duration_s", maxDurationS = "max_duration_s"
        case minPathLen = "min_path_len", minVerticalRange = "min_vertical_range"
        case minHorizontalRange = "min_horizontal_range", minExtent = "min_extent"
        case minPathRatio = "min_path_ratio", startHandMinY = "start_hand_min_y"
        case peakHandMaxY = "peak_hand_max_y"
    }
}

public struct SportProfile: Decodable {
    public let label: String
    public let camera: String
    public let metrics: [MetricSpec]
    let analyzer: String
    let tracker: String
    let detect: Detect
    let gates: Gates
    let pattern: [String: Double]?
}

struct TypeTarget: Decodable {
    let mean, std, tol: Double
}

public struct MetricSpec: Decodable {
    public let id: String
    public let label: String
    public let unit: String
    public let mean: Double
    public let std: Double
    public let tol: Double
    let weight: Double
    let oneSided: String?
    let byType: [String: TypeTarget?]?
    let onlyTypes: [String]?
    let cueLow: String
    let cueHigh: String
    enum CodingKeys: String, CodingKey {
        case id, label, unit, mean, std, tol, weight
        case oneSided = "one_sided", byType = "by_type", cueLow = "cue_low", cueHigh = "cue_high"
        case onlyTypes = "only_types"
    }
}

public struct Rep: Codable {
    public let tStart: Double
    public let tEnd: Double
    public let type: String
    public let events: [String: Double]
    public let metrics: [String: Double]
    public let scores: [String: Double]
    public let score: Double
    public let cues: [String]
    public let peakSpeed: Double
    enum CodingKeys: String, CodingKey {
        case tStart = "t_start", tEnd = "t_end", type, events, metrics, scores, score, cues
        case peakSpeed = "peak_speed"
    }
}

public enum EngineEvent {
    case rep(Rep)
    case rejected(reason: String)
}

public struct MetricSummary: Codable {
    public let mean: Double
    public let sd: Double
    public let score: Double
    public let n: Int
}

public struct SessionSummary: Codable {
    public let sport: String
    public let repCount: Int
    public let rejected: [String: Int]
    public let types: [String: Int]
    public let score: Double?
    public let formScore: Double?
    public let consistency: Double?
    public let metrics: [String: MetricSummary]
    public let topCues: [String]
    public let activeS: Double
    public let passiveS: Double
    enum CodingKeys: String, CodingKey {
        case sport, rejected, types, score, consistency, metrics
        case repCount = "rep_count", formScore = "form_score", topCues = "top_cues"
        case activeS = "active_s", passiveS = "passive_s"
    }
}
