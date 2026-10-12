import Foundation
import FormCore

/// The player's height, level and units. Kept on this iPhone only; the level and drill travel with each
/// session summary, the height never leaves the device.
enum PlayerSettings {
    static let heightKey = "player.heightCm"      // Double, 0 = not set
    static let levelKey = "player.level"
    static let metricKey = "player.metric"

    static func current(_ config: PlayerConfig?) -> Player {
        let defaults = UserDefaults.standard
        let height = defaults.double(forKey: heightKey)
        let saved = defaults.string(forKey: levelKey)
        let level = saved.flatMap { config?.levels[$0] != nil ? $0 : nil } ?? config?.defaultLevel
        return Player(heightCm: height > 0 ? height : nil, level: level)
    }

    static var metric: Bool {
        UserDefaults.standard.object(forKey: metricKey) as? Bool ?? (Locale.current.measurementSystem != .us)
    }

    static func heightLabel(_ cm: Double?, metric: Bool) -> String {
        guard let cm = cm, cm > 0 else { return "Not set" }
        if metric { return "\(Int(cm.rounded())) cm" }
        let inches = Int((cm / 2.54).rounded())
        return "\(inches / 12)′\(inches % 12)″"
    }

    static func speedUnit(metric: Bool) -> String { metric ? "km/h" : "mph" }

    /// Peak hand speed of a rep (torso lengths per second) in km/h or mph. 2D only, so an estimate.
    static func handSpeed(_ rep: Rep, player: Player, config: PlayerConfig?, metric: Bool) -> Double? {
        guard let torso = config?.torsoMeters(heightCm: player.heightCm) else { return nil }
        let mps = rep.peakSpeed * torso
        return metric ? mps * 3.6 : mps * 2.23694
    }

    /// A torso-length value as a real distance, when the height is known.
    static func realDistance(_ value: Double, player: Player, config: PlayerConfig?, metric: Bool) -> String? {
        guard let torso = config?.torsoMeters(heightCm: player.heightCm) else { return nil }
        let cm = value * torso * 100
        return metric ? "\(Int(cm.rounded())) cm" : String(format: "%.1f in", cm / 2.54)
    }

    /// Closest a phone held upright (about 70° vertical field of view) can be and still fit you head to feet.
    static func minPhoneDistance(heightCm: Double, metric: Bool) -> String {
        let m = (heightCm / 100 / 0.85) / 2 / tan(35 * Double.pi / 180)
        return metric ? String(format: "%.1f m", m) : "\(Int((m * 3.281).rounded(.up))) ft"
    }
}
