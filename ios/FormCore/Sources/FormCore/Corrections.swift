import Foundation

/// Port of corrections.py. Coordinates are image-height units with y pointing down.
public func correctionEvent(analyzer: String, metric: String) -> (event: String, ref: String?)? {
    let rules: [String: [String: (String, String?)]] = [
        "golf": ["lead_arm_top": ("top", nil), "head_sway": ("impact", "address"), "head_lift": ("impact", "address"), "hip_sway": ("top", "address"), "finish_balance": ("finish", nil)],
        "basketball": ["elbow_extension": ("release", nil), "elbow_flare": ("set", nil), "release_height": ("release", nil), "arm_verticality": ("release", nil), "guide_hand_gap": ("release", nil), "lateral_drift": ("end", "start")],
        "racket": ["finish_height": ("follow_through", nil), "elbow_finish": ("follow_through", nil), "off_hand_reach": ("backswing", nil), "spacing": ("contact", nil), "contact_front": ("contact", "backswing"), "back_load": ("backswing", "contact"), "weight_shift": ("contact", "backswing"), "contact_arm": ("contact", nil), "contact_height": ("contact", nil), "stance_height": ("contact", nil), "ready_height": ("start", nil), "backswing_size": ("backswing", nil)]
    ]
    return rules[analyzer]?[metric]
}

private enum CorrectionMath {
    enum Missing: Error { case joint }
    static let upper = ["nose", "l_shoulder", "r_shoulder", "l_elbow", "r_elbow", "l_wrist", "r_wrist"]
    static func get(_ p: [String: Point]?, _ name: String) throws -> Point {
        guard let point = p?[name] else { throw Missing.joint }; return point
    }
    static func length(_ a: Point, _ b: Point) -> Double { hypot(a.x-b.x, a.y-b.y) }
    static func mid(_ a: Point, _ b: Point) -> Point { Point(x: (a.x+b.x)/2, y: (a.y+b.y)/2) }
    static func hips(_ p: [String: Point]?) throws -> Point { try mid(get(p,"l_hip"), get(p,"r_hip")) }
    static func shift(_ p: inout [String: Point], _ names: [String], _ dx: Double, _ dy: Double) {
        for n in names { if let v = p[n] { p[n] = Point(x:v.x+dx, y:v.y+dy) } }
    }
    static func ik(_ root: Point, _ goal: Point, _ l1: Double, _ l2: Double, _ bend: Point) -> (Point, Point) {
        var target=goal, dx=goal.x-root.x, dy=goal.y-root.y, d=hypot(goal.x-root.x, goal.y-root.y)
        let reach=(l1+l2)*0.999
        if d < 1e-9 { return (bend,target) }
        if d > reach { target=Point(x:root.x+dx/d*reach,y:root.y+dy/d*reach); dx=target.x-root.x; dy=target.y-root.y; d=reach }
        d=max(d,abs(l1-l2)+1e-6)
        let a=(l1*l1-l2*l2+d*d)/(2*d), h=sqrt(max(l1*l1-a*a,0))
        let mx=root.x+a*dx/d, my=root.y+a*dy/d
        let c1=Point(x:mx-h*dy/d,y:my+h*dx/d), c2=Point(x:mx+h*dy/d,y:my-h*dx/d)
        let side=dx*(bend.y-root.y)-dy*(bend.x-root.x) >= 0
        return (((dx*(c1.y-root.y)-dy*(c1.x-root.x) >= 0) == side) ? c1 : c2,target)
    }
    static func wrist(_ p: inout [String: Point], _ side: String, _ target: Point) throws {
        let s=try get(p,side+"_shoulder"), e=try get(p,side+"_elbow"), w=try get(p,side+"_wrist")
        let (middle,end)=ik(s,target,length(s,e),length(e,w),e)
        p[side+"_elbow"]=middle; p[side+"_wrist"]=end
    }
    static func straighten(_ p: inout [String: Point], _ side: String) throws {
        let s=try get(p,side+"_shoulder"), e=try get(p,side+"_elbow"), w=try get(p,side+"_wrist")
        let l1=length(s,e), l2=length(e,w), d=length(s,w)
        if d < 1e-9 { return }
        let ux=(w.x-s.x)/d, uy=(w.y-s.y)/d
        p[side+"_elbow"]=Point(x:s.x+ux*l1,y:s.y+uy*l1)
        p[side+"_wrist"]=Point(x:s.x+ux*(l1+l2),y:s.y+uy*(l1+l2))
    }
    static func elbow(_ p: inout [String: Point], _ side: String, _ y: Double) throws {
        let s=try get(p,side+"_shoulder"), e=try get(p,side+"_elbow"), w=try get(p,side+"_wrist")
        let l1=length(s,e), l2=length(e,w), dy=max(-l1,min(l1,y-s.y))
        let dx=sqrt(max(l1*l1-dy*dy,0))*(e.x >= s.x ? 1.0 : -1.0)
        let ne=Point(x:s.x+dx,y:s.y+dy), d=length(ne,w)
        p[side+"_elbow"]=ne
        if d > 1e-9 { p[side+"_wrist"]=Point(x:ne.x+(w.x-ne.x)*l2/d,y:ne.y+(w.y-ne.y)*l2/d) }
    }
    static func bodyX(_ p: inout [String: Point], _ dx: Double) {
        shift(&p,upper+["l_hip","r_hip"],dx,0); shift(&p,["l_knee","r_knee"],dx/2,0)
    }
    static func lower(_ p: inout [String: Point], _ dy: Double) throws {
        var legs: [String: (Double,Double)]=[:]
        for side in ["l","r"] {
            if let hip=p[side+"_hip"],let knee=p[side+"_knee"],let ankle=p[side+"_ankle"] { legs[side]=(length(hip,knee),length(knee,ankle)) }
        }
        shift(&p,upper+["l_hip","r_hip"],0,dy)
        for (side,(thigh,shin)) in legs { p[side+"_knee"]=try ik(get(p,side+"_hip"),get(p,side+"_ankle"),thigh,shin,get(p,side+"_knee")).0 }
    }
}

