import SwiftUI
import SceneKit

enum DemoPlayback: String, CaseIterable { case wrong = "Wrong", correct = "Correct", both = "Both" }
@MainActor struct HologramDemo: View {
    let cue: DemoCue
    let leftHanded: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode=DemoPlayback.both
    @State private var replay=0
    @State private var keyMoment=false
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HologramScene(cue: cue, leftHanded: leftHanded, reduceMotion: reduceMotion,
                              mode: mode, replay: replay, keyMoment: keyMoment)
                    .id(cue.key)
                    .frame(maxWidth: .infinity,maxHeight: .infinity).frame(minHeight: 260)
                    .accessibilityHidden(true)
                HStack {
                    Label("Correct",systemImage: "checkmark.circle").foregroundStyle(.cyan)
                    Label(mode == .both ? "Wrong ghost" : "Wrong",systemImage: "xmark.circle").foregroundStyle(.orange)
                }.font(.caption)
                Picker("Motion",selection:$mode) {
                    ForEach(DemoPlayback.allCases,id:\.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal)
                HStack {
                    Button("Replay") { keyMoment=false; replay += 1 }
                    Button(keyMoment ? "Play motion" : "Key moment") { keyMoment.toggle() }
                        .accessibilityIdentifier("hologram.keyMoment")
                }.buttonStyle(.bordered).frame(minHeight:44)
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        Text(cue.meaning).font(.headline).accessibilityIdentifier("hologram.meaning")
                        Text(cue.text).font(.subheadline)
                        Label("Wrong: "+cue.wrongMotion,systemImage:"xmark.circle").foregroundStyle(.orange)
                        Label("Correct: "+cue.correctMotion,systemImage:"checkmark.circle").foregroundStyle(.cyan)
                    }.frame(maxWidth:.infinity,alignment:.leading).padding()
                }.frame(maxHeight:210)
            }.background(Color(red:0.015,green:0.025,blue:0.05))
                .navigationTitle("Movement demo").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) {
                    Button("Close demo") { dismiss() }.accessibilityIdentifier("hologram.close")
                } }
        }.preferredColorScheme(.dark)
    }
}

struct HologramScene: UIViewRepresentable {
    let cue:DemoCue
    let leftHanded:Bool, reduceMotion:Bool
    let mode:DemoPlayback
    let replay:Int
    let keyMoment:Bool
    func makeCoordinator() -> HologramStage { HologramStage(cue:cue,leftHanded:leftHanded) }
    func makeUIView(context:Context) -> SCNView {
        let view=SCNView(); view.scene=context.coordinator.scene; view.pointOfView=context.coordinator.camera
        view.backgroundColor=UIColor(red:0.015,green:0.025,blue:0.05,alpha:1)
        view.antialiasingMode = .multisampling4X; view.preferredFramesPerSecond=30
        view.isPlaying=true; view.rendersContinuously=true
        view.isAccessibilityElement=false; view.accessibilityElementsHidden=true
        return view
    }
    func updateUIView(_ view:SCNView,context:Context) {
        let signature="\(mode)-\(replay)-\(reduceMotion)-\(keyMoment)"
        guard signature != context.coordinator.signature else { return }
        context.coordinator.signature=signature
        context.coordinator.play(mode:mode,reduceMotion:reduceMotion,keyMoment:keyMoment)
        view.isPlaying = !keyMoment && !reduceMotion
        view.rendersContinuously = !keyMoment && !reduceMotion
        view.setNeedsDisplay()
    }
    static func dismantleUIView(_ view:SCNView,coordinator:HologramStage) {
        coordinator.scene.rootNode.removeAllActions(); view.isPlaying=false; view.rendersContinuously=false
        view.scene=nil; view.pointOfView=nil
    }
}

