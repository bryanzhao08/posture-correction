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
    init(profiles: Profiles, sport: Sport, profile: SportProfile, handedness: Handedness, spokenCues: Bool, sharePose: Bool) {
        _controller = StateObject(wrappedValue: SessionController(profiles: profiles, sport: sport, profile: profile,
            handedness: handedness, spokenCues: spokenCues, sharePose: sharePose))
    }
    var body: some View {
        if let id = savedID {
            NavigationStack {
                LocalSummaryView(sessionID: id)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        } else {
            SessionView(controller: controller, onSaved: { savedID = $0 }, onCancel: { dismiss() })
        }
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
    @ScaledMetric(relativeTo: .largeTitle) private var repFontSize: CGFloat = 112
    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize: CGFloat = 48
    @ScaledMetric(relativeTo: .largeTitle) private var countdownFontSize: CGFloat = 88
    init(controller: SessionController, onSaved: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _controller = ObservedObject(wrappedValue: controller)
        self.onSaved = onSaved
        self.onCancel = onCancel
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: controller.camera.captureSession, mirrored: controller.frame?.mirrored ?? true)
                .ignoresSafeArea()
            if let frame = controller.frame {
                SkeletonOverlay(joints: frame.joints, names: controller.jointNames, aspect: frame.aspect, mirrored: frame.mirrored)
                    .ignoresSafeArea()
            }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            Text(controller.profile.label).font(.title2.bold())
                            Spacer()
                            Button { controller.camera.switchCamera() } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(width: 52, height: 52)
                            }.accessibilityLabel("Switch front or back camera")
                                .disabled(controller.frame?.engineState == .active || controller.isFinished)
                        }
                        HStack(spacing: 16) {
                            Text(controller.stateLabel).font(.title.bold()).padding(.horizontal, 20).padding(.vertical, 12)
                                .background(.black.opacity(0.85), in: Capsule())
                            Spacer(minLength: 0)
                            VStack {
                                Text(Display.score(controller.frame?.lastRep?.score)).font(.system(size: scoreFontSize, weight: .bold, design: .rounded)).monospacedDigit()
                                Text("LAST SCORE").font(.caption.bold())
                            }.padding(12).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                        }
                        Spacer(minLength: 0)
                        if controller.frame?.started == true {
                            VStack(spacing: 8) {
                                Text("\(controller.frame?.repCount ?? 0)").font(.system(size: repFontSize, weight: .heavy, design: .rounded)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                                Text("REPS").font(.title2.bold())
                                if let cue = controller.frame?.lastRep?.cues.first {
                                    Text(cue).font(.title2.bold()).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(24).frame(maxWidth: .infinity)
                                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
                                .accessibilityElement(children: .combine)
                        } else {
                            VStack(spacing: 16) {
                                Text(controller.profile.camera).font(.headline).multilineTextAlignment(.center)
                                if let countdown = controller.frame?.countdown {
                                    Text("\(countdown)").font(.system(size: countdownFontSize, weight: .heavy, design: .rounded))
                                    Text("Hold your position").font(.title2.bold())
                                } else {
                                    Text(controller.frame?.setupMessage ?? "Stand in view with your face and both feet visible.")
                                        .font(.title2.bold()).multilineTextAlignment(.center)
                                }
                                Text("After switching cameras, the setup check starts again.").font(.footnote)
                            }.padding(24).frame(maxWidth: .infinity).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
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
        .onDisappear { controller.stop() }
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
    @MainActor private func finishAndSave() async {
        guard !busy else { return }
        busy = true
        await controller.finish()
        do { onSaved(try controller.save(to: state)) }
        catch { saveError = "Could not save on this iPhone: " + error.localizedDescription }
        busy = false
    }
}
