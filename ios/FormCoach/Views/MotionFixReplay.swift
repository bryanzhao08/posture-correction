import SwiftUI
import FormCore

/// Loops the rep at half speed: red is what you did (your recorded skeleton), green is the same motion
/// with the fix applied. Framed on the player, so it reads the same however far away the phone was.
struct MotionFixReplay: View {
    let card: RepCard
    private let slow = 2.0
    private let pause = 0.8
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let m = card.motion
                guard m.count > 1 else { return }
                let t0 = m[0].t, dur = m[m.count - 1].t - t0
                let el = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: dur * slow + pause)
                let t = t0 + min(dur, el / slow)
                var i = 0
                while i < m.count - 1 && m[i + 1].t <= t { i += 1 }
                let a = m[i], b = m[min(i + 1, m.count - 1)]
                let u = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
                func lerp(_ p: [String: Point], _ q: [String: Point]) -> [String: Point] {
                    p.reduce(into: [:]) { o, kv in
                        let (k, v) = kv
                        o[k] = q[k].map { Point(x: v.x + u * ($0.x - v.x), y: v.y + u * ($0.y - v.y)) } ?? v
                    }
                }
                let all = m.flatMap { Array($0.pose.values) + Array(($0.fix ?? [:]).values) }
                let minX = all.map(\.x).min()!, maxX = all.map(\.x).max()!
                let minY = all.map(\.y).min()!, maxY = all.map(\.y).max()!
                let span = max((maxX - minX) / size.width, (maxY - minY) / size.height) * 1.25
                let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
                func px(_ p: Point) -> CGPoint {
                    let x = size.width / 2 + (p.x - cx) / span
                    return CGPoint(x: card.frame.mirrored ? size.width - x : x, y: size.height / 2 + (p.y - cy) / span)
                }
                let unit = max(2, size.height / 140)
                func skeleton(_ pose: [String: Point], _ color: Color, _ width: CGFloat) {
                    var path = Path()
                    for (a, b) in FeedbackDrawing.bones {
                        guard let p = pose[a], let q = pose[b] else { continue }
                        path.move(to: px(p)); path.addLine(to: px(q))
                    }
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    for (name, p) in pose {
                        let r = (name == "nose" ? 2.2 : 1.6) * unit, c = px(p)
                        context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
                    }
                }
                if let fa = a.fix, let fb = b.fix {
                    skeleton(lerp(fa, fb), Color(red: 0.24, green: 0.86, blue: 0.52), unit * 1.8)
                }
                skeleton(lerp(a.pose, b.pose), Color(red: 1, green: 0.35, blue: 0.37), unit * 1.4)
            }
        }
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityLabel("Replay of your rep: red is what you did, green is the corrected motion")
        .accessibilityIdentifier("rep.feedback.motion")
    }
}