/// Lit translucent volume plus Fresnel emission keeps the silhouette readable through the ghost.
final class HologramFigure {
    let root=SCNNode(), implement=SCNNode(), head=SCNNode(), ball=SCNNode()
    var joints:[String:SCNNode]=[:], bones:[String:SCNNode]=[:]
    var materials:[SCNMaterial]=[]
    let sport:String
    static let links=[("pelvis","chest"),("l_shoulder","r_shoulder"),("chest","head"),
        ("l_shoulder","l_elbow"),("l_elbow","l_wrist"),("r_shoulder","r_elbow"),("r_elbow","r_wrist"),
        ("l_hip","r_hip"),("l_hip","l_knee"),("l_knee","l_ankle"),("r_hip","r_knee"),("r_knee","r_ankle")]
    init(sport:String,leftHanded:Bool,wrong:Bool) {
        self.sport=sport
        if leftHanded { root.scale.x = -1 }
        for name in ["pelvis","chest","l_shoulder","r_shoulder","l_elbow","r_elbow","l_wrist","r_wrist","l_hip","r_hip","l_knee","r_knee","l_ankle","r_ankle"] {
            let radius:CGFloat = name.contains("wrist") ? 0.028 : 0.034
            let node=SCNNode(geometry:SCNSphere(radius:radius)); root.addChildNode(node); joints[name]=node; decorate(node,wrong:wrong)
        }
        for (a,b) in Self.links {
            let radius:CGFloat = a == "pelvis" ? 0.12 : (a.contains("hip") && b.contains("knee") ? 0.043 : 0.028)
            let node=SCNNode(geometry:SCNCapsule(capRadius:radius,height:1)); root.addChildNode(node); bones[a+b]=node; decorate(node,wrong:wrong)
        }
        head.geometry=SCNSphere(radius:0.105); head.scale=SCNVector3(0.83,1.14,0.94); root.addChildNode(head); decorate(head,wrong:wrong)
        let nose=SCNNode(geometry:SCNCone(topRadius:0,bottomRadius:0.018,height:0.036)); nose.position=SCNVector3(0,-0.01,0.10); nose.eulerAngles.x = .pi/2
        head.addChildNode(nose); decorate(nose,wrong:wrong)
        // Eye line gives head-direction cues an unambiguous orientation landmark.
        let eyes=SCNNode(geometry:SCNBox(width:0.12,height:0.012,length:0.015,chamferRadius:0.003)); eyes.position=SCNVector3(0,0.02,0.085)
        head.addChildNode(eyes); decorate(eyes,wrong:wrong)
        for side in ["l","r"] {
            let foot=SCNNode(geometry:SCNBox(width:0.085,height:0.06,length:0.23,chamferRadius:0.025))
            root.addChildNode(foot); joints[side+"_foot"]=foot; decorate(foot,wrong:wrong)
            let palm=SCNNode(geometry:SCNCapsule(capRadius:0.025,height:0.08))
            root.addChildNode(palm); joints[side+"_palm"]=palm; decorate(palm,wrong:wrong)
        }
        root.addChildNode(implement)
        if sport == "golf" {
            part(SCNCylinder(radius:0.009,height:1.1),at:SCNVector3(0,0.55,0),wrong:wrong)
            part(SCNCylinder(radius:0.016,height:0.20),at:SCNVector3(0,0.10,0),wrong:wrong)
            part(SCNBox(width:0.10,height:0.06,length:0.065,chamferRadius:0.018),at:SCNVector3(0.025,1.09,0),wrong:wrong)
        } else if sport != "basketball" {
            let length:CGFloat = sport == "tennis" ? 0.69 : 0.40
            part(SCNCylinder(radius:0.014,height:sport == "tennis" ? 0.30 : 0.13),at:SCNVector3(0,sport == "tennis" ? 0.15 : 0.065,0),wrong:wrong)
            if sport == "tennis" {
                let frame=SCNNode(geometry:SCNTorus(ringRadius:0.12,pipeRadius:0.008)); frame.position.y=0.49
                frame.scale=SCNVector3(1,1,1.5); frame.eulerAngles.x = .pi/2; implement.addChildNode(frame); decorate(frame,wrong:wrong)
                for i in -4...4 {
                    let string=SCNNode(geometry:SCNBox(width:0.19,height:0.003,length:0.003,chamferRadius:0))
                    string.position=SCNVector3(0,0.49+Float(i)*0.035,0); implement.addChildNode(string); decorate(string,wrong:wrong)
                }
            } else { part(SCNBox(width:0.20,height:length-0.13,length:0.018,chamferRadius:0.055),at:SCNVector3(0,0.265,0),wrong:wrong) }
        }
        ball.geometry=SCNSphere(radius:sport == "basketball" ? 0.12 : 0.033)
        root.addChildNode(ball); decorate(ball,wrong:wrong)
    }
    func part(_ geometry:SCNGeometry,at:SCNVector3,wrong:Bool) {
        let n=SCNNode(geometry:geometry); n.position=at; implement.addChildNode(n); decorate(n,wrong:wrong)
    }
    func decorate(_ node:SCNNode,wrong:Bool) {
        if let material=materials.first { node.geometry?.materials=[material]; return }
        let m=SCNMaterial(); m.lightingModel = .blinn; m.diffuse.contents=wrong ? UIColor(red:0.28,green:0.06,blue:0.01,alpha:1) : UIColor(red:0.01,green:0.16,blue:0.20,alpha:1)
        m.emission.contents=wrong ? UIColor(red:0.7,green:0.19,blue:0.02,alpha:1) : UIColor(red:0.02,green:0.48,blue:0.58,alpha:1)
        m.transparency=0.6; m.blendMode = .add; m.writesToDepthBuffer=false; m.isDoubleSided=false
        m.shaderModifiers=[.surface: """
        #pragma body
        float edge = pow(1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view))), 2.8);
        float band = 0.5 + 0.5 * sin(_surface.position.y * 38.0 - u_time * 2.2);
        _surface.emission.rgb *= 0.38 + edge * 1.5 + band * 0.10;
        _surface.diffuse.a *= 0.65;
        """
        ]
        node.geometry?.materials=[m]; materials.append(m)
    }
    func apply(_ p:DemoPose,base:BaseMotion,still:Bool) {
        let s=DemoSkeleton(p:p,base:base)
        for (name,node) in joints {
            if let point=s.points[name] { node.simdPosition=point }
            if name.hasSuffix("_foot"), let ankle=s.points[String(name.prefix(1))+"_ankle"] { node.simdPosition=ankle+SIMD3(0,-0.025,0.065) }
            if name.hasSuffix("_palm"), let wrist=s.points[String(name.prefix(1))+"_wrist"] { node.simdPosition=wrist; node.simdOrientation=simd_quatf(from:SIMD3(0,1,0),to:s.shaft) }
        }
        if sport == "basketball", let palm=joints["r_palm"] {
            palm.simdOrientation=simd_quatf(angle:p.wristSnap*Float.pi*0.65,axis:SIMD3(1,0,0))
        }
        for (a,b) in Self.links {
            if let from=s.points[a],let to=s.points[b],let n=bones[a+b] { Self.segment(n,from:from,to:to) }
        }
        head.simdPosition=s.points["head"]!; head.simdOrientation=DemoSkeleton.rotation(p.headYaw,base == .golfSwing ? p.spine : 0)
        implement.simdPosition=s.grip; implement.simdOrientation=simd_quatf(from:SIMD3(0,1,0),to:s.shaft)
        implement.isHidden=sport == "basketball" || base == .tripod
        ball.simdPosition=s.ball; ball.isHidden=base == .tripod || base == .readyStance
        if base == .golfSwing {
            let address=DemoSkeleton(p:DemoMotion(base:.golfSwing,parameters:[:]).frames[0],base:.golfSwing)
            ball.simdPosition=address.grip+address.shaft*1.1; ball.scale=SCNVector3(0.64,0.64,0.64)
        }
    }
    static func segment(_ n:SCNNode,from:SIMD3<Float>,to:SIMD3<Float>) {
        let v=to-from
        guard simd_length(v)>0.00001 else { n.isHidden=true; return }
        n.isHidden=false; n.simdPosition=(from+to)/2; n.simdScale=SIMD3(1,simd_length(v),1)
        n.simdOrientation=simd_quatf(from:SIMD3(0,1,0),to:simd_normalize(v))
    }
}

