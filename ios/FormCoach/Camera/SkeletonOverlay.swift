import SwiftUI
import FormCore

@MainActor
struct SkeletonOverlay: View {
    let joints: [JointObservation?]
    let names: [String]
    let aspect: Double
    let mirrored: Bool
    let markers: [MarkerPoint]
    private let bones = [
        ("nose", "l_shoulder"), ("nose", "r_shoulder"), ("l_shoulder", "r_shoulder"),
        ("l_shoulder", "l_elbow"), ("l_elbow", "l_wrist"), ("r_shoulder", "r_elbow"), ("r_elbow", "r_wrist"),
        ("l_shoulder", "l_hip"), ("r_shoulder", "r_hip"), ("l_hip", "r_hip"),
        ("l_hip", "l_knee"), ("l_knee", "l_ankle"), ("r_hip", "r_knee"), ("r_knee", "r_ankle")
    ]
    init(joints: [JointObservation?], names: [String], aspect: Double, mirrored: Bool, markers: [MarkerPoint] = []) {
        self.joints = joints
        self.names = names
        self.aspect = aspect
        self.mirrored = mirrored
        self.markers = markers
    }
    var body: some View {
        Canvas { context, size in
            let ratio = CGFloat(max(0.01, aspect))
            let width = min(size.width, size.height * ratio)
            let height = width / ratio
            let offset = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
            func point(_ name: String) -> CGPoint? {
                guard let index = names.firstIndex(of: name), index < joints.count,
                      let joint = joints[index], joint.confidence >= 0.3 else { return nil }
                return CGPoint(x: offset.x + CGFloat(mirrored ? 1 - joint.x : joint.x) * width,
                               y: offset.y + CGFloat(joint.y) * height)
            }
            for (start, end) in bones {
                guard let a = point(start), let b = point(end) else { continue }
                var path = Path()
                path.move(to: a); path.addLine(to: b)
                context.stroke(path, with: .color(.black.opacity(0.8)), lineWidth: 7)
                context.stroke(path, with: .color(.cyan), lineWidth: 3)
            }
            for marker in markers {
                let p = CGPoint(x: offset.x + CGFloat(mirrored ? 1-marker.x : marker.x)*width, y: offset.y + CGFloat(marker.y)*height)
                context.stroke(Path(ellipseIn: CGRect(x: p.x-12,y: p.y-12,width: 24,height: 24)), with: .color(.orange), lineWidth: 3)
            }
            for name in names {
                guard let p = point(name) else { continue }
                let circle = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                context.fill(circle, with: .color(.white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
