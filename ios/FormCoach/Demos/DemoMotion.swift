import Foundation
import simd

/// Metres, degrees and seconds. Pose targets are solved into anatomical two-bone joint angles.
/// Feet are world-space anchors; the golf grip is one shared target for both arms.
struct DemoPose {
    var spine: Float = 8, shoulderTurn: Float = 0, hipTurn: Float = 0, knee: Float = 20
    var pelvisZ: Float = 0, stagger: Float = 0, elbowLift: Float = 0
    var pelvisX: Float = 0, jump: Float = 0, headX: Float = 0, headDrop: Float = 0, headYaw: Float = 0
    var grip = SIMD3<Float>(0.25, -0.2, 0.35) // relative to shoulder centre in the torso frame
    var guide = SIMD3<Float>(-0.2, -0.25, 0.3)
    var ballPoint = SIMD3<Float>(0,0,0) // torso-relative flight target, independent of the follow-through hand
    var shaft = SIMD3<Float>(0, 1, 0)
    var elbowFlare: Float = 0, guidePush: Float = 0, wristSnap: Float = 0
    var footShift: Float = 0, trailHeel: Float = 0, ballReleased: Float = 0, toss: Float = 0
    static func blend(_ a: Self, _ b: Self, _ t: Float) -> Self {
        let f = t*t*(3-2*t)
        func m(_ a: Float,_ b: Float) -> Float { a+(b-a)*f }
        var p = Self()
        p.spine=m(a.spine,b.spine); p.shoulderTurn=m(a.shoulderTurn,b.shoulderTurn); p.hipTurn=m(a.hipTurn,b.hipTurn)
        p.pelvisZ=m(a.pelvisZ,b.pelvisZ); p.stagger=m(a.stagger,b.stagger); p.elbowLift=m(a.elbowLift,b.elbowLift)
        p.knee=m(a.knee,b.knee); p.pelvisX=m(a.pelvisX,b.pelvisX); p.jump=m(a.jump,b.jump)
        p.headX=m(a.headX,b.headX); p.headDrop=m(a.headDrop,b.headDrop); p.headYaw=m(a.headYaw,b.headYaw)
        p.grip=simd_mix(a.grip,b.grip,SIMD3(repeating:f)); p.guide=simd_mix(a.guide,b.guide,SIMD3(repeating:f))
        p.ballPoint=simd_mix(a.ballPoint,b.ballPoint,SIMD3(repeating:f))
        p.shaft=simd_normalize(simd_mix(a.shaft,b.shaft,SIMD3(repeating:f)))
        p.elbowFlare=m(a.elbowFlare,b.elbowFlare); p.guidePush=m(a.guidePush,b.guidePush); p.wristSnap=m(a.wristSnap,b.wristSnap)
        p.footShift=m(a.footShift,b.footShift); p.trailHeel=m(a.trailHeel,b.trailHeel)
        p.ballReleased=b.ballReleased>a.ballReleased ? (t>=0.98 ? b.ballReleased : a.ballReleased) : m(a.ballReleased,b.ballReleased); p.toss=m(a.toss,b.toss)
        return p
    }
}
struct DemoMotion {
    let base: BaseMotion
    let parameters: [String: Double]
    func p(_ key: String,_ fallback: Float) -> Float { Float(parameters[key] ?? Double(fallback)) }
    var back: Float { p("tempoBackSeconds",base == .golfSwing ? (hitch>0 ? 1.35 : 0.84) : (base == .basketballShot ? 0.12 : 0.65)) }
    var down: Float { p("tempoDownSeconds",base == .golfSwing ? (hitch>0 ? 0.18 : 0.28) : (base == .basketballShot ? 0.28 : 0.3)) }
    var hitch: Float { p("pauseAtTop",0) }
    var duration: Float { back+hitch+down+1.9 }
    var frames: [DemoPose] {
        var a=DemoPose(), top=a, hit=a, end=a
        switch base {
        case .golfSwing:
            a.spine=38; a.knee=22; a.grip=SIMD3(0,-0.54,0.12); a.shaft=SIMD3(0,-0.72,0.69)
            top=a; top.shoulderTurn = p("shoulderTurnDeg",90); top.hipTurn = 45
            top.grip=SIMD3(0.304,0.25,0.2785); top.shaft=SIMD3(-1,0.02,0)
            // The lead-elbow parameter changes the radius of the shared grip, never releases a hand.
            let left=SIMD3<Float>(-0.18,0,0), vector=top.grip-left
            let bend=p("leadElbowBendAtTop",8)*Float.pi/180
            let reach=sqrt(0.342*0.342+0.27*0.27+2*0.342*0.27*cos(bend))
            top.grip=left+simd_normalize(vector)*reach
            top.headX=p("headSlide",0); top.pelvisX=p("hipSlide",0)
            hit=a; hit.shoulderTurn = -22; hit.hipTurn = -35
            hit.spine=38-p("spineTiltLoss",0); hit.headDrop=p("headDrop",0)
            hit.knee=22+p("impactSink",0)
            end=a; end.spine=5; end.shoulderTurn = -100; end.hipTurn = -85
            end.grip=SIMD3(-0.18,0.22,0.35); end.shaft=SIMD3(0.4,0.15,-0.9)
            end.pelvisX=p("finishLean",-0.12); end.trailHeel=end.pelvisX>0 ? 0 : 0.1; end.knee=8
        case .basketballShot:
            a.knee=p("kneeBend",38); a.spine=5; a.grip=SIMD3(0.10,-0.15,0.32)
            top=a; top.grip=SIMD3(0.13,0.18,0.22); top.elbowFlare=p("elbowFlare",0)
            top.knee=a.knee*0.6
            hit=top; hit.knee=p("releaseKnee",0); hit.jump=0.10
            hit.grip=SIMD3(0.15,p("releaseHeight",0.56),0.22)
            let bend=p("armExtensionAtContact",5)*Float.pi/180
            let reach=sqrt(0.342*0.342+0.27*0.27+2*0.342*0.27*cos(bend))
            hit.grip=SIMD3(0.18,0,0)+simd_normalize(hit.grip-SIMD3(0.18,0,0))*reach
            if parameters["releaseHeight"] != nil { hit.grip=SIMD3(0.15,p("releaseHeight",0.56),0.30) }
            hit.guidePush=p("guideHandPushes",0); hit.ballReleased=1; hit.wristSnap=1
            hit.pelvisX=p("drift",0); hit.footShift=hit.pelvisX
            hit.ballPoint=hit.grip+SIMD3(0,0.12,0.30)
            end=hit; end.jump=0; end.grip.x += p("armAcrossBody",0)
            end.ballPoint=hit.ballPoint+SIMD3(0,0.65,0.70)
            if p("followThroughHold",1.4)<0.5 { end.grip=SIMD3(0.18,-0.42,0.15); end.wristSnap=0 }
        case .readyStance, .tripod:
            a.knee=base == .tripod ? 8 : p("kneeBend",35)
            a.spine=base == .tripod ? 3 : p("waistBend",a.knee<1 ? 45 : 8)
            a.grip=SIMD3(0.10,p("paddleHeightReady",-0.13),0.38)
            top=a; hit=a; end=a
        default:
            let overhead=base == .tennisServe || base == .pickleballOverhead
            let dink=base == .pickleballDink
            let backhand=base == .tennisBackhand
            a.grip=SIMD3(0.13,-0.18,0.35); a.knee=25
            top=a; top.knee=p("kneeBend",35); top.shoulderTurn = (backhand ? -1 : 1)*p("unitTurnDeg",dink ? 20 : (base == .pickleballDrive ? 45 : 70)); top.hipTurn = backhand ? -30 : (dink ? 10 : 30)
            top.grip=backhand ? SIMD3(-0.35,-0.08,0.12) : SIMD3(0.30,-0.12,dink ? 0.25 : -0.18)
            if parameters["backswingSize"] != nil { top.grip.z = -p("backswingSize",0.35) }
            top.shaft=DemoSkeleton.rotation(top.shoulderTurn,top.spine).act(SIMD3(0,0.8,dink ? 0.6 : -0.6))
            if overhead {
                top.grip=SIMD3(0.20,0.10,-0.23); top.shaft=SIMD3(0,-0.8,-0.6)
                top.guide=SIMD3(-0.20,0.56,0.05); top.toss=1
            }
            hit=a; hit.knee=10; hit.shoulderTurn = backhand ? 15 : -15; hit.hipTurn = backhand ? 15 : -15
            hit.grip=SIMD3(backhand ? -0.28 : 0.32,p("contactHeight",dink ? -0.38 : -0.24),0.40)
            hit.shaft=SIMD3(0.5,0.1,0.85)
            hit.spine=p("waistBend",8); hit.knee=p("contactKnee",10)
            if overhead {
                let bend=p("armExtensionAtContact",5)*Float.pi/180
                let reach=sqrt(0.342*0.342+0.27*0.27+2*0.342*0.27*cos(bend))
                hit.grip=SIMD3(0.18,0,0)+simd_normalize(SIMD3<Float>(0,0.98,0.13))*reach; hit.shaft=SIMD3(0,0.96,0.28)
            }
            if parameters["lowBallLoad"] != nil {
                hit.knee=p("lowBallLoad",1)>0.5 ? 80 : 0
                hit.spine=p("lowBallLoad",1)>0.5 ? 8 : 55
                let pelvis=SIMD3<Float>(0,0.055+0.895*cos(hit.knee*Float.pi/360),0)
                let rotation=DemoSkeleton.rotation(hit.shoulderTurn,hit.spine)
                let shoulder=pelvis+rotation.act(SIMD3(0,0.49,0))
                hit.grip=rotation.inverse.act(SIMD3<Float>(0.40,0.76,0.25)-shoulder)
            }
            hit.headYaw=p("headTurnEarly",0)
            end=hit; end.shoulderTurn = backhand ? 55 : -55; end.hipTurn = backhand ? 35 : -35
            end.grip=backhand ? SIMD3(0.45,0.16,0.22) : SIMD3(-0.28,0.18,0.32)
            end.shaft=backhand ? SIMD3(0.8,0.5,0.1) : SIMD3(-0.8,0.5,0.1)
            if dink || base == .pickleballDrive { end.grip=SIMD3(0.25,-0.10,0.52); end.shoulderTurn = -25; end.shaft=SIMD3(0,0.3,0.95) }
            if p("swingThrough",1)<0.5 { end=hit }
            if overhead { end.grip=SIMD3(-0.28,-0.18,0.35); end.shaft=SIMD3(-0.5,-0.6,0.6) }
        }
        if parameters["finishHeight"] != nil { end.grip.y=p("finishHeight",0.25) }
        if parameters["finishElbowLift"] != nil { end.elbowLift=p("finishElbowLift",2.3); end.grip=SIMD3(-0.15,0.24,0.30) }
        if parameters["offReach"] != nil { top.guide=SIMD3(-0.18,-0.10,p("offReach",0.58)) }
        if parameters["contactSpacing"] != nil { hit.grip.x=p("contactSpacing",0.38); hit.grip.z=0.22 }
        if parameters["contactFront"] != nil { hit.grip.z=p("contactFront",0.48); hit.shoulderTurn=0; hit.hipTurn=0 }
        if parameters["extensionThrough"] != nil {
            end=hit
            if p("extensionThrough",0.55)>0 {
                end.grip=hit.grip+SIMD3(0,0,p("extensionThrough",0.55)); end.shaft=SIMD3(0,0.15,0.98)
            } else {
                end.grip=SIMD3(-0.28,0.18,0.32); end.shaft=SIMD3(-0.8,0.5,0.1)
            }
        }
        if parameters["backLoad"] != nil || parameters["weightTransfer"] != nil {
            a.stagger=0.27; top.stagger=0.27; hit.stagger=0.27; end.stagger=0.27
            a.hipTurn=0; top.hipTurn=0; hit.hipTurn=0; end.hipTurn=0
            top.pelvisZ=p("backLoad",-0.23)
            hit.pelvisZ=parameters["weightTransfer"] != nil ? top.pelvisZ+p("weightTransfer",0.32) : 0.12; end.pelvisZ=hit.pelvisZ
        }
        if base == .tennisBackhand && parameters["armExtensionAtContact"] != nil {
            let reach=sqrt(0.342*0.342+0.27*0.27+2*0.342*0.27*cos(p("armExtensionAtContact",5)*Float.pi/180))
            hit.grip=SIMD3(0.18,0,0)+simd_normalize(SIMD3<Float>(-0.3,-0.2,0.7))*reach
        }
        return [a,top,hit,end,a]
    }
    /// Common elapsed time for Both: timing defects are visible as a phase lag against the correct ghost.
    func sample(_ seconds: Float) -> DemoPose {
        let f=frames
        if parameters["extensionThrough"] != nil {
            let contact=back+hitch+down
            if seconds>contact+0.35 {
                var finish=f[3]
                finish.shoulderTurn = -55; finish.hipTurn = -35
                finish.grip=SIMD3(-0.28,0.18,0.32); finish.shaft=SIMD3(-0.8,0.5,0.1)
                if seconds<=contact+0.85 { return .blend(f[3],finish,(seconds-contact-0.35)/0.5) }
                if seconds<=duration-0.55 { return finish }
                return .blend(finish,f[4],max(0,min(1,(seconds-duration+0.55)/0.55)))
            }
        }
        let times:[Float]=[0,back,back+hitch,back+hitch+down,back+hitch+down+0.35,duration-0.55,duration]
        let poses=[f[0],f[1],f[1],f[2],f[3],f[3],f[4]]
        for i in 0..<6 where seconds <= times[i+1] {
            var t=max(0,min(1,(seconds-times[i])/max(0.001,times[i+1]-times[i])))
            if i == 2 { t=pow(t,p("accelerationProfile",1.4)) }
            return .blend(poses[i],poses[i+1],t)
        }
        return f[0]
    }
}

