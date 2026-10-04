import Foundation
import CoreVideo
import FormCore

struct MarkerPoint: Equatable { let x: Double; let y: Double }
enum OrangeThresholds {
    static let stride = 4
    static let hueDegrees = 10.0...35.0
    static let saturation = 0.65
    static let value = 0.75
    static let minimumSamples = 3
    static let maximumSamples = 1200
    static let wristRadius = 0.08
}
/// Used only on CameraManager.queue. Pixel sampling, components and wrist history share that queue.
final class OrangeMarkerTracker {
    private let names: [String]
    private let side: String
    private var lastWrist: MarkerPoint?
    private var forearm: MarkerPoint?
    private var lastGoodTime: Double?
    private var mask: [UInt8] = []
    private var work: [Int] = []
    private(set) var implement: MarkerPoint?
    init(names: [String], sport: String, handedness: Handedness) {
        self.names = names
        let dominant = handedness == .left ? "l" : "r"
        side = sport == "golf" ? (dominant == "l" ? "r" : "l") : dominant
    }
    func reset() { lastWrist = nil; forearm = nil; lastGoodTime = nil; implement = nil }
    func detect(_ buffer: CVPixelBuffer) -> [MarkerPoint] {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return [] }
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer,.readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return [] }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let step = OrangeThresholds.stride, columns = (width + step - 1) / step, rows = (height + step - 1) / step
        let bytes = base.assumingMemoryBound(to: UInt8.self), rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        if mask.count != columns * rows { mask = Array(repeating: 0,count: columns * rows) }
        for gy in 0..<rows {
            for gx in 0..<columns {
                let index = gy * columns + gx, pixel = gy * step * rowBytes + gx * step * 4
                let b = Double(bytes[pixel]) / 255, g = Double(bytes[pixel+1]) / 255, r = Double(bytes[pixel+2]) / 255
                let maximum = max(r,max(g,b)), minimum = min(r,min(g,b)), delta = maximum - minimum
                // Orange's red channel is always largest; reject other hue sectors before division.
                guard maximum >= OrangeThresholds.value, maximum == r, delta >= maximum * OrangeThresholds.saturation else {
                    mask[index] = 0; continue
                }
                let hue = 60 * (g-b) / delta
                mask[index] = OrangeThresholds.hueDegrees.contains(hue) ? 1 : 0
            }
        }
        var points: [MarkerPoint] = []
        for seed in mask.indices where mask[seed] == 1 {
            mask[seed] = 0; work.removeAll(keepingCapacity: true); work.append(seed)
            var cursor = 0, sumX = 0, sumY = 0
            while cursor < work.count {
                let i = work[cursor], x = i % columns, y = i / columns
                sumX += x; sumY += y; cursor += 1
                func visit(_ neighbour: Int) {
                    if mask[neighbour] == 1 { mask[neighbour] = 0; work.append(neighbour) }
                }
                if x > 0 { visit(i-1) }; if x+1 < columns { visit(i+1) }
                if y > 0 { visit(i-columns) }; if y+1 < rows { visit(i+columns) }
            }
            if (OrangeThresholds.minimumSamples...OrangeThresholds.maximumSamples).contains(work.count) {
                points.append(MarkerPoint(x: (Double(sumX) / Double(work.count) * Double(step) + 0.5) / Double(width),
                                          y: (Double(sumY) / Double(work.count) * Double(step) + 0.5) / Double(height)))
            }
        }
        return points
    }
    func substitute(joints: [JointObservation?], markers: [MarkerPoint], t: Double) -> [JointObservation?] {
        var result = joints
        func joint(_ name: String) -> JointObservation? {
            guard let i = names.firstIndex(of: name), i < joints.count else { return nil }; return joints[i]
        }
        guard let wristIndex = names.firstIndex(of: side + "_wrist"), wristIndex < joints.count else { return result }
        let wrist = joints[wristIndex], elbow = joint(side + "_elbow")
        if let wrist = wrist, wrist.confidence >= 0.5 {
            lastWrist = MarkerPoint(x: wrist.x,y: wrist.y); lastGoodTime = t
            if let elbow = elbow, elbow.confidence >= 0.5 { forearm = MarkerPoint(x: wrist.x-elbow.x,y: wrist.y-elbow.y) }
        }
        if let lastGoodTime = lastGoodTime, t-lastGoodTime > 1.0 { lastWrist = nil; forearm = nil }
        var targets: [MarkerPoint] = []
        if let lastWrist = lastWrist { targets.append(lastWrist) }
        if let elbow = elbow, elbow.confidence >= 0.5, let vector = forearm {
            targets.append(MarkerPoint(x: elbow.x+vector.x,y: elbow.y+vector.y))
        }
        func distance(_ a: MarkerPoint, _ b: MarkerPoint) -> Double { hypot(a.x-b.x,a.y-b.y) }
        if (wrist?.confidence ?? 0) < 0.5,
           let marker = markers.min(by: { a,b in
               (targets.map { distance(a,$0) }.min() ?? .infinity) < (targets.map { distance(b,$0) }.min() ?? .infinity)
           }), targets.contains(where: { distance(marker,$0) <= OrangeThresholds.wristRadius }) {
            result[wristIndex] = JointObservation(x: marker.x,y: marker.y,confidence: 0.6)
        }
        implement = nil
        if let elbow = elbow, let vector = forearm {
            let length = hypot(vector.x,vector.y)
            if length > 0.001 {
                let candidates = markers.filter { ($0.x-elbow.x)*vector.x + ($0.y-elbow.y)*vector.y > length*length }
                implement = candidates.max { a,b in
                    (a.x-elbow.x)*vector.x + (a.y-elbow.y)*vector.y < (b.x-elbow.x)*vector.x + (b.y-elbow.y)*vector.y
                }
            }
        }
        return result
    }
}
