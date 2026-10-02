import AVFoundation
import Vision
import FormCore

final class PoseDetector {
    private let request = VNDetectHumanBodyPoseRequest()
    private let names: [String]
    private let mapping: [String: VNHumanBodyPoseObservation.JointName] = [
        "nose": .nose, "l_shoulder": .leftShoulder, "r_shoulder": .rightShoulder,
        "l_elbow": .leftElbow, "r_elbow": .rightElbow, "l_wrist": .leftWrist, "r_wrist": .rightWrist,
        "l_hip": .leftHip, "r_hip": .rightHip, "l_knee": .leftKnee, "r_knee": .rightKnee,
        "l_ankle": .leftAnkle, "r_ankle": .rightAnkle
    ]
    init(jointNames: [String]) { names = jointNames }
    func detect(_ buffer: CVPixelBuffer) throws -> [JointObservation?] {
        // The video data connection physically rotates buffers into portrait; no additional rotation here.
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        // Prefer the largest confidently visible body, usually the athlete closest to the tripod.
        let candidates = try observations.map { try $0.recognizedPoints(.all) }
        let points = candidates.max { bodyArea($0) < bodyArea($1) }
        return names.map { name in
            guard let joint = mapping[name], let point = points?[joint], point.confidence > 0 else { return nil }
            return JointObservation(x: Double(point.x), y: 1 - Double(point.y), confidence: Double(point.confidence))
        }
    }
    private func bodyArea(_ points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> CGFloat {
        let visible = points.values.filter { $0.confidence >= 0.3 }
        guard let minX = visible.map(\.x).min(), let maxX = visible.map(\.x).max(),
              let minY = visible.map(\.y).min(), let maxY = visible.map(\.y).max() else { return 0 }
        return (maxX - minX) * (maxY - minY)
    }
}
