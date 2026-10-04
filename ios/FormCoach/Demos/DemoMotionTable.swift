import Foundation

enum BaseMotion: String, CaseIterable { case golfSwing, basketballShot, tennisForehand, tennisBackhand, tennisServe, pickleballDink, pickleballDrive, pickleballOverhead, readyStance, tripod }
struct MotionSpec {
    let base: BaseMotion
    let wrong: [String: Double]
    let correct: [String: Double]
}
// Degrees for joint angles, metres for translations, seconds for timing. Coaches can tune this table.
enum DemoMotionTable {
    static let entries: [String: MotionSpec] = {
        var t: [String: MotionSpec] = [:]
        func add(_ key: String, _ base: BaseMotion, _ parameter: String, _ wrong: Double, _ correct: Double) {
            t[key] = MotionSpec(base: base, wrong: [parameter: wrong], correct: [parameter: correct])
        }
        add("golf.tempo_ratio.low", .golfSwing, "tempoBackSeconds", 0.25, 0.84)
        add("golf.tempo_ratio.high", .golfSwing, "tempoBackSeconds", 1.8, 0.84)
        add("golf.lead_arm_top.low", .golfSwing, "leadElbowBendAtTop", 100, 8)
        add("golf.head_sway.high", .golfSwing, "headSlide", 0.32, 0)
        add("golf.head_lift.low", .golfSwing, "headDrop", 0.3, 0)
        add("golf.head_lift.high", .golfSwing, "spineTiltLoss", 32, 0)
        add("golf.hip_sway.high", .golfSwing, "hipSlide", 0.35, 0.02)
        add("golf.shoulder_turn.high", .golfSwing, "shoulderTurnDeg", 20, 85)
        add("golf.finish_balance.high", .golfSwing, "finishLean", 35, 0)
        add("basketball.leg_drive.low", .basketballShot, "kneeBend", 0, 40)
        add("basketball.elbow_extension.low", .basketballShot, "armExtensionAtContact", 65, 5)
        add("basketball.elbow_flare.high", .basketballShot, "elbowFlare", 65, 4)
        add("basketball.release_height.low", .basketballShot, "releaseHeight", 65, 155)
        add("basketball.arm_verticality.high", .basketballShot, "armAcrossBody", 65, 0)
        add("basketball.follow_through_hold.low", .basketballShot, "followThroughHold", 0.05, 1.3)
        add("basketball.lateral_drift.high", .basketballShot, "drift", 0.4, 0)
        add("basketball.shot_rhythm.low", .basketballShot, "tempoBackSeconds", 1.4, 0.1)
        add("basketball.shot_rhythm.high", .basketballShot, "shotHitch", 70, 0)
        add("basketball.guide_hand_gap.low", .basketballShot, "guideHandPushes", 120, 35)
        add("tennis.stance_height.high", .readyStance, "kneeBend", 0, 35)
        add("tennis.contact_arm.low", .tennisServe, "armExtensionAtContact", 70, 5)
        add("tennis.contact_height.low", .tennisForehand, "contactHeight", 125, 65)
        add("tennis.contact_height.high", .tennisForehand, "contactHeight", 15, 65)
        add("tennis.swing_through.low", .tennisBackhand, "swingThrough", 15, 145)
        add("tennis.shoulder_turn.high", .tennisForehand, "unitTurnDeg", 5, 65)
        add("tennis.head_stability.high", .tennisForehand, "headTurnEarly", 80, 0)
        add("tennis.swing_tempo.low", .tennisForehand, "tempoDownSeconds", 1.1, 0.3)
        add("tennis.swing_tempo.high", .tennisForehand, "accelerationProfile", 0.1, 1)
        add("pickleball.stance_height.high", .readyStance, "kneeBend", 0, 35)
        add("pickleball.ready_height.high", .readyStance, "paddleHeightReady", 0, 65)
        add("pickleball.backswing_size.high", .pickleballDink, "backswingSize", 120, 25)
        add("pickleball.contact_arm.low", .pickleballOverhead, "armExtensionAtContact", 75, 5)
        add("pickleball.contact_height.low", .pickleballDrive, "contactHeight", 130, 55)
        add("pickleball.contact_height.high", .pickleballDrive, "contactHeight", 10, 55)
        add("pickleball.swing_through.low", .pickleballDrive, "swingThrough", 10, 100)
        add("pickleball.head_stability.high", .pickleballDink, "headTurnEarly", 75, 0)
        for sport in ["golf", "basketball", "tennis", "pickleball"] {
            t["setup." + sport] = MotionSpec(base: .tripod,
                wrong: ["tripodHeight": 0.35, "tripodDistance": 1],
                correct: ["tripodHeight": sport == "golf" ? 0.9 : 1.3, "tripodDistance": sport == "tennis" ? 5 : 3.5])
        }
        return t
    }()
}