struct DemoSkeleton {
    var points:[String:SIMD3<Float>]
    var grip:SIMD3<Float>, shaft:SIMD3<Float>, ball:SIMD3<Float>, ballReleased:Bool
    static func rotation(_ yaw: Float,_ lean: Float = 0) -> simd_quatf {
        simd_quatf(angle:lean*Float.pi/180,axis:SIMD3(1,0,0))*simd_quatf(angle:yaw*Float.pi/180,axis:SIMD3(0,1,0))
    }
    static func elbow(_ root: SIMD3<Float>,_ target: SIMD3<Float>,_ pole: SIMD3<Float>,_ upper: Float,_ lower: Float) -> SIMD3<Float> {
        let vector=target-root, d=min(upper+lower-0.0001,max(abs(upper-lower)+0.0001,simd_length(vector)))
        let axis=simd_normalize(vector), along=(upper*upper-lower*lower+d*d)/(2*d)
        let projected=pole-axis*simd_dot(pole,axis)
        let perpendicular=simd_length(projected)>0.001 ? simd_normalize(projected) : SIMD3<Float>(0,0,1)
        return root+axis*along+perpendicular*sqrt(max(0,upper*upper-along*along))
    }
    init(p: DemoPose,base: BaseMotion) {
        let hips=Self.rotation(p.hipTurn)
        var legReachHeight:Float = .greatestFiniteMagnitude
        for (side,x) in [("l",Float(-0.16)),("r",Float(0.16))] {
            let hipOffset=hips.act(SIMD3(x,0,0))
            let dx=p.pelvisX+hipOffset.x-(x*1.4+p.footShift)
            let dz=p.pelvisZ+hipOffset.z-(0.03+(side == "l" ? p.stagger : -p.stagger))
            let ankleY=0.055+p.jump+(side == "r" ? p.trailHeel : 0)
            legReachHeight=min(legReachHeight,ankleY+sqrt(max(0.1,0.8998*0.8998-dx*dx-dz*dz)))
        }
        let pelvis=SIMD3<Float>(p.pelvisX,min(legReachHeight,0.055+0.895*cos(p.knee*Float.pi/360)-(p.pelvisX-p.footShift)*(p.pelvisX-p.footShift)/1.8+p.jump),p.pelvisZ)
        let sideLean = -asin(max(-0.9,min(0.9,p.headX/(0.74*cos(p.spine*Float.pi/180)))))
        let r=simd_quatf(angle:sideLean,axis:SIMD3(0,0,1))*Self.rotation(p.shoulderTurn,p.spine)
        let shoulder=pelvis+r.act(SIMD3(0,0.49,0))
        let left=shoulder+r.act(SIMD3(-0.18,0,0)), right=shoulder+r.act(SIMD3(0.18,0,0))
        grip=shoulder+r.act(p.grip); shaft=simd_normalize(p.shaft)
        var leftWrist=shoulder+r.act(p.guide), rightWrist=grip
        if base == .golfSwing {
            // Project the shared grip into both arms' reach without separating either hand.
            for _ in 0..<4 {
                for root in [left,right-shaft*0.075] {
                    let vector=grip-root, length=simd_length(vector)
                    if length>0.6119 { grip=root+vector*(0.6119/length) }
                }
            }
            leftWrist=grip; rightWrist=grip+shaft*0.075
        }
        if base == .basketballShot {
            leftWrist = p.ballReleased<0.5 ? grip+SIMD3(-0.16,0.06,0) : shoulder+SIMD3(-0.27,-0.05,0.25)
            if p.guidePush>0.5 { leftWrist=grip+SIMD3(-0.12,0.01,0) }
        }
        if base != .golfSwing {
            func reachable(_ wrist:SIMD3<Float>,from root:SIMD3<Float>) -> SIMD3<Float> {
                let vector=wrist-root, length=simd_length(vector)
                return root+vector*(min(0.6119,max(0.0721,length))/max(0.0001,length))
            }
            rightWrist=reachable(rightWrist,from:right); grip=rightWrist
            leftWrist=reachable(leftWrist,from:left)
        }
        let head=shoulder+r.act(SIMD3(0,0.25,0))+SIMD3(0,-p.headDrop,0)
        points=["pelvis":pelvis,"chest":shoulder,"head":head,"l_shoulder":left,"r_shoulder":right,
                "l_wrist":leftWrist,"r_wrist":rightWrist]
        points["l_elbow"]=Self.elbow(left,leftWrist,r.act(SIMD3(-0.4,-1,0.4)),0.342,0.27)
        points["r_elbow"]=Self.elbow(right,rightWrist,r.act(SIMD3(0.15+p.elbowFlare,-1+p.elbowLift,0.15)),0.342,0.27)
        for (side,x) in [("l",Float(-0.16)),("r",Float(0.16))] {
            let hip=pelvis+hips.act(SIMD3(x,0,0))
            let foot=SIMD3<Float>(x*1.4+p.footShift,0.055+p.jump+(side == "r" ? p.trailHeel : 0),0.03+(side == "l" ? p.stagger : -p.stagger))
            points[side+"_hip"]=hip; points[side+"_ankle"]=foot
            points[side+"_knee"]=Self.elbow(hip,foot,SIMD3(0,0,1),0.45,0.45)
        }
        ballReleased=p.ballReleased>0.5
        ball=base == .basketballShot ? (ballReleased ? shoulder+r.act(p.ballPoint) : grip+SIMD3(0,0.12,0.02)) : grip+shaft*(base == .tennisServe ? 0.69 : 0.4)
        if base == .tennisServe && p.toss>0.1 { ball=shoulder+SIMD3(-0.05,0.95,0.15) }
    }
}
