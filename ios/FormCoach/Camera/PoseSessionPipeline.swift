import Foundation
import FormCore

struct CameraFrameState {
    let joints: [JointObservation?]
    let aspect: Double
    let mirrored: Bool
    let setupMessage: String?
    let countdown: Int?
    let started: Bool
    let engineState: EngineState
    let repCount: Int
    let lastRep: Rep?
    let countedReps: [Rep]
    let markers: [MarkerPoint]
}
struct SessionCapture {
    let summary: SessionSummary
    let reps: [Rep]
    let recording: Recording?
}

// All callers own this object on their source's serial queue. Counting/scoring stay in FormCore.
final class PoseSessionPipeline {
    private let engine: FormEngine
    private let sport: String
    private let handedness: Handedness
    private let jointNames: [String]
    private let collectPose: Bool
    private var countingStarted = false
    private var hasStartedCounting = false
    private var setupSince: Double?
    private var aspect = 9.0 / 16.0
    private var lastRep: Rep?
    private var frames: [PoseFrame] = []
    var upright = false
    var engineState: EngineState { engine.state }

    init(profiles: Profiles, sport: String, handedness: Handedness, collectPose: Bool) {
        self.sport = sport
        self.handedness = handedness
        self.jointNames = profiles.joints
        self.collectPose = collectPose
        engine = FormEngine(profiles: profiles, sport: sport, handedness: handedness)
    }
    func resetSetup() { setupSince = nil; countingStarted = false }
    func processFrame(t: Double, joints: [JointObservation?], aspect: Double, mirrored: Bool, markers: [MarkerPoint] = []) -> CameraFrameState {
        self.aspect = aspect
        let setup = setupMessage(joints)
        var countdown: Int?
        if !countingStarted {
            if setup == nil {
                if setupSince == nil { setupSince = t }
                let elapsed = t - (setupSince ?? t)
                if elapsed >= 3 { countingStarted = true; hasStartedCounting = true }
                else { countdown = max(1, 3 - Int(elapsed)) }
            } else { setupSince = nil }
        }
        var counted: [Rep] = []
        if countingStarted {
            if collectPose {
                frames.append(PoseFrame(t: t, j: joints.map { joint in
                    joint.map { [$0.x, $0.y, $0.confidence] } ?? [0, 0, 0]
                }, m: markers.isEmpty ? nil : markers.map { [$0.x, $0.y] }))
            }
        }
        if hasStartedCounting {
            // During a camera switch setup check, missing observations disarm the engine using real frame time.
            let engineJoints = countingStarted ? joints : Array<JointObservation?>(repeating: nil, count: jointNames.count)
            // The app never decides what a rep is; FormCore owns all counting and rejection logic.
            for event in engine.push(t: t, joints: engineJoints, aspect: aspect) {
                if case .rep(let rep) = event { lastRep = rep; counted.append(rep) }
            }
        }
        return CameraFrameState(joints: joints, aspect: aspect, mirrored: mirrored,
            setupMessage: countingStarted ? nil : setup, countdown: countdown, started: countingStarted,
            engineState: engine.state, repCount: engine.reps.count, lastRep: lastRep, countedReps: counted, markers: markers)
    }
    private func setupMessage(_ joints: [JointObservation?]) -> String? {
        func point(_ name: String) -> JointObservation? {
            guard let index = jointNames.firstIndex(of: name), index < joints.count,
                  let joint = joints[index], joint.confidence >= 0.3,
                  (0.02...0.98).contains(joint.x), (0.02...0.98).contains(joint.y) else { return nil }
            return joint
        }
        guard let nose = point("nose"), let left = point("l_ankle"), let right = point("r_ankle") else {
            return "Step into view with your face and both feet visible."
        }
        let height = max(left.y, right.y) - nose.y
        guard height >= 0.45 else { return "Move closer. Your body should fill at least 45% of the frame." }
        guard height <= 0.90 else { return "Move back. Leave room above your head and below your feet." }
        guard upright else { return "Keep the phone upright and level on the tripod." }
        return nil
    }
    func finish() -> SessionCapture {
        let recording = collectPose && !frames.isEmpty
            ? Recording(sport: sport, handedness: handedness, aspect: aspect, frames: frames) : nil
        let snapshot = SessionCapture(summary: engine.summary(), reps: engine.reps, recording: recording)
        frames.removeAll()
        return snapshot
    }
    func discardRecording() { frames.removeAll() }
}
