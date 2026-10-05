import SwiftUI
import FormCore

/// Capture and recording are created only after the explicit Start session action.
@MainActor struct TrainingSessionFlow: View {
    let profiles: Profiles
    let sport: Sport
    let profile: SportProfile
    let handedness: Handedness
    let spokenCues: Bool
    let sharePose: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var trainingID = ""
    @State private var view = ""
    @State private var started = false
    private var choices: [TrainingType] { profile.training ?? [] }
    private var selected: TrainingType? { choices.first { $0.id == trainingID } ?? choices.first }
    var body: some View {
        Group {
            if started {
                SessionFlow(profiles: profiles, sport: sport, profile: profile, handedness: handedness,
                            spokenCues: spokenCues, sharePose: sharePose, view: choices.isEmpty ? nil : view,
                            focus: selected?.id == "serve" ? "serve" : nil, training: selected?.id)
            } else {
                NavigationStack {
                    Form {
                        if !choices.isEmpty {
                        Section("What are you practising?") {
                            Picker("Training", selection: $trainingID) {
                                ForEach(choices) { Text($0.label).tag($0.id) }
                            }.accessibilityIdentifier("training.type")
                        }
                        }
                        if let selected = selected {
                            Section("Camera view") {
                                Text(selected.why)
                                Picker("View", selection: $view) {
                                    ForEach(selected.views, id: \.self) { Text(Self.viewLabel($0)).tag($0) }
                                }.pickerStyle(.segmented).accessibilityIdentifier("training.view")
                                cameraInstructions
                            }
                        }
                        if selected == nil {
                            Section("Camera placement") { cameraInstructions }
                        }
                    }.navigationTitle(sport.label + " practice")
                        .safeAreaInset(edge: .bottom) {
                            Button {
                                if !choices.isEmpty {
                                    UserDefaults.standard.set(trainingID, forKey: "training." + sport.rawValue)
                                    UserDefaults.standard.set(view, forKey: "trainingView." + sport.rawValue)
                                }
                                started = true
                            } label: {
                                Text("Start session").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("training.start")
                                .padding().background(.regularMaterial)
                        }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
                }.modifier(DemoPresentation())
            }
        }.onAppear {
            guard trainingID.isEmpty, let first = choices.first else { return }
            let saved = UserDefaults.standard.string(forKey: "training." + sport.rawValue)
            let choice = choices.first { $0.id == saved } ?? first
            trainingID = choice.id
            let savedView = UserDefaults.standard.string(forKey: "trainingView." + sport.rawValue)
            view = savedView.flatMap { choice.views.contains($0) ? $0 : nil } ?? choice.recommended
        }.onChange(of: trainingID) { old, new in
            if !old.isEmpty, let choice = choices.first(where: { $0.id == new }) { view = choice.recommended }
        }
    }
    private var cameraInstructions: some View {
        CoachingInstruction(text: profile.camera(for: view), sport: sport.rawValue,
                            scope: "preparation." + sport.rawValue, setup: true, textIdentifier: "training.camera")
    }
    static func viewLabel(_ view: String) -> String {
        switch view { case "back": return "From behind"; case "side": return "Side-on"; default: return "Face-on" }
    }
}

@MainActor enum SessionContext {
    static func label(_ sport: String, summary: SessionSummary, profile: SportProfile?) -> String {
        var parts = [profile?.label ?? sport.capitalized]
        if let id = summary.training, let type = profile?.training?.first(where: { $0.id == id }) { parts.append(type.label) }
        if let view = summary.view { parts.append(TrainingSessionFlow.viewLabel(view).lowercased()) }
        return parts.joined(separator: " · ")
    }
}
