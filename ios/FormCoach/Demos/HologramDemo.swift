import SwiftUI
import SceneKit

enum DemoPlayback: String, CaseIterable { case wrong = "Wrong", correct = "Correct", both = "Both" }

@MainActor struct HologramDemo: View {
    let cue: DemoCue
    let leftHanded: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = DemoPlayback.both
    @State private var replay = 0
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HologramScene(spec: DemoMotionTable.entries[cue.key]!, sport: cue.sport,
                              leftHanded: leftHanded, reduceMotion: reduceMotion, mode: mode, replay: replay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).frame(minHeight: 260)
                    .accessibilityLabel("3D movement demonstration. Orange shows the wrong motion. Cyan shows the correct motion.")
                    .accessibilityIdentifier("hologram.scene")
                Picker("Motion", selection: $mode) {
                    ForEach(DemoPlayback.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal)
                Button("Replay") { replay += 1 }.buttonStyle(.bordered)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(cue.meaning).font(.headline).accessibilityIdentifier("hologram.meaning")
                        Text(cue.text).font(.subheadline)
                        Label("Wrong: " + cue.wrongMotion, systemImage: "xmark.circle").foregroundStyle(.orange)
                        Label("Correct: " + cue.correctMotion, systemImage: "checkmark.circle").foregroundStyle(.cyan)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }.frame(maxHeight: 230)
            }
            .background(Color(red: 0.015, green: 0.035, blue: 0.07))
            .navigationTitle("Movement demo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Close demo") { dismiss() }.accessibilityIdentifier("hologram.close")
            } }
        }.preferredColorScheme(.dark)
    }
}

/// Joint-angle keyframes shared by every cue. A cue changes parameters, never the scene hierarchy.
struct MotionPose {
    var shoulder: Double = 35, across: Double = 0, elbow: Double = 25
    var leadShoulder: Double = 35, leadElbow: Double = 10
    var knee: Double = 15, turn: Double = 0, lean: Double = 0
    var x: Double = 0, headX: Double = 0, headY: Double = 0, headTurn: Double = 0
    static func blend(_ a: Self, _ b: Self, _ fraction: Double) -> Self {
        let f = fraction * fraction * (3 - 2 * fraction)
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * f }
        return Self(shoulder: mix(a.shoulder,b.shoulder), across: mix(a.across,b.across), elbow: mix(a.elbow,b.elbow),
            leadShoulder: mix(a.leadShoulder,b.leadShoulder), leadElbow: mix(a.leadElbow,b.leadElbow),
            knee: mix(a.knee,b.knee), turn: mix(a.turn,b.turn), lean: mix(a.lean,b.lean), x: mix(a.x,b.x),
            headX: mix(a.headX,b.headX), headY: mix(a.headY,b.headY), headTurn: mix(a.headTurn,b.headTurn))
    }
}
struct ParametricMotion {
    let base: BaseMotion
    let parameters: [String: Double]
    func p(_ key: String, _ fallback: Double) -> Double { parameters[key] ?? fallback }
    var backDuration: Double { p("tempoBackSeconds", base == .golfSwing ? 0.84 : (base == .basketballShot ? 0.1 : 0.4)) }
    var forwardDuration: Double { p("tempoDownSeconds", base == .golfSwing ? 0.28 : 0.3) }
    var duration: Double { backDuration + forwardDuration + 0.25 + p("followThroughHold", 1.1) + 0.8 }
    var keyframes: [MotionPose] {
        var address = MotionPose()
        address.knee = p("kneeBend", 25)
        var top = address, contact = address, finish = address
        if base == .golfSwing {
            address.lean = 22
            top.shoulder = 125; top.leadShoulder = 125; top.turn = -p("shoulderTurnDeg",85)
            top.leadElbow = p("leadElbowBendAtTop",8); top.elbow = 90
            contact.shoulder = 40; contact.leadShoulder = 40; contact.turn = 25
            contact.lean = 22 - p("spineTiltLoss",0)
            finish.shoulder = 150; finish.leadShoulder = 145; finish.turn = 100
            finish.lean = p("finishLean",0); finish.knee = 5
        } else if base == .basketballShot {
            address.shoulder = 65; address.elbow = 95; address.leadShoulder = 65
            top.shoulder = 125 - p("shotHitch",0); top.elbow = 100
            contact.shoulder = p("releaseHeight",155); contact.elbow = p("armExtensionAtContact",5)
            contact.across = p("elbowFlare",4) + p("armAcrossBody",0)
            contact.leadShoulder = p("guideHandPushes",35); contact.knee = 0
            finish = contact
        } else if base == .readyStance || base == .tripod {
            address.shoulder = p("paddleHeightReady",base == .tripod ? 25 : 65); address.elbow = 65
            if base == .tripod { address.knee = 0 }
            address.leadShoulder = 60; top = address; contact = address; finish = address
            top.knee = address.knee + 5
        } else {
            let overhead = base == .tennisServe || base == .pickleballOverhead
            let dink = base == .pickleballDink
            let backhand = base == .tennisBackhand
            address.shoulder = 45; address.elbow = 35
            top.shoulder = overhead ? 150 : p("backswingSize",dink ? 25 : 80)
            top.across = backhand ? -75 : 55; top.turn = -p("unitTurnDeg",65)
            top.elbow = overhead ? 100 : 30
            contact.shoulder = p("contactHeight", overhead ? 175 : (dink ? 40 : 65))
            contact.elbow = p("armExtensionAtContact",10); contact.turn = 20
            contact.across = backhand ? 35 : -30
            finish.shoulder = p("swingThrough",dink ? 65 : 145); finish.across = -65; finish.turn = 65
        }
        top.x = p("hipSlide",0); contact.x = p("drift",0)
        top.headX = p("headSlide",0); contact.headY = -p("headDrop",0)
        contact.headTurn = p("headTurnEarly",0); finish.headTurn = contact.headTurn
        return [address,top,contact,finish,address]
    }
    func sample(_ time: Double) -> MotionPose {
        let original = keyframes
        let frames = [original[0],original[1],original[2],original[3],original[3],original[4]]
        let times = [0.0, backDuration, backDuration + forwardDuration,
                     backDuration + forwardDuration + 0.25,
                     backDuration + forwardDuration + 0.25 + p("followThroughHold",1.1), duration]
        for i in 0..<5 where time <= times[i+1] {
            var f = max(0,min(1,(time-times[i]) / max(0.001,times[i+1]-times[i])))
            if i == 1 { f = pow(f, p("accelerationProfile",1)) }
            return .blend(frames[i],frames[i+1],f)
        }
        return frames[0]
    }
}

