import AVFoundation
import CoreMotion
import FormCore

// Capture configuration, Vision, setup gating, FormEngine and snapshots share one serial queue.
final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let captureSession = AVCaptureSession()
    let queue = DispatchQueue(label: "com.formcoach.camera", qos: .userInitiated)
    var onFrame: ((CameraFrameState) -> Void)?
    var onError: ((String) -> Void)?
    private let detector: PoseDetector
    private let pipeline: PoseSessionPipeline
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private var position: AVCaptureDevice.Position = .front
    private var input: AVCaptureDeviceInput?
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var stopped = false
    private var visionFailed = false
    private let jointCount: Int
    #if DEBUG
    let isReplaying: Bool
    let replayHandedness: Handedness
    private let replaySport: String
    private var replay: ReplayDemoSource?
    var onReplayFinished: (() -> Void)?
    #endif

    init(profiles: Profiles, sport: String, handedness: Handedness, collectPose: Bool) {
        detector = PoseDetector(jointNames: profiles.joints)
        jointCount = profiles.joints.count
        #if DEBUG
        isReplaying = ReplayDemoSource.shouldReplay
        replayHandedness = isReplaying ? (ReplayDemoSource.fixtureHandedness(sport: sport) ?? handedness) : handedness
        #endif
        let engineHandedness: Handedness
        #if DEBUG
        engineHandedness = isReplaying ? replayHandedness : handedness
        #else
        engineHandedness = handedness
        #endif
        pipeline = PoseSessionPipeline(profiles: profiles, sport: sport, handedness: engineHandedness, collectPose: collectPose)
        #if DEBUG
        replaySport = sport
        #endif
        super.init()
        motionQueue.maxConcurrentOperationCount = 1
    }
    func start() {
        queue.async { [weak self] in
            guard let self = self, !self.stopped else { return }
            #if DEBUG
            if self.isReplaying {
                do {
                    let recording = try ReplayDemoRecording.load(sport: self.replaySport, jointCount: self.jointCount)
                    self.pipeline.upright = true
                    let source = ReplayDemoSource(recording: recording, queue: self.queue)
                    source.onFrame = { [weak self] t, joints, aspect in
                        guard let self = self, !self.stopped else { return }
                        self.onFrame?(self.pipeline.processFrame(t: t, joints: joints, aspect: aspect, mirrored: true))
                    }
                    source.onFinished = { [weak self] in self?.onReplayFinished?() }
                    self.replay = source
                    source.start()
                } catch { self.onError?(error.localizedDescription) }
                return
            }
            #endif
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
            guard let self = self, self.configured, !self.stopped, self.pipeline.engineState != .active else { return }
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
                self.pipeline.resetSetup()
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
                self.pipeline.upright = valid
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
            let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
            let joints: [JointObservation?]
            do { joints = try detector.detect(buffer); visionFailed = false }
            catch {
                joints = Array(repeating: nil, count: jointCount)
                if !visionFailed { onError?("Body tracking failed: " + error.localizedDescription); visionFailed = true }
            }
            onFrame?(pipeline.processFrame(t: t, joints: joints, aspect: aspect, mirrored: position == .front))
        }
    }
    func finish() async -> SessionCapture {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                stopped = true
                motion.stopDeviceMotionUpdates()
                if captureSession.isRunning { captureSession.stopRunning() }
                #if DEBUG
                replay?.stop()
                replay = nil
                #endif
                let snapshot = pipeline.finish()
                continuation.resume(returning: snapshot)
            }
        }
    }
    func stop() {
        queue.async { [self] in
            stopped = true
            motion.stopDeviceMotionUpdates()
            if captureSession.isRunning { captureSession.stopRunning() }
            #if DEBUG
            replay?.stop()
            replay = nil
            #endif
            pipeline.discardRecording()
        }
    }
}
