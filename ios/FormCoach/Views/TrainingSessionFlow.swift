import SwiftUI
import FormCore

/// Capture and recording are created only after the explicit Start session action.
@MainActor struct TrainingSessionFlow: View {
    let profiles: Profiles
    let sport: Sport
    let profile: SportProfile
    let handedness: Handedness
    @State var spokenCues: Bool
    @AppStorage("sayNice") private var sayNice = false
    @EnvironmentObject private var state: AppState
    let sharePose: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var trainingID = ""
    @State private var view = ""
    @State private var started = false
    @AppStorage("saveReplays") private var saveReplays = false
    @AppStorage("replayOfferSeen") private var replayOfferSeen = false
    @State private var offerReplays = false
    @State private var drillID = ""
    @AppStorage(PlayerSettings.heightKey) private var heightCm = 0.0
    @AppStorage(PlayerSettings.metricKey) private var metric = Locale.current.measurementSystem != .us
    private var drills: [Drill] { profile.drills(for: choices.isEmpty ? nil : selected?.id) }
    private var drill: Drill? { drills.first { $0.id == drillID } ?? drills.first }
    private var player: Player { PlayerSettings.current(profiles.player) }
    private var choices: [TrainingType] { profile.training ?? [] }
    private var selected: TrainingType? { choices.first { $0.id == trainingID } ?? choices.first }
    var body: some View {
        Group {
            if started {
                SessionFlow(profiles: profiles, sport: sport, profile: profile, handedness: handedness,
                            spokenCues: spokenCues, sharePose: sharePose, view: choices.isEmpty ? nil : view,
                            focus: selected?.id == "serve" ? "serve" : nil, training: selected?.id,
                            player: player, drill: drill?.id)
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
                        if !drills.isEmpty {
                            Section {
                                Picker("Drill", selection: Binding(get: { drill?.id ?? "" }, set: { drillID = $0 })) {
                                    ForEach(drills) { Text($0.label).tag($0.id) }
                                }.accessibilityIdentifier("training.drill")
                                if let drill = drill {
                                    Text(drill.about)
                                    if let tip = drill.tip { Label(tip, systemImage: "lightbulb").font(.subheadline) }
                                    let focus = (drill.emphasis ?? [:]).filter { $0.value > 1 }.keys
                                    let labels = profile.effective(for: view).metrics.filter { focus.contains($0.id) }.map(\.label)
                                    if !labels.isEmpty { Text("Focus: " + labels.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary) }
                                    if let types = drill.types { Text("Only \(types.joined(separator: " and "))s count.").font(.caption).foregroundStyle(.secondary) }
                                }
                            } header: { Text("Drill") } footer: {
                                let level = player.level.flatMap { profiles.player?.levels[$0]?.label } ?? ""
                                Text("Goal \(drill?.goalReps ?? 0) reps · scored as \(level) · height \(PlayerSettings.heightLabel(player.heightCm, metric: metric)). Change your level and height in Settings.")
                            }
                        }
                        Section("Coaching audio") {
                            Toggle("Speak cues", isOn:$spokenCues)
                                .onChange(of:spokenCues) { _, value in try? state.setSpokenCues(value) }
                            Toggle("Say 'nice' on good reps", isOn:$sayNice)
                        }
                        Section { Toggle("Save replays of reps that need work",isOn:$saveReplays).accessibilityIdentifier("replays.save") } footer: { Text("Stay on this iPhone. Never uploaded.") }
                        if selected == nil {
                            Section("Camera placement") { cameraInstructions }
                        }
                    }.navigationTitle(sport.label + " practice")
                        .safeAreaInset(edge: .bottom) {
                            Button {
                                if let drill = drill { UserDefaults.standard.set(drill.id, forKey: "drill." + sport.rawValue) }
                                if !choices.isEmpty {
                                    UserDefaults.standard.set(trainingID, forKey: "training." + sport.rawValue)
                                    UserDefaults.standard.set(view, forKey: "trainingView." + sport.rawValue)
                                }
                                if !saveReplays && !replayOfferSeen { offerReplays=true } else { started=true }
                            } label: {
                                Text("Start session").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("training.start")
                                .padding().background(.regularMaterial)
                        }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
                }.modifier(DemoPresentation())
            }
        }.alert("Save short replays of reps that need work?",isPresented:$offerReplays) {
            Button("Save replays") { saveReplays=true; replayOfferSeen=true; started=true }
            Button("Not now") { replayOfferSeen=true; started=true }
        } message: { Text("They stay on this iPhone and are never uploaded.") }
        .onAppear {
            if drillID.isEmpty { drillID = UserDefaults.standard.string(forKey: "drill." + sport.rawValue) ?? "" }
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
        VStack(alignment: .leading, spacing: 8) {
            CoachingInstruction(text: profile.camera(for: view), sport: sport.rawValue,
                                scope: "preparation." + sport.rawValue, setup: true, textIdentifier: "training.camera")
            if heightCm > 0 {
                Text("At \(PlayerSettings.heightLabel(heightCm, metric: metric)), keep the phone at least \(PlayerSettings.minPhoneDistance(heightCm: heightCm, metric: metric)) away to fit you head to feet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    static func viewLabel(_ view: String) -> String {
        switch view { case "back": return "From behind"; case "side": return "Side-on"; default: return "Face-on" }
    }
}

@MainActor enum SessionContext {
    static func label(_ sport: String, summary: SessionSummary, profile: SportProfile?) -> String {
        var parts = [profile?.label ?? sport.capitalized]
        if let id = summary.training, let type = profile?.training?.first(where: { $0.id == id }) { parts.append(type.label) }
        if let id = summary.drill, let drill = profile?.drills?.first(where: { $0.id == id }) { parts.append(drill.label) }
        if let view = summary.view { parts.append(TrainingSessionFlow.viewLabel(view).lowercased()) }
        return parts.joined(separator: " · ")
    }
}
