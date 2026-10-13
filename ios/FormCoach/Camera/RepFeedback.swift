import UIKit
import CoreImage
import FormCore

/// Immutable, memory-only frames. Images never enter the session upload or pose recording.
struct FeedbackFrame {
    let t: Double
    let pose: [String: Point]
    let torso: Double
    let aspect: Double
    let mirrored: Bool
    let imageData: Data?
    var image: CGImage? { imageData.flatMap { UIImage(data:$0)?.cgImage } }
}
struct RepCard: Identifiable {
    var id: Int { index }
    let index: Int
    let sport: String
    let rep: Rep
    let cue: String
    let shortLabel: String
    let metric: String?
    let frame: FeedbackFrame
    let corrected: [String: Point]?
    /// The whole rep as recorded (red) and the same motion with the fix applied (green), for the replay.
    var motion: [MotionFrame] = []
}
struct MotionFrame {
    let t: Double
    let pose: [String: Point]
    let fix: [String: Point]?
}

/// Port of fixMotion in web/src/app/fixcard.ts: the recorded motion with the key-moment fix eased in and
/// out. The correction's joint offsets grow from nothing at the start of the rep to full at the key moment,
/// then ease off by the end, so a fix at the set point does not bend the arm at release.
func fixMotion(_ frames: [(t: Double, pose: [String: Point])], keyPose: [String: Point]?, ghost: [String: Point]?,
               tStart: Double, keyT: Double, tEnd: Double) -> [MotionFrame] {
    func smooth(_ u: Double) -> Double { let c = max(0, min(1, u)); return c * c * (3 - 2 * c) }
    return frames.map { f in
        guard let keyPose = keyPose, let ghost = ghost else { return MotionFrame(t: f.t, pose: f.pose, fix: nil) }
        let w = f.t <= keyT ? (keyT > tStart ? smooth((f.t - tStart) / (keyT - tStart)) : 1)
                            : (tEnd > keyT ? 1 - smooth((f.t - keyT) / (tEnd - keyT)) : 1)
        var fix: [String: Point] = [:]
        for (k, p) in f.pose {
            if let g = ghost[k], let kp = keyPose[k] { fix[k] = Point(x: p.x + w * (g.x - kp.x), y: p.y + w * (g.y - kp.y)) }
            else { fix[k] = p }
        }
        return MotionFrame(t: f.t, pose: f.pose, fix: fix)
    }
}

