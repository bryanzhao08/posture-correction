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
        add("golf.tempo_ratio.high", .golfSwing, "pauseAtTop", 0.9, 0)
        add("golf.lead_arm_top.low", .golfSwing, "leadElbowBendAtTop", 100, 8)
        add("golf.head_sway.high", .golfSwing, "headSlide", 0.32, 0)
        add("golf.head_lift.low", .golfSwing, "spineTiltLoss", 35, 0)
        add("golf.head_lift.high", .golfSwing, "impactSink", 45, 0)
        add("golf.hip_sway.high", .golfSwing, "hipSlide", 0.35, 0.02)
        add("golf.shoulder_turn.high", .golfSwing, "shoulderTurnDeg", 20, 90)
        add("golf.finish_balance.high", .golfSwing, "finishLean", 0.28, -0.12)
        add("basketball.leg_drive.low", .basketballShot, "kneeBend", 0, 40)
        add("basketball.elbow_extension.low", .basketballShot, "armExtensionAtContact", 65, 5)
        add("basketball.elbow_flare.high", .basketballShot, "elbowFlare", 1.5, 0)
        add("basketball.release_height.low", .basketballShot, "releaseHeight", 0.20, 0.58)
        add("basketball.arm_verticality.high", .basketballShot, "armAcrossBody", -0.5, 0)
        add("basketball.follow_through_hold.low", .basketballShot, "followThroughHold", 0.05, 1.3)
        add("basketball.lateral_drift.high", .basketballShot, "drift", 0.4, 0)
        add("basketball.shot_rhythm.low", .basketballShot, "releaseKnee", 38, 0)
        add("basketball.shot_rhythm.high", .basketballShot, "pauseAtTop", 0.85, 0)
        add("basketball.guide_hand_gap.low", .basketballShot, "guideHandPushes", 1, 0)
        add("tennis.stance_height.high", .tennisForehand, "kneeBend", 0, 35)
        add("tennis.contact_arm.low", .tennisServe, "armExtensionAtContact", 70, 5)
        add("tennis.contact_height.low", .tennisForehand, "contactHeight", 0.08, -0.25)
        add("tennis.contact_height.high", .tennisForehand, "lowBallLoad", 0, 1)
        add("tennis.swing_through.low", .tennisForehand, "swingThrough", 0, 1)
        add("tennis.shoulder_turn.high", .tennisForehand, "unitTurnDeg", 5, 65)
        add("tennis.head_stability.high", .tennisBackhand, "headTurnEarly", 80, 0)
        add("tennis.swing_tempo.low", .tennisForehand, "accelerationProfile", 5, 1.4)
        add("tennis.swing_tempo.high", .tennisForehand, "tempoDownSeconds", 1.2, 0.3)
        add("pickleball.stance_height.high", .readyStance, "kneeBend", 0, 35)
        add("pickleball.ready_height.high", .readyStance, "paddleHeightReady", -0.50, -0.13)
        add("pickleball.backswing_size.high", .pickleballDink, "backswingSize", 0.40, -0.25)
        add("pickleball.contact_arm.low", .pickleballOverhead, "armExtensionAtContact", 75, 5)
        add("pickleball.contact_height.low", .pickleballDrive, "contactHeight", 0.08, -0.35)
        add("pickleball.contact_height.high", .pickleballDrive, "lowBallLoad", 0, 1)
        add("pickleball.swing_through.low", .pickleballDrive, "swingThrough", 0, 1)
        add("pickleball.head_stability.high", .pickleballDink, "headTurnEarly", 75, 0)
        add("tennis.finish_height.low", .tennisForehand, "finishHeight", -0.35, 0.25)
        add("tennis.elbow_finish.low", .tennisForehand, "finishElbowLift", 0, 2.3)
        add("tennis.off_hand_reach.low", .tennisForehand, "offReach", 0.1, 0.58)
        add("tennis.spacing.low", .tennisForehand, "contactSpacing", 0.08, 0.38)
        add("tennis.spacing.high", .tennisForehand, "contactSpacing", 0.72, 0.38)
        add("tennis.contact_front.low", .tennisForehand, "contactFront", -0.12, 0.48)
        add("tennis.extension_through.low", .tennisForehand, "extensionThrough", 0, 0.55)
        add("tennis.back_load.high", .tennisForehand, "backLoad", 0.20, -0.23)
        add("tennis.weight_shift.low", .tennisForehand, "weightTransfer", 0, 0.32)
        add("tennis.contact_arm.low@side", .tennisBackhand, "armExtensionAtContact", 80, 5)
        for view in ["front", "back", "side"] {
            t["setup.tennis." + view] = MotionSpec(base: .tripod,
                wrong: ["tripodHeight": 0.35, "tripodDistance": 1],
                correct: ["tripodHeight": view == "back" ? 1.55 : 1.15, "tripodDistance": view == "back" ? 3 : 5])
        }
        for sport in ["golf", "basketball", "tennis", "pickleball"] {
            t["setup." + sport] = MotionSpec(base: .tripod,
                wrong: ["tripodHeight": 0.35, "tripodDistance": 1],
                correct: ["tripodHeight": sport == "golf" ? 0.9 : 1.3, "tripodDistance": sport == "tennis" ? 5 : 3.5])
        }
        return t
    }()
}