struct HologramScene: UIViewRepresentable {
    let spec: MotionSpec
    let sport: String
    let leftHanded: Bool
    let reduceMotion: Bool
    let mode: DemoPlayback
    let replay: Int
    func makeCoordinator() -> HologramRig { HologramRig(sport: sport, setup: spec.base == .tripod, leftHanded: leftHanded) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.scene
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = UIColor(red: 0.015, green: 0.035, blue: 0.07, alpha: 1)
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = true
        view.isPlaying = true; view.rendersContinuously = true
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let signature = "\(mode.rawValue)-\(replay)-\(reduceMotion)"
        guard context.coordinator.signature != signature else { return }
        context.coordinator.signature = signature
        context.coordinator.play(spec: spec, mode: mode, reduceMotion: reduceMotion)
    }
    static func dismantleUIView(_ view: SCNView, coordinator: HologramRig) {
        coordinator.scene.rootNode.removeAllActions(); coordinator.figure.removeAllActions()
        coordinator.camera.removeAllActions(); view.isPlaying = false
    }
}

final class HologramRig {
    let scene = SCNScene(), figure = SCNNode(), camera = SCNNode(), torso = SCNNode(), head = SCNNode()
    let rightShoulder = SCNNode(), leftShoulder = SCNNode(), rightElbow = SCNNode(), leftElbow = SCNNode()
    let rightHip = SCNNode(), leftHip = SCNNode(), rightKnee = SCNNode(), leftKnee = SCNNode()
    let tripod = SCNNode(), scanline = SCNNode()
    var materials: [SCNMaterial] = []
    var signature = ""
    let setup: Bool
    init(sport: String, setup: Bool, leftHanded: Bool) {
        self.setup = setup
        scene.rootNode.addChildNode(figure); figure.position.y = 0.92
        if leftHanded { figure.scale.x = -1 }
        figure.addChildNode(torso)
        shape(SCNCapsule(capRadius: 0.12, height: 0.58), parent: torso, at: SCNVector3(0,0.29,0))
        torso.addChildNode(head); head.position = SCNVector3(0,0.78,0)
        shape(SCNSphere(radius: 0.13), parent: head)
        shape(SCNSphere(radius: 0.035), parent: head, at: SCNVector3(0,0,0.13))
        func arm(_ shoulder: SCNNode, _ elbow: SCNNode, x: Float) -> SCNNode {
            torso.addChildNode(shoulder); shoulder.position = SCNVector3(x,0.55,0)
            shape(SCNSphere(radius: 0.065), parent: shoulder)
            shape(SCNCapsule(capRadius: 0.045,height: 0.3), parent: shoulder, at: SCNVector3(0,-0.15,0))
            shoulder.addChildNode(elbow); elbow.position.y = -0.3
            shape(SCNSphere(radius: 0.06), parent: elbow)
            shape(SCNCapsule(capRadius: 0.035,height: 0.3), parent: elbow, at: SCNVector3(0,-0.15,0))
            let hand = SCNNode(); elbow.addChildNode(hand); hand.position.y = -0.3
            shape(SCNSphere(radius: 0.06), parent: hand)
            return hand
        }
        let hand = arm(rightShoulder,rightElbow,x: 0.23)
        _ = arm(leftShoulder,leftElbow,x: -0.23)
        for (hip,knee,x) in [(leftHip,leftKnee,Float(-0.13)),(rightHip,rightKnee,Float(0.13))] {
            figure.addChildNode(hip); hip.position.x = x
            shape(SCNSphere(radius: 0.065), parent: hip)
            shape(SCNCapsule(capRadius: 0.065,height: 0.43), parent: hip, at: SCNVector3(0,-0.215,0))
            hip.addChildNode(knee); knee.position.y = -0.43
            shape(SCNSphere(radius: 0.065), parent: knee)
            shape(SCNCapsule(capRadius: 0.045,height: 0.42), parent: knee, at: SCNVector3(0,-0.21,0))
            shape(SCNSphere(radius: 0.055), parent: knee, at: SCNVector3(0,-0.42,0))
            shape(SCNBox(width: 0.1,height: 0.06,length: 0.22,chamferRadius: 0.03), parent: knee, at: SCNVector3(0,-0.45,0.07))
        }
        if sport == "basketball" {
            shape(SCNSphere(radius: 0.12), parent: hand, at: SCNVector3(0,-0.12,0))
        } else {
            let length: CGFloat = sport == "golf" ? 0.85 : 0.3
            shape(SCNCylinder(radius: 0.015,height: length), parent: hand, at: SCNVector3(0,-Float(length)/2,0))
            if sport == "golf" {
                shape(SCNBox(width: 0.15,height: 0.06,length: 0.07,chamferRadius: 0.01), parent: hand, at: SCNVector3(0.045,-0.85,0))
            } else {
                let implement = SCNNode(geometry: sport == "tennis" ? SCNTorus(ringRadius: 0.13,pipeRadius: 0.012) : SCNBox(width: 0.23,height: 0.3,length: 0.025,chamferRadius: 0.08))
                implement.position.y = -0.43
                if sport == "tennis" { implement.eulerAngles.x = .pi / 2 }
                decorate(implement); hand.addChildNode(implement)
            }
        }
        for i in -6...6 {
            for axis in 0...1 {
                let line = SCNNode(geometry: SCNBox(width: axis == 0 ? 6 : 0.005,height: 0.003,length: axis == 0 ? 0.005 : 6,chamferRadius: 0))
                line.position = SCNVector3(axis == 0 ? 0 : Float(i)*0.5,0,axis == 0 ? Float(i)*0.5 : 0)
                let material = SCNMaterial(); material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.12)
                material.lightingModel = .constant; line.geometry?.materials = [material]
                scene.rootNode.addChildNode(line)
            }
        }
        scanline.geometry = SCNBox(width: 1.4,height: 0.008,length: 0.8,chamferRadius: 0)
        let shimmer = SCNMaterial(); shimmer.diffuse.contents = UIColor.black
        shimmer.emission.contents = UIColor(red: 0, green: 0.12, blue: 0.16, alpha: 1); shimmer.lightingModel = .constant
        shimmer.transparency = 0.1; shimmer.blendMode = .add; scanline.geometry?.materials = [shimmer]
        scene.rootNode.addChildNode(scanline)
        if setup {
            scene.rootNode.addChildNode(tripod)
            shape(SCNCylinder(radius: 0.025,height: 1), parent: tripod, at: SCNVector3(0,0.5,0))
            for angle in [Float(0),Float(2.1),Float(4.2)] {
                let leg = SCNNode(); tripod.addChildNode(leg); leg.position.y = 0.3; leg.eulerAngles = SCNVector3(0,angle,0.6)
                shape(SCNCylinder(radius: 0.015,height: 0.6), parent: leg, at: SCNVector3(0,-0.3,0))
            }
            shape(SCNBox(width: 0.14,height: 0.26,length: 0.025,chamferRadius: 0.025), parent: tripod, at: SCNVector3(0,1.12,0))
        }
        camera.camera = SCNCamera(); camera.camera?.zFar = 100
        scene.rootNode.addChildNode(camera)
        camera.position = setup ? SCNVector3(5,3.5,7) : SCNVector3(2.7,2.1,4.1)
        camera.look(at: SCNVector3(0,0.9,setup ? 1.5 : 0))
        apply(MotionPose())
    }
    func decorate(_ node: SCNNode) {
        let material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = UIColor.black; material.emission.contents = UIColor.cyan
        material.blendMode = .add; material.transparency = 0.65; material.isDoubleSided = true
        node.geometry?.materials = [material]; materials.append(material)
    }
    func shape(_ geometry: SCNGeometry, parent: SCNNode, at: SCNVector3 = SCNVector3Zero) {
        let node = SCNNode(geometry: geometry); node.position = at; decorate(node); parent.addChildNode(node)
    }
    func apply(_ p: MotionPose) {
        func radians(_ d: Double) -> Float { Float(d * .pi / 180) }
        rightShoulder.eulerAngles = SCNVector3(-radians(p.shoulder),0,radians(p.across))
        leftShoulder.eulerAngles = SCNVector3(-radians(p.leadShoulder),0,0)
        rightElbow.eulerAngles.x = -radians(p.elbow); leftElbow.eulerAngles.x = -radians(p.leadElbow)
        for hip in [leftHip,rightHip] { hip.eulerAngles.x = -radians(p.knee / 2) }
        for knee in [leftKnee,rightKnee] { knee.eulerAngles.x = radians(p.knee) }
        torso.eulerAngles = SCNVector3(radians(p.lean),radians(p.turn),0)
        figure.position.x = Float(p.x); figure.position.y = 0.92 - Float(p.knee / 500)
        head.position = SCNVector3(Float(p.headX),0.78 + Float(p.headY),0)
        head.eulerAngles.y = radians(p.headTurn)
    }
    func play(spec: MotionSpec, mode: DemoPlayback, reduceMotion: Bool) {
        figure.removeAllActions(); camera.removeAllActions(); scanline.removeAllActions()
        let variants: [Bool] = mode == .both ? [true,false] : [mode == .wrong]
        var actions: [SCNAction] = []
        for wrong in variants {
            let parameters = wrong ? spec.wrong : spec.correct
            let motion = ParametricMotion(base: spec.base,parameters: parameters)
            let configure = SCNAction.run { [weak self] _ in
                guard let self = self else { return }
                let color = wrong ? UIColor.systemOrange : UIColor.cyan
                for m in self.materials { m.diffuse.contents = UIColor.black; m.emission.contents = color }
                if self.setup {
                    self.tripod.position.z = Float(parameters["tripodDistance"] ?? 3.5)
                    self.tripod.scale.y = Float(parameters["tripodHeight"] ?? 1.3) / 1.12
                }
                self.apply(motion.sample(reduceMotion ? motion.backDuration + motion.forwardDuration : 0))
            }
            if reduceMotion {
                actions += [.fadeOut(duration: 0.2),configure,.fadeIn(duration: 0.2),.wait(duration: 2)]
            } else {
                actions += [configure,.customAction(duration: motion.duration) { [weak self] _,time in self?.apply(motion.sample(Double(time))) }]
            }
        }
        figure.runAction(.repeatForever(.sequence(actions)))
        scanline.isHidden = reduceMotion
        if !reduceMotion {
            scanline.position.y = 0.05
            scanline.runAction(.repeatForever(.sequence([.move(to: SCNVector3(0,1.9,0),duration: 2.5),.move(to: SCNVector3(0,0.05,0),duration: 0)])))
            camera.runAction(.repeatForever(.customAction(duration: 12) { [weak self] node,time in
                guard let self = self else { return }
                let angle = 0.5 + sin(Double(time) / 12 * .pi * 2) * 0.18
                let distance = self.setup ? 8.5 : 4.9
                node.position = SCNVector3(Float(sin(angle)*distance),self.setup ? 3.5 : 2.1,Float(cos(angle)*distance))
                node.look(at: SCNVector3(0,0.9,self.setup ? 1.5 : 0))
            }))
        }
    }
}