final class HologramStage {
    let scene=SCNScene(), camera=SCNNode(), arc=SCNNode(), ring=SCNNode()
    let correct:HologramFigure, wrong:HologramFigure
    let cue:DemoCue, spec:MotionSpec
    var signature=""
    var setupNodes:[SCNNode]=[]
    var angleLabel=SCNNode()
    init(cue:DemoCue,leftHanded:Bool) {
        self.cue=cue; spec=DemoMotionTable.entries[cue.key]!
        correct=HologramFigure(sport:cue.sport,leftHanded:leftHanded,wrong:false)
        wrong=HologramFigure(sport:cue.sport,leftHanded:leftHanded,wrong:true)
        scene.rootNode.addChildNode(wrong.root); scene.rootNode.addChildNode(correct.root)
        let ambient=SCNNode(); ambient.light=SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity=280; scene.rootNode.addChildNode(ambient)
        let light=SCNNode(); light.light=SCNLight(); light.light?.type = .omni; light.light?.intensity=600; light.position=SCNVector3(2,4,3); scene.rootNode.addChildNode(light)
        for i in -12...12 {
            for axis in 0...1 {
                let line=SCNNode(geometry:SCNBox(width:axis == 0 ? 12 : 0.003,height:0.002,length:axis == 0 ? 0.003 : 12,chamferRadius:0))
                line.position=SCNVector3(axis == 0 ? 0 : Float(i)*0.5,0,axis == 0 ? Float(i)*0.5 : 0)
                glow(line,UIColor(red:0,green:0.08,blue:0.10,alpha:1)); scene.rootNode.addChildNode(line)
            }
        }
        ring.geometry=SCNTorus(ringRadius:0.65,pipeRadius:0.008); ring.position.y=0.015
        glow(ring,UIColor(red:0,green:0.35,blue:0.45,alpha:1)); scene.rootNode.addChildNode(ring)
        scene.rootNode.addChildNode(arc)
        camera.camera=SCNCamera(); camera.camera?.zFar=80; camera.camera?.bloomIntensity=0.8; camera.camera?.bloomThreshold=0.65; camera.camera?.bloomBlurRadius=6
        camera.camera?.wantsHDR=true; camera.camera?.exposureAdaptationBrighteningSpeedFactor=0; camera.camera?.exposureAdaptationDarkeningSpeedFactor=0
        scene.rootNode.addChildNode(camera)
        setCamera(0)
    }
    func glow(_ node:SCNNode,_ color:UIColor) {
        let m=SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents=UIColor.black; m.emission.contents=color
        m.blendMode = .add; m.writesToDepthBuffer=false; node.geometry?.materials=[m]
    }
    func text(_ text:String,at:SCNVector3,color:UIColor) -> SCNNode {
        let g=SCNText(string:text,extrusionDepth:0); g.font=UIFont.systemFont(ofSize:1,weight:.medium); g.flatness=0.2
        let n=SCNNode(geometry:g); n.scale=SCNVector3(0.065,0.065,0.065); n.position=at
        glow(n,color); n.constraints=[SCNBillboardConstraint()]; scene.rootNode.addChildNode(n); return n
    }
    func setCamera(_ time:Float) {
        let setup=spec.base == .tripod
        let angle:Float = setup ? 2.2 : 0.72 + sin(time*0.14)*0.12
        let radius:Float=setup ? 6 : 3.7
        camera.position=SCNVector3(sin(angle)*radius,setup ? 2.6 : 2.15,cos(angle)*radius)
        camera.look(at:SCNVector3(0,setup ? 0.9 : 1,setup ? 1.2 : 0))
    }
    /// A shared, fixed phase for positional cues; timing cues compare the same elapsed seconds.
    func reviewTime(_ motion:DemoMotion) -> Float {
        let key=cue.key
        if key.contains("leg_drive") { return 0 }
        if key.contains("rhythm") { let good=DemoMotion(base:spec.base,parameters:spec.correct); return good.back+good.down }
        if key.contains("tempo") { return DemoMotion(base:spec.base,parameters:spec.correct).back+0.15 }
        if key.contains("follow_through") || key.contains("swing_through") || key.contains("finish_balance") || key.contains("arm_verticality") { return motion.back+motion.hitch+motion.down+0.75 }
        if key.contains("head_lift") || key.contains("contact") || key.contains("head_stability") || key.contains("drift") || key.contains("guide_hand") || key.contains("elbow_extension") || key.contains("release_height") { return motion.back+motion.hitch+motion.down }
        return motion.back
    }
    func rotationGuide(_ p:DemoPose) {
        guard cue.key.contains("shoulder_turn") || cue.key.contains("hip_sway") else { return }
        if arc.childNodes.isEmpty {
            for _ in 0..<32 {
                let n=SCNNode(geometry:SCNCylinder(radius:0.004,height:1)); glow(n,.cyan); arc.addChildNode(n)
            }
            angleLabel=text("",at:SCNVector3(-0.6,0.16,0.8),color:.cyan)
        }
        let degrees=cue.key.contains("hip_sway") ? p.hipTurn : p.shoulderTurn
        let angle=abs(degrees)*Float.pi/180
        for i in 0..<32 {
            let a=Float(i)/32*angle,b=Float(i+1)/32*angle
            let n=arc.childNodes[i]
            HologramFigure.segment(n,from:SIMD3(sin(a)*0.75,0.025,cos(a)*0.75),to:SIMD3(sin(b)*0.75,0.025,cos(b)*0.75))
        }
        (angleLabel.geometry as? SCNText)?.string=cue.key.contains("hip_sway") ? "\(Int(abs(degrees)))° hips • \(Int(abs(p.pelvisX)*100)) cm shift" : "\(Int(abs(degrees)))° shoulder turn"
    }
    func setup(parameters:[String:Double],wrong:Bool,clear:Bool=true) {
        if clear { setupNodes.forEach { $0.removeFromParentNode() }; setupNodes=[] }
        let distance=Float(parameters["tripodDistance"] ?? 3.5), height=Float(parameters["tripodHeight"] ?? 1.3)
        let color=wrong ? UIColor.orange : UIColor.cyan
        func add(_ g:SCNGeometry,_ p:SIMD3<Float>) -> SCNNode {
            let n=SCNNode(geometry:g); n.simdPosition=p; glow(n,color); scene.rootNode.addChildNode(n); setupNodes.append(n); return n
        }
        let centre=SIMD3<Float>(0,height,distance)
        _=add(SCNBox(width:0.18,height:0.32,length:0.035,chamferRadius:0.025),centre)
        let screen=add(SCNBox(width:0.145,height:0.26,length:0.003,chamferRadius:0.013),centre+SIMD3(0,0,-0.020))
        screen.opacity=0.30
        _=add(SCNSphere(radius:0.018),centre+SIMD3(-0.055,0.10,-0.025))
        let pole=add(SCNCylinder(radius:0.025,height:1),SIMD3(0,height/2,distance)); pole.simdScale.y=height
        for angle:Float in [0,2.094,4.188] {
            let leg=add(SCNCylinder(radius:0.018,height:1),SIMD3.zero)
            HologramFigure.segment(leg,from:SIMD3(0,0.38,distance),to:SIMD3(sin(angle)*0.35,0.02,distance+cos(angle)*0.35))
        }
        // Four transparent frustum faces, physically projected at the athlete's plane.
        let vertical:Float=0.45, halfHeight=distance*vertical, halfWidth=halfHeight*0.48
        let corners=[SIMD3<Float>(-halfWidth,height-halfHeight,0),SIMD3(halfWidth,height-halfHeight,0),
                     SIMD3(halfWidth,height+halfHeight,0),SIMD3(-halfWidth,height+halfHeight,0)]
        for i in 0..<4 {
            let vertices=[SCNVector3(centre),SCNVector3(corners[i]),SCNVector3(corners[(i+1)%4])]
            let indices:[Int32]=[0,1,2]
            let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
            let n=add(geometry,.zero); n.opacity=0.035; n.geometry?.firstMaterial?.isDoubleSided=true
            let edge=add(SCNCylinder(radius:0.004,height:1),.zero)
            HologramFigure.segment(edge,from:centre,to:corners[i]); edge.opacity=0.2
        }
        let label=text(wrong ? "1 m • too close / low" : (cue.sport == "tennis" ? "4–6 m" : (cue.sport == "golf" ? "3–4 m" : "3–5 m")),at:SCNVector3(0.12,0.18,distance/2),color:color)
        label.scale=SCNVector3(0.13,0.13,0.13)
        setupNodes.append(label)
        if wrong {
            let cutoff=add(SCNSphere(radius:0.135),SIMD3(0,1.64,0)); cutoff.geometry?.firstMaterial?.emission.contents=UIColor.red
            cutoff.opacity=0.5
            setupNodes.append(text("Head outside frame",at:SCNVector3(-0.45,1.95,0),color:.red))
        }
    }
    func play(mode:DemoPlayback,reduceMotion:Bool,keyMoment:Bool) {
        scene.rootNode.removeAllActions()
        let bad=DemoMotion(base:spec.base,parameters:spec.wrong), good=DemoMotion(base:spec.base,parameters:spec.correct)
        for figure in [correct,wrong] {
            for material in figure.materials {
                if let surface=material.shaderModifiers?[.surface] {
                    material.shaderModifiers=[.surface:reduceMotion ? surface.replacingOccurrences(of:"u_time * 2.2",with:"0.0") : surface.replacingOccurrences(of:"38.0 - 0.0",with:"38.0 - u_time * 2.2")]
                }
            }
        }
        correct.root.isHidden=mode == .wrong; wrong.root.isHidden=mode == .correct
        wrong.root.opacity=mode == .both ? 0.28 : 1; wrong.root.position.z=mode == .both ? -0.12 : 0
        func draw(_ t:Float) {
            let freeze=keyMoment || reduceMotion
            let gt=freeze ? reviewTime(good) : t, bt=freeze ? reviewTime(bad) : t
            let gp=good.sample(gt),bp=bad.sample(bt)
            correct.apply(gp,base:spec.base,still:freeze); wrong.apply(bp,base:spec.base,still:freeze)
            setCamera(freeze ? 0 : t)
            rotationGuide(mode == .wrong ? bp : gp)
        }
        draw(0)
        if spec.base == .tripod {
            setup(parameters:mode == .wrong ? spec.wrong : spec.correct,wrong:mode == .wrong)
            if mode == .both {
                let first=setupNodes.count
                setup(parameters:spec.wrong,wrong:true,clear:false)
                for node in setupNodes.dropFirst(first) { node.opacity *= 0.28 }
            }
        }
        else { setupNodes.forEach { $0.removeFromParentNode() }; setupNodes=[] }
        if keyMoment { return }
        if reduceMotion {
            scene.rootNode.runAction(.repeatForever(.sequence([.fadeOpacity(to:0.8,duration:0.3),.fadeOpacity(to:1,duration:0.3),.wait(duration:2)])))
            return
        }
        let loop=max(bad.duration,good.duration)+0.4
        scene.rootNode.runAction(.repeatForever(.customAction(duration:TimeInterval(loop)) { [weak self] _,elapsed in
            guard let self=self else { return }; draw(Float(elapsed))
            let flicker=0.96+0.04*sin(Float(elapsed)*9)
            self.correct.root.opacity=CGFloat(flicker)
        }))
    }
}