public func correctedPose(analyzer: String, metric: String, target: Double, pose: [String: Point], ref: [String: Point]?, torso: Double, dominant: String, repType: String = "") -> [String: Point]? {
    guard correctionEvent(analyzer:analyzer,metric:metric) != nil else { return nil }
    var p=pose
    let dom=dominant, off=dominant == "r" ? "l" : "r", T=torso
    typealias M = CorrectionMath
    do {
        if analyzer == "golf" {
            let lead=off
            switch metric {
            case "lead_arm_top": try M.straighten(&p,lead)
            case "head_sway": p["nose"]=try Point(x:M.get(ref,"nose").x,y:M.get(p,"nose").y)
            case "head_lift":
                let dy=try M.get(ref,"nose").y+target*T-M.get(p,"nose").y
                try M.lower(&p,max(-0.3*T,min(0.3*T,dy)))
            case "hip_sway":
                let hx=try M.hips(p).x, rx=try M.hips(ref).x, want=rx+copysign(target*T,hx-rx)
                M.shift(&p,["l_hip","r_hip"],want-hx,0); M.shift(&p,["l_knee","r_knee"],(want-hx)/2,0)
            case "finish_balance":
                let ankle=try M.get(p,lead+"_ankle"), hx=try M.hips(p).x, want=ankle.x+copysign(target*T,hx-ankle.x)
                M.bodyX(&p,want-hx)
            default: break
            }
        } else if analyzer == "basketball" {
            let s=try M.get(p,dom+"_shoulder")
            switch metric {
            case "elbow_extension": try M.straighten(&p,dom)
            case "elbow_flare":
                let width=try M.length(M.get(p,"l_shoulder"),M.get(p,"r_shoulder")), e=try M.get(p,dom+"_elbow"), want=s.x+copysign(target*width,e.x-s.x)
                M.shift(&p,[dom+"_elbow",dom+"_wrist"],want-e.x,0)
            case "release_height": try M.wrist(&p,dom,Point(x:M.get(p,dom+"_wrist").x,y:s.y-target*T))
            case "arm_verticality":
                let w=try M.get(p,dom+"_wrist"), e=try M.get(p,dom+"_elbow"), L=M.length(s,e)+M.length(e,w), a=target*Double.pi/180, sign=w.x >= s.x ? 1.0 : -1.0
                try M.wrist(&p,dom,Point(x:s.x+sign*L*sin(a),y:s.y-L*cos(a)))
            case "guide_hand_gap":
                let w=try M.get(p,dom+"_wrist"), side=try M.get(p,off+"_shoulder").x >= s.x ? 1.0 : -1.0
                try M.wrist(&p,off,Point(x:w.x+side*target*T,y:w.y+0.15*T))
            case "lateral_drift":
                let hx=try M.hips(p).x, rx=try M.hips(ref).x, want=rx+copysign(target*T,hx-rx)
                M.bodyX(&p,want-hx)
            default: break
            }
        } else {
            let hip=try M.hips(p), w=try M.get(p,dom+"_wrist")
            switch metric {
            case "finish_height": try M.wrist(&p,dom,Point(x:w.x,y:M.get(p,off+"_shoulder").y-target*T))
            case "elbow_finish": try M.elbow(&p,dom,M.get(p,"nose").y-target*T)
            case "off_hand_reach": try M.straighten(&p,off)
            case "spacing": try M.wrist(&p,dom,Point(x:hip.x+copysign(target*T,w.x-hip.x),y:w.y))
            case "contact_front", "weight_shift", "back_load":
                let contact=metric == "back_load" ? ref : p, back=metric == "back_load" ? p : ref
                let fwd=try M.get(contact,dom+"_wrist").x >= M.get(back,dom+"_wrist").x ? 1.0 : -1.0
                let la=try M.get(p,"l_ankle"), ra=try M.get(p,"r_ankle")
                let ordered=[la.x,ra.x].sorted { $0*fwd < $1*fwd }, backX=ordered[0], frontX=ordered[1]
                if metric == "contact_front" { try M.wrist(&p,dom,Point(x:frontX+fwd*target*T,y:w.y)) }
                else {
                    let width=(frontX-backX)*fwd
                    if width <= 0 { return nil }
                    let want = metric == "back_load" ? backX+fwd*target*width : try M.hips(ref).x+fwd*target*width
                    M.bodyX(&p,want-hip.x)
                }
            case "contact_arm": try M.straighten(&p,dom)
            case "contact_height", "ready_height": try M.wrist(&p,dom,Point(x:w.x,y:hip.y+target*T))
            case "stance_height":
                let ankles=try M.mid(M.get(p,"l_ankle"),M.get(p,"r_ankle"))
                try M.lower(&p,ankles.y-target*T-hip.y)
            case "backswing_size":
                let c=Point(x:hip.x,y:hip.y-0.5*T), d=M.length(w,c)
                if d < 1e-9 { return nil }
                let k=target*T/d
                try M.wrist(&p,dom,Point(x:c.x+(w.x-c.x)*k,y:c.y+(w.y-c.y)*k))
            default: break
            }
        }
        return p
    } catch { return nil }
}
