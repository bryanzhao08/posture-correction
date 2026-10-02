import AVFoundation
import CoreMotion
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
}
struct SessionCapture {
    let summary: SessionSummary
    let reps: [Rep]
    let recording: Recording?
}

// Capture configuration, Vision, setup gating, FormEngine and snapshots share one serial queue.
final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    let queue = DispatchQueue(label: "com.formcoach.camera", qos: .userInitiated)
    var onFrame: ((CameraFrameState) -> Void)?
    var onError: ((String) -> Void)?
    private let detector: PoseDetector
    private let engine: FormEngine
    private let sport: String
    private let handedness: Handedness
    private let jointNames: [String]
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var upright = false
    private var position: AVCaptureDevice.Position = .front
    private var input: AVCaptureDeviceInput?
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var stopped = false
    private var countingStarted = false
    private var hasStartedCounting = false
    private var setupSince: Double?
    private var aspect = 9.0 / 16.0
    private var lastRep: Rep?
    private var frames: [PoseFrame] = []
    private let collectPose: Bool
    private var visionFailed = false

    init(profiles: Profiles, sport: String, handedness: Handedness, collectPose: Bool) {
        self.sport = sport
        self.handedness = handedness
        jointNames = profiles.joints
        detector = PoseDetector(jointNames: profiles.joints)
        engine = FormEngine(profiles: profiles, sport: sport, handedness: handedness)
        self.collectPose = collectPose
        super.init()
        motionQueue.maxConcurrentOperationCount = 1
    }
    func start() {
        queue.async { [weak self] in
            guard let self = self, !self.stopped else { return }
            do {
                if !self.configured { try self.configure() }
                self.startMotion()
                if !self.captureSession.isRunning { self.captureSession.startRunning() }
            } catch { self.onError?(error.localizedDescription) }
        }
    }
    private func configure() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.sessionPreset = .hd1280x720
        let newInput = try cameraInput(position)
        guard captureSession.canAddInput(newInput) else { throw APIError(message: "Cannot connect to the camera.") }
        captureSession.addInput(newInput)
        input = newInput
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard captureSession.canAddOutput(output) else { throw APIError(message: "Cannot read camera frames.") }
        captureSession.addOutput(output)
        try orientOutput()
        configured = true
    }
    private func cameraInput(_ position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw APIError(message: "This camera is unavailable on this device.")
        }
        return try AVCaptureDeviceInput(device: device)
    }
    private func orientOutput() throws {
        guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) else {
            throw APIError(message: "This camera cannot provide portrait frames.")
        }
        connection.videoRotationAngle = 90
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false // Preserve Vision's anatomical left/right.
        }
    }
    func switchCamera() {
        queue.async { [weak self] in
            guard let self = self, self.configured, !self.stopped, self.engine.state != .active else { return }
            let next: AVCaptureDevice.Position = self.position == .front ? .back : .front
            do {
                let replacement = try self.cameraInput(next)
                self.captureSession.beginConfiguration()
                if let old = self.input { self.captureSession.removeInput(old) }
                guard self.captureSession.canAddInput(replacement) else {
                    if let old = self.input, self.captureSession.canAddInput(old) { self.captureSession.addInput(old) }
                    self.captureSession.commitConfiguration()
                    throw APIError(message: "Cannot switch cameras.")
                }
                self.captureSession.addInput(replacement)
                self.input = replacement
                self.position = next
                do { try self.orientOutput() }
                catch { self.captureSession.commitConfiguration(); throw error }
                self.captureSession.commitConfiguration()
                self.setupSince = nil
                self.countingStarted = false
            } catch { self.onError?(error.localizedDescription) }
        }
    }
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else {
            onError?("Motion sensing is unavailable. Use an iPhone with motion sensors to check tripod alignment.")
            return
        }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self else { return }
            let valid = data.map {
                $0.gravity.y < -0.8 && abs($0.gravity.x) < 0.25 && abs($0.gravity.z) < 0.55
            } ?? false
            self.queue.async {
                self.upright = valid
                if let error = error { self.onError?(error.localizedDescription) }
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !stopped, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard t.isFinite else { return }
            aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
            let joints: [JointObservation?]
            do { joints = try detector.detect(buffer); visionFailed = false }
            catch {
                joints = Array(repeating: nil, count: jointNames.count)
                if !visionFailed { onError?("Body tracking failed: " + error.localizedDescription); visionFailed = true }
            }
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
                    }))
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
            onFrame?(CameraFrameState(joints: joints, aspect: aspect, mirrored: position == .front,
                setupMessage: countingStarted ? nil : setup, countdown: countdown, started: countingStarted,
                engineState: engine.state, repCount: engine.reps.count, lastRep: lastRep, countedReps: counted))
        }
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
    func finish() async -> SessionCapture {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopped = true
                motion.stopDeviceMotionUpdates()
                if captureSession.isRunning { captureSession.stopRunning() }
                let recording = collectPose && !frames.isEmpty
                    ? Recording(sport: sport, handedness: handedness, aspect: aspect, frames: frames) : nil
                let snapshot = SessionCapture(summary: engine.summary(), reps: engine.reps, recording: recording)
                frames.removeAll()
                continuation.resume(returning: snapshot)
            }
        }
    }
    func stop() {
        queue.async { [self] in
            stopped = true
            motion.stopDeviceMotionUpdates()
            if captureSession.isRunning { captureSession.stopRunning() }
            frames.removeAll()
        }
    }
}