final class FeedbackBuffer {
    private(set) var frames: [FeedbackFrame] = []
    private var poses: [FeedbackFrame] = []
    private var lastImageTime = -Double.infinity
    private let context = CIContext(options: [.cacheIntermediates: false])
    func append(t: Double, joints: [JointObservation?], names: [String], aspect: Double,
                mirrored: Bool, buffer: CVPixelBuffer? = nil) {
        guard t - lastImageTime >= 0.095 else { return }
        lastImageTime = t
        var pose: [String: Point] = [:]
        for (name,joint) in zip(names,joints) {
            if let j=joint, j.confidence >= 0.3 { pose[name]=Point(x:j.x*aspect,y:j.y) }
        }
        func middle(_ a: String,_ b: String) -> Point? {
            guard let a=pose[a],let b=pose[b] else { return nil }
            return Point(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
        }
        let torso: Double
        if let shoulder=middle("l_shoulder","r_shoulder"),let hip=middle("l_hip","r_hip") { torso=max(1e-6,hypot(shoulder.x-hip.x,shoulder.y-hip.y)) }
        else { torso=0.2 }
        var imageData: Data?
        if let buffer=buffer {
            let input=CIImage(cvPixelBuffer:buffer)
            let scale=min(1,360/input.extent.height)
            let scaled=input.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            if let image=context.createCGImage(scaled,from:scaled.extent) { imageData=UIImage(cgImage:image).jpegData(compressionQuality:0.6) }
        }
        frames.append(FeedbackFrame(t:t,pose:pose,torso:torso,aspect:aspect,mirrored:mirrored,imageData:imageData))
        frames.removeAll { $0.t < t-2.1 }
        // References such as address can precede the image window; retain tiny pose metadata only.
        poses.append(FeedbackFrame(t:t,pose:pose,torso:torso,aspect:aspect,mirrored:mirrored,imageData:nil))
        poses.removeAll { $0.t < t-8 }
    }
    func nearest(_ time: Double) -> FeedbackFrame? { frames.min { abs($0.t-time) < abs($1.t-time) } }
    func card(rep: Rep,index: Int,sport: String,profile: SportProfile,dominant: String) -> RepCard? {
        guard let first=rep.cues.first else { return nil }
        // Prefer a rule we can draw, retaining a plain skeleton for timing/rotation cues.
        let cue=rep.cues.first { cue in
            profile.metric(forCue:cue).flatMap { correctionEvent(analyzer:profile.analyzer,metric:$0.id) } != nil
        } ?? first
        let spec=profile.metric(forCue:cue)
        let rule=spec.flatMap { correctionEvent(analyzer:profile.analyzer,metric:$0.id) }
        let eventTime=rule.map { event in event.event == "start" ? rep.tStart : (event.event == "end" ? rep.tEnd : rep.events[event.event] ?? rep.tEnd) } ?? rep.tEnd
        guard let frame=nearest(eventTime) else { return nil }
        let refTime=rule?.ref.map { $0 == "start" ? rep.tStart : ($0 == "end" ? rep.tEnd : rep.events[$0] ?? rep.tStart) }
        let reference=refTime.flatMap { time in poses.min { abs($0.t-time) < abs($1.t-time) }?.pose }
        let correction=spec.flatMap { metric in targetFor(metric,rep.type).flatMap { target in
            correctedPose(analyzer:profile.analyzer,metric:metric.id,target:target.mean,pose:frame.pose,
                          ref:reference,torso:frame.torso,dominant:dominant,repType:rep.type)
        } }
        let recorded=poses.filter { $0.t >= rep.tStart-0.05 && $0.t <= rep.tEnd+0.05 && $0.pose.count >= 8 }.map { (t:$0.t,pose:$0.pose) }
        let motion=fixMotion(recorded,keyPose:correction == nil ? nil : frame.pose,ghost:correction,
                             tStart:rep.tStart,keyT:frame.t,tEnd:rep.tEnd)
        return RepCard(index:index,sport:sport,rep:rep,cue:cue,shortLabel:profile.shortLabel(forCue:cue),
                       metric:spec?.id,frame:frame,corrected:correction,motion:motion)
    }
    func clear() { frames.removeAll(); poses.removeAll(); lastImageTime = -Double.infinity }
}

/// Shared by the glance card, detail view and the on-device replay renderer.
enum FeedbackDrawing {
    static let bones=[("l_shoulder","r_shoulder"),("l_shoulder","l_elbow"),("l_elbow","l_wrist"),("r_shoulder","r_elbow"),("r_elbow","r_wrist"),("l_shoulder","l_hip"),("r_shoulder","r_hip"),("l_hip","r_hip"),("l_hip","l_knee"),("l_knee","l_ankle"),("r_hip","r_knee"),("r_knee","r_ankle"),("nose","l_shoulder"),("nose","r_shoulder")]
    static func draw(frame: FeedbackFrame,corrected: [String: Point]?,size: CGSize,context: CGContext,ghostAlpha: CGFloat = 0.65,moveReference: [String:Point]? = nil) {
        func pixel(_ p: Point) -> CGPoint { CGPoint(x:p.x/frame.aspect*size.width,y:p.y*size.height) }
        func line(_ a: Point,_ b: Point) { context.move(to:pixel(a)); context.addLine(to:pixel(b)); context.strokePath() }
        context.setLineCap(.round); context.setLineWidth(max(1.5,size.height/160))
        context.setStrokeColor(UIColor.white.cgColor); context.setFillColor(UIColor.white.cgColor)
        for (a,b) in bones { if let a=frame.pose[a],let b=frame.pose[b] { line(a,b) } }
        let radius=max(2,size.height/100)
        for p in frame.pose.values { let c=pixel(p); context.fillEllipse(in:CGRect(x:c.x-radius,y:c.y-radius,width:radius*2,height:radius*2)) }
        guard let corrected=corrected else { return }
        let source=moveReference ?? frame.pose
        let moved=Set(corrected.compactMap { name,p in source[name].map { hypot(p.x-$0.x,p.y-$0.y)>0.002 ? name : nil } ?? nil })
        let cyan=UIColor.cyan.withAlphaComponent(ghostAlpha)
        context.setStrokeColor(cyan.cgColor); context.setFillColor(cyan.cgColor)
        context.setShadow(offset:.zero,blur:4,color:cyan.cgColor)
        for (a,b) in bones where moved.contains(a) || moved.contains(b) { if let a=corrected[a],let b=corrected[b] { line(a,b) } }
        context.setShadow(offset:.zero,blur:0,color:nil)
        for name in moved {
            guard let a=source[name],let b=corrected[name] else { continue }
            let start=pixel(a),end=pixel(b), angle=atan2(end.y-start.y,end.x-start.x), head=max(4,size.height/65)
            line(a,b)
            context.move(to:CGPoint(x:end.x-head*cos(angle-0.5),y:end.y-head*sin(angle-0.5)))
            context.addLine(to:end); context.addLine(to:CGPoint(x:end.x-head*cos(angle+0.5),y:end.y-head*sin(angle+0.5))); context.strokePath()
            context.fillEllipse(in:CGRect(x:end.x-radius*1.3,y:end.y-radius*1.3,width:radius*2.6,height:radius*2.6))
        }
    }
    static func image(_ card: RepCard,height: CGFloat = 360) -> UIImage {
        let size=CGSize(width:height*card.frame.aspect,height:height)
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        return UIGraphicsImageRenderer(size:size,format:format).image { renderer in
            UIColor(white:0.06,alpha:1).setFill(); renderer.fill(CGRect(origin:.zero,size:size))
            if let image=card.frame.image { UIImage(cgImage:image).draw(in:CGRect(origin:.zero,size:size)) }
            draw(frame:card.frame,corrected:card.corrected,size:size,context:renderer.cgContext)
        }
    }
}
