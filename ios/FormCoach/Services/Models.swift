import Foundation
import FormCore

enum Sport: String, CaseIterable, Identifiable, Codable {
    case golf, basketball, tennis, pickleball
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .golf: return "figure.golf"
        case .basketball: return "figure.basketball"
        case .tennis: return "figure.tennis"
        case .pickleball: return "figure.racquetball"
        }
    }
}

struct User: Codable {
    let id: Int
    let email: String
    var name: String
    var handedness: Handedness
    var emailReports: Bool
    enum CodingKeys: String, CodingKey {
        case id, email, name, handedness
        case emailReports = "email_reports"
    }
}
struct AuthOut: Decodable {
    let accessToken: String
    let tokenType: String
    let user: User
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", tokenType = "token_type", user
    }
}
struct AuthIn: Encodable {
    let email: String
    let password: String
    let name: String?
    enum CodingKeys: String, CodingKey { case email, password, name }
}
struct UserPatch: Codable, Equatable {
    var name: String?
    var handedness: Handedness?
    var emailReports: Bool?
    enum CodingKeys: String, CodingKey { case name, handedness; case emailReports = "email_reports" }
}
struct SessionIn: Codable {
    let clientID: String
    let sport: String
    let handedness: Handedness
    let startedAt: String
    let durationS: Double
    let summary: SessionSummary
    let reps: [Rep]
    let appVersion: String
    let device: String
    enum CodingKeys: String, CodingKey {
        case clientID = "client_id", sport, handedness, startedAt = "started_at"
        case durationS = "duration_s", summary, reps, appVersion = "app_version", device
    }
}
struct SessionListItem: Codable, Identifiable {
    let id: Int
    let clientID: String
    let sport: String
    let startedAt: String
    let durationS: Double
    let repCount: Int
    let score: Double?
    enum CodingKeys: String, CodingKey {
        case id, clientID = "client_id", sport, startedAt = "started_at"
        case durationS = "duration_s", repCount = "rep_count", score
    }
}
struct SessionOut: Codable, Identifiable {
    let id: Int
    let clientID: String
    let sport: String
    let startedAt: String
    let durationS: Double
    let repCount: Int
    let score: Double?
    let handedness: Handedness
    let summary: SessionSummary
    let reps: [Rep]
    let comparison: Comparison
    let checkpoint: Checkpoint?
    enum CodingKeys: String, CodingKey {
        case id, clientID = "client_id", sport, startedAt = "started_at"
        case durationS = "duration_s", repCount = "rep_count", score
        case handedness, summary, reps, comparison, checkpoint
    }
}
struct Comparison: Codable {
    let previousSessions: Int
    let previousAvgScore: Double?
    let scoreDelta: Double?
    let metrics: [MetricComparison]
    enum CodingKeys: String, CodingKey {
        case previousSessions = "previous_sessions", previousAvgScore = "previous_avg_score"
        case scoreDelta = "score_delta", metrics
    }
}
struct MetricComparison: Codable, Identifiable {
    let id: String
    let label: String
    let unit: String
    let value: Double?
    let previous: Double?
    let pro: Double
    let score: Double?
    let direction: String?
    enum CodingKeys: String, CodingKey { case id, label, unit, value, previous, pro, score, direction }
}
struct Stats: Codable {
    let sport: String
    let sessions: Int
    let totalReps: Int
    let avgScore: Double?
    let bestScore: Double?
    let recentAvgScore: Double?
    let previousAvgScore: Double?
    let metrics: [MetricComparison]
    let trend: [TrendPoint]
    enum CodingKeys: String, CodingKey {
        case sport, sessions, totalReps = "total_reps", avgScore = "avg_score", bestScore = "best_score"
        case recentAvgScore = "recent_avg_score", previousAvgScore = "previous_avg_score", metrics, trend
    }
}
struct TrendPoint: Codable, Identifiable {
    let id: Int
    let startedAt: String
    let score: Double?
    let repCount: Int
    enum CodingKeys: String, CodingKey { case id, startedAt = "started_at", score, repCount = "rep_count" }
}
struct Checkpoint: Codable, Identifiable {
    let id: Int
    let sport: String
    let number: Int
    let createdAt: String
    let sessions: Int
    let totalReps: Int
    let avgScore: Double?
    let previousAvgScore: Double?
    let metrics: [MetricComparison]
    let focusCues: [String]
    enum CodingKeys: String, CodingKey {
        case id, sport, number, createdAt = "created_at", sessions, totalReps = "total_reps"
        case avgScore = "avg_score", previousAvgScore = "previous_avg_score", metrics, focusCues = "focus_cues"
    }
}
struct Recording: Codable {
    let sport: String
    let handedness: Handedness
    let aspect: Double
    var frames: [PoseFrame]
    enum CodingKeys: String, CodingKey { case sport, handedness, aspect, frames }
}
struct PoseFrame: Codable {
    let t: Double
    // Absent points use [0, 0, 0]; joint positions and confidence otherwise match FormCore.
    let j: [[Double]]
    enum CodingKeys: String, CodingKey { case t, j }
}
struct LocalSession: Codable, Identifiable {
    var id: String { payload.clientID }
    let payload: SessionIn
    var server: SessionOut?
    var recording: Recording?
    var poseUploaded: Bool
    var uploadError: String?
    enum CodingKeys: String, CodingKey { case payload, server, recording, poseUploaded, uploadError }
}
struct AccountCache: Codable {
    var user: User
    var stats: [String: Stats] = [:]
    var history: [String: [SessionListItem]] = [:]
    var details: [String: SessionOut] = [:]
    var checkpoints: [String: [Checkpoint]] = [:]
    var pendingPatch: UserPatch?
    var spokenCues = false
    var sharePose = false
    enum CodingKeys: String, CodingKey {
        case user, stats, history, details, checkpoints, pendingPatch, spokenCues, sharePose
    }
}

enum Display {
    static func score(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "—" }
    static func number(_ value: Double?, unit: String = "") -> String {
        guard let value = value else { return "—" }
        return String(format: "%.2f", value) + (unit.isEmpty ? "" : " " + unit)
    }
    static func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text) ?? .distantPast
    }
    static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
