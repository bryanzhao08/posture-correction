import SwiftUI
import UIKit
import AVFoundation
import AudioToolbox
import FormCore
import Darwin

@MainActor
final class SessionController: ObservableObject {
    let camera: CameraManager
    let sport: Sport
    let profile: SportProfile
    let jointNames: [String]
    private let handedness: Handedness
    private let startedAt = Date()
    private let startedUptime = ProcessInfo.processInfo.systemUptime
    private let clientID = UUID().uuidString
    private let speaker = AVSpeechSynthesizer()
    private var previousIdleTimerDisabled = false
    private var awake = false
    private var requestedStart = false
    private var finishing = false
    private var disposed = false
    private var snapshot: SessionCapture?
    private var duration: Double = 0
    @Published var frame: CameraFrameState?
    @Published var error: String?
    @Published var spokenCues: Bool
    @Published private(set) var isFinished = false
    @Published private(set) var cameraDenied = false

    init(profiles: Profiles, sport: Sport, profile: SportProfile, handedness: Handedness,
         spokenCues: Bool, sharePose: Bool) {
        self.sport = sport
        self.profile = profile
        self.handedness = handedness
        self.spokenCues = spokenCues
        jointNames = profiles.joints
        camera = CameraManager(profiles: profiles, sport: sport.rawValue, handedness: handedness, collectPose: sharePose)
        camera.onFrame = { [weak self] frame in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isFinished, !self.finishing else { return }
                self.frame = frame
                for rep in frame.countedReps { self.feedback(rep) }
            }
        }
        camera.onError = { [weak self] message in
            Task { @MainActor [weak self] in self?.error = message }
        }
    }
    func start() async {
        guard !requestedStart, !isFinished, !disposed else { return }
        requestedStart = true
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard !isFinished, !finishing, !disposed else { return }
        guard allowed else {
            cameraDenied = true
            error = "Camera access is required. Enable it in iPhone Settings to track your practice."
            return
        }
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        awake = true
        camera.start()
    }
    private func feedback(_ rep: Rep) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AudioServicesPlaySystemSound(1057)
        if spokenCues, let cue = rep.cues.first, !speaker.isSpeaking {
            let utterance = AVSpeechUtterance(string: cue)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            speaker.speak(utterance)
        }
    }
    func stopSpeech() { speaker.stopSpeaking(at: .immediate) }
    func finish() async {
        guard !finishing, !isFinished else { return }
        finishing = true
        duration = max(0, ProcessInfo.processInfo.systemUptime - startedUptime)
        snapshot = await camera.finish()
        stopSpeech()
        restoreAwake()
        isFinished = true
        finishing = false
    }
    func save(to state: AppState) throws -> String {
        guard let snapshot = snapshot else { throw APIError(message: "The session is still finishing.") }
        let payload = SessionIn(clientID: clientID, sport: sport.rawValue, handedness: handedness,
            startedAt: Display.timestamp(startedAt), durationS: duration, summary: snapshot.summary,
            reps: snapshot.reps, appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            device: Self.deviceIdentifier())
        return try state.saveSession(payload, recording: snapshot.recording)
    }
    func stop() { disposed = true; camera.stop(); stopSpeech(); restoreAwake() }
    private func restoreAwake() {
        if awake { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled; awake = false }
    }
    private static func deviceIdentifier() -> String {
        var info = utsname()
        uname(&info)
        return Mirror(reflecting: info.machine).children.reduce(into: "") { value, element in
            if let byte = element.value as? Int8, byte != 0 { value.append(Character(UnicodeScalar(UInt8(bitPattern: byte)))) }
        }
    }
    var stateLabel: String {
        guard let frame = frame else { return "No person" }
        if !frame.started {
            return frame.joints.contains(where: { ($0?.confidence ?? 0) >= 0.3 }) ? "Get set" : "No person"
        }
        switch frame.engineState {
        case .noPerson: return "No person"
        case .moving: return "Get set"
        case .ready: return "Ready"
        case .active: return "Swinging"
        }
    }
}
