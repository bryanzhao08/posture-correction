import SwiftUI
import UIKit
import Combine
import AVFoundation
import FormCore

@MainActor
struct SessionFlow: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: SessionController
    @State private var savedID: String?
    init(profiles: Profiles, sport: Sport, profile: SportProfile, handedness: Handedness, spokenCues: Bool, sharePose: Bool, view: String? = nil, focus: String? = nil, training: String? = nil) {
        _controller = StateObject(wrappedValue: SessionController(profiles: profiles, sport: sport, profile: profile,
            handedness: handedness, spokenCues: spokenCues, sharePose: sharePose, view: view, focus: focus, training: training))
    }
    var body: some View {
        Group {
        if let id = savedID {
            NavigationStack {
                LocalSummaryView(sessionID: id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        } else {
            SessionView(controller: controller, onSaved: { savedID = $0 }, onCancel: { dismiss() })
        }
        }.modifier(DemoPresentation())
    }
}
@MainActor
struct SessionView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var controller: SessionController
    let onSaved: (String) -> Void
    let onCancel: () -> Void
    @State private var busy = false
    @State private var saveError: String?
    @State private var showSetupInstructions = false
    @ScaledMetric(relativeTo: .largeTitle) private var repFontSize: CGFloat = 112
    @AppStorage("scoreboardMode") private var scoreboardMode = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recentCue = false
    @ScaledMetric(relativeTo: .largeTitle) private var countdownFontSize: CGFloat = 88
    init(controller: SessionController, onSaved: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _controller = ObservedObject(wrappedValue: controller)
        self.onSaved = onSaved
        self.onCancel = onCancel
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !controller.isReplaying {
                CameraPreview(session: controller.camera.captureSession, mirrored: controller.frame?.mirrored ?? true)
                    .ignoresSafeArea()
            }
            if let frame = controller.frame {
                SkeletonOverlay(joints: frame.joints, names: controller.jointNames, aspect: frame.aspect, mirrored: frame.mirrored, markers: frame.markers)
                    .ignoresSafeArea()
            }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            Text(controller.profile.label).font(.title2.bold())
                            Spacer()
                            #if DEBUG
                            if controller.isReplaying {
                                Text(controller.replayFinished ? "Demo complete · tap End session" : "Demo replay")
                                    .font(.caption.bold()).multilineTextAlignment(.trailing)
                                    .padding(12).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                            }
                            #endif
                            if !controller.isReplaying {
                                Button { controller.camera.switchCamera() } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(width: 52, height: 52)
                                }.accessibilityLabel("Switch front or back camera")
                                    .disabled(controller.frame?.engineState == .active || controller.isFinished)
                            }
                        }
                        HStack(spacing: 16) {
                            Text(controller.stateLabel).font(.title.bold()).padding(.horizontal, 20).padding(.vertical, 12)
                                .background(.black.opacity(0.85), in: Capsule())
                            Spacer(minLength: 0)
                            if controller.frame?.started == true, scoreboardMode != "full" {
                                HStack(spacing: 4) {
                                    Button { changeScoreboard("full") } label: {
                                        if scoreboardMode == "minimized" {
                                            Text("\(controller.frame?.repCount ?? 0) reps · \(Display.score(controller.frame?.lastRep?.score))")
                                                .font(.headline).monospacedDigit()
                                        } else { Image(systemName: "number.square") }
                                    }.frame(minHeight: 44).accessibilityLabel("Show scoreboard")
                                        .accessibilityIdentifier("scoreboard.show")
                                    if scoreboardMode == "minimized" {
                                        Button { changeScoreboard("hidden") } label: { Image(systemName: "xmark") }
                                            .frame(width: 44, height: 44).accessibilityLabel("Hide scoreboard")
                                            .accessibilityIdentifier("scoreboard.hide")
                                    }
                                }.padding(.horizontal, 12).background(.black.opacity(0.85), in: Capsule())
                            }
                        }
                        if controller.frame?.started == true, scoreboardMode == "minimized", recentCue,
                           let cue = controller.frame?.lastRep?.cues.first {
                            Text(cue).font(.headline).lineLimit(1).padding(12)
                                .background(.black.opacity(0.85), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        if controller.frame?.started == true {
                            if scoreboardMode == "full" {
                                VStack(spacing: 8) {
                                    HStack {
                                        Spacer()
                                        Button { changeScoreboard("minimized") } label: { Image(systemName: "chevron.down") }
                                            .frame(width: 44, height: 44).accessibilityLabel("Minimize scoreboard")
                                            .accessibilityIdentifier("scoreboard.minimize")
                                    }
                                    HStack(spacing: 12) {
                                        scoreboardNumber("\(controller.frame?.repCount ?? 0)", label: "REPS")
                                        Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: repFontSize)
                                        scoreboardNumber(Display.score(controller.frame?.lastRep?.score), label: "SCORE")
                                    }
                                    if let cue = controller.frame?.lastRep?.cues.first {
                                        CoachingInstruction(text: cue, sport: controller.sport.rawValue, scope: controller.demoScope)
                                            .font(.title2.bold()).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                    }
                                }.padding(20).frame(maxWidth: .infinity)
                                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
                                    .accessibilityElement(children: .contain)
                            }
                        } else {
                            VStack(spacing: 16) {
                                CoachingInstruction(text: controller.profile.camera, sport: controller.sport.rawValue, scope: controller.demoScope, setup: true).font(.headline).multilineTextAlignment(.center)
                                if let countdown = controller.frame?.countdown {
                                    Text("\(countdown)").font(.system(size: countdownFontSize, weight: .heavy, design: .rounded))
                                    Text("Hold your position").font(.title2.bold())
                                } else {
                                    Text(controller.frame?.setupMessage ?? "Stand in view with your face and both feet visible.")
                                        .font(.title2.bold()).multilineTextAlignment(.center)
                                }
                                if controller.markersEnabled { Text("Markers: \(controller.frame?.markers.count ?? 0) found").font(.caption).foregroundStyle(.orange) }
                                if !controller.isReplaying {
                                    Text("After switching cameras, the setup check starts again.").font(.footnote)
                                }
                            }.padding(24).frame(maxWidth: .infinity).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
                        }
                        if controller.frame?.started == true {
                            VStack(alignment: .leading, spacing: 12) {
                                Button { showSetupInstructions.toggle() } label: {
                                    HStack {
                                        Text("Tripod setup")
                                        Spacer()
                                        Image(systemName: showSetupInstructions ? "chevron.up" : "chevron.down")
                                    }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.borderless).accessibilityIdentifier("setup.instructions")
                                    .accessibilityValue(showSetupInstructions ? "Expanded" : "Collapsed")
                                if showSetupInstructions {
                                    CoachingInstruction(text: controller.profile.camera, sport: controller.sport.rawValue,
                                                        scope: controller.demoScope, setup: true).font(.subheadline)
                                }
                            }.padding(16).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                        }
                        if let error = saveError ?? controller.error { ErrorNotice(message: error) }
                        if controller.cameraDenied {
                            Button("Open iPhone Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                            Button("Back to sports", action: onCancel).frame(minHeight: 44)
                        }
                        Toggle("Speak coaching cues", isOn: $controller.spokenCues)
                            .padding(16).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                            .onChange(of: controller.spokenCues) { _, value in
                                if !value { controller.stopSpeech() }
                                do { try state.setSpokenCues(value) } catch { saveError = error.localizedDescription }
                            }
                        Button { Task { await finishAndSave() } } label: {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text(controller.isFinished ? "Retry saving session" : "End session").font(.title2.bold())
                            }.frame(maxWidth: .infinity, minHeight: 64)
                        }.buttonStyle(.borderedProminent).tint(.red).disabled(busy)
                    }.padding(16).frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .task { await controller.start() }
        .task(id: controller.frame?.repCount) {
            recentCue = (controller.frame?.repCount ?? 0) > 0
            do { try await Task.sleep(for: .seconds(4)); recentCue = false } catch { }
        }
        .onDisappear { if !DemoOffers.shared.isPresenting { controller.stop() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await finishAndSave() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: controller.camera.captureSession).receive(on: DispatchQueue.main)) { _ in
            Task { await finishAndSave() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: controller.camera.captureSession).receive(on: DispatchQueue.main)) { _ in
            controller.error = "The camera stopped. Your completed reps will be saved."
            Task { await finishAndSave() }
        }
    }
    private func scoreboardNumber(_ value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Text(value).font(.system(size: repFontSize, weight: .heavy, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.35).lineLimit(1)
            Text(label).font(.title2.bold())
        }.frame(maxWidth: .infinity)
    }
    private func changeScoreboard(_ mode: String) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { scoreboardMode = mode }
    }
    @MainActor private func finishAndSave() async {
        guard !busy else { return }
        busy = true
        await controller.finish()
        do { onSaved(try controller.save(to: state)) }
        catch { saveError = "Could not save on this iPhone: " + error.localizedDescription }
        busy = false
    }
}
