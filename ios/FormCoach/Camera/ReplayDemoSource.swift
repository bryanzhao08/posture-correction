#if DEBUG
import Foundation
import AVFoundation
import FormCore

struct ReplayDemoRecording: Decodable {
    let sport: String
    let handedness: Handedness
    let fps: Double
    let aspect: Double
    let frames: [PoseFrame]
    enum CodingKeys: String, CodingKey { case sport, handedness, fps, aspect, frames }

    static func load(sport: String, jointCount: Int) throws -> ReplayDemoRecording {
        guard let url = Bundle.main.url(forResource: sport + "_demo", withExtension: "json") else {
            throw ReplayDemoError(message: "The bundled \(sport) demo recording is missing.")
        }
        let recording = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try recording.validate(sport: sport, jointCount: jointCount)
        return recording
    }
    func validate(sport: String, jointCount: Int) throws {
        guard self.sport == sport, fps.isFinite, fps > 0, fps <= 240,
              aspect.isFinite, aspect > 0, !frames.isEmpty else {
            throw ReplayDemoError(message: "The demo recording has invalid session metadata.")
        }
        var previous = -Double.infinity
        for frame in frames {
            guard frame.t.isFinite, frame.t > previous, frame.j.count == jointCount,
                  frame.j.allSatisfy({ $0.count == 3 && $0.allSatisfy(\.isFinite) && (0...1).contains($0[2]) }) else {
                throw ReplayDemoError(message: "The demo recording has invalid pose frames.")
            }
            previous = frame.t
        }
    }
}
struct ReplayDemoError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// Timer and callbacks are confined to CameraManager's queue, just like live capture output.
final class ReplayDemoSource {
    private let recording: ReplayDemoRecording
    private let queue: DispatchQueue
    private let timeline: [PoseFrame]
    private var timer: DispatchSourceTimer?
    private var startTime: DispatchTime?
    private var nextIndex = 0
    private var stopped = false
    var onFrame: ((Double, [JointObservation?], Double) -> Void)?
    var onFinished: (() -> Void)?

    static var shouldReplay: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return UserDefaults.standard.bool(forKey: "debugReplayDemoSession")
            || AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) == nil
        #endif
    }
    static func fixtureHandedness(sport: String) -> Handedness? {
        // Fixtures are anatomical recordings; use their handedness for both analysis and uploads.
        try? ReplayDemoRecording.load(sport: sport, jointCount: 13).handedness
    }
    init(recording: ReplayDemoRecording, queue: DispatchQueue) {
        self.recording = recording
        self.queue = queue
        // Fixtures begin moving before 3 seconds. Show their first pose during setup without
        // shifting any recorded timestamps or dropping any of their real motion frames.
        let first = recording.frames[0]
        let preRollCount = Int(ceil(3 * recording.fps))
        let preRoll = (0..<preRollCount).map {
            PoseFrame(t: first.t - 3 + Double($0) / recording.fps, j: first.j)
        }
        timeline = preRoll + recording.frames
    }
    func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !stopped, timer == nil, startTime == nil else { return }
        startTime = .now()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .nanoseconds(max(1, Int(1_000_000_000 / recording.fps))),
                        leeway: .milliseconds(2))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }
    private func tick() {
        guard !stopped, let start = startTime, let first = timeline.first else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        // Catch up without dropping recorded poses if processing briefly runs behind real time.
        while !stopped, nextIndex < timeline.count, timeline[nextIndex].t - first.t <= elapsed {
            let frame = timeline[nextIndex]
            nextIndex += 1
            let joints: [JointObservation?] = frame.j.map {
                $0[2] > 0 ? JointObservation(x: $0[0], y: $0[1], confidence: $0[2]) : nil
            }
            onFrame?(frame.t, joints, recording.aspect)
        }
        if !stopped, nextIndex == timeline.count {
            stop()
            // Do not clear the last frame or finish the session: the normal End button saves it.
            onFinished?()
        }
    }
    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        stopped = true
        timer?.cancel()
        timer = nil
    }
}
#endif
