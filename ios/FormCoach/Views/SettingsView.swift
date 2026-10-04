import SwiftUI
import FormCore

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("offerMovementDemos") private var offerMovementDemos = true
    @AppStorage("orangeMarkers.golf") private var golfMarkers = false
    @AppStorage("orangeMarkers.tennis") private var tennisMarkers = false
    @AppStorage("orangeMarkers.pickleball") private var pickleballMarkers = false
    @State private var handedness: Handedness = .right
    @State private var emailReports = true
    @State private var spokenCues = false
    @State private var sharePose = false
    @State private var confirmDeletion = false
    @State private var busy = false
    @State private var message: String?
    @State private var error: String?
    #if DEBUG
    @AppStorage("debugReplayDemoSession") private var replayDemoSession = false
    @State private var backend = ""
    #endif
    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Text(state.user?.name ?? "")
                    Text(state.user?.email ?? "").foregroundStyle(.secondary)
                }
                Section("Practice preferences") {
                    Picker("Handedness", selection: $handedness) {
                        Text("Right").tag(Handedness.right)
                        Text("Left").tag(Handedness.left)
                    }
                    Toggle("Email progress reports", isOn: $emailReports)
                    Toggle("Speak coaching cues", isOn: $spokenCues)
                    Toggle("Offer movement demos", isOn: $offerMovementDemos)
                }
                Section("Golf markers") {
                    Toggle("I'm using neon-orange markers", isOn: $golfMarkers)
                    Text("Stick neon-orange markers on the back of your lead glove and the club head.").font(.caption)
                }
                Section("Tennis markers") {
                    Toggle("I'm using neon-orange markers", isOn: $tennisMarkers)
                    Text("Stick neon-orange markers on your hitting wrist and the racket tip.").font(.caption)
                }
                Section("Pickleball markers") {
                    Toggle("I'm using neon-orange markers", isOn: $pickleballMarkers)
                    Text("Stick neon-orange markers on your hitting wrist and the paddle's top edge.").font(.caption)
                }
                Section {
                    Toggle("Share pose data to improve accuracy", isOn: $sharePose)
                } header: { Text("Optional pose sharing") } footer: {
                    Text("Off by default. When enabled, joint positions and confidence values are saved during new sessions and sent to the backend. No photos, video or audio are recorded. Turning this off deletes pose recordings still waiting on this iPhone.")
                }
                Section {
                    Button("Save preferences") {
                        do {
                            try state.saveSettings(handedness: handedness, emailReports: emailReports,
                                                   spokenCues: spokenCues, sharePose: sharePose)
                            message = "Saved on this iPhone. Account preferences sync when connected."
                            error = nil
                        } catch { self.error = error.localizedDescription }
                    }.frame(minHeight: 44)
                    if let message = message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    if state.cache?.pendingPatch != nil { Text("Account preferences waiting to sync.").font(.caption) }
                    if let error = error { ErrorNotice(message: error) }
                }
                Section("Uploads") {
                    LabeledContent("Waiting to sync", value: "\(state.pendingCount)")
                    Button(state.isSyncing ? "Syncing…" : "Retry uploads") {
                        Task { await state.syncPending() }
                    }.disabled(state.isSyncing || busy)
                }
                #if DEBUG
                Section("Movement review") {
                    NavigationLink("Demo gallery") { DemoGallery() }.accessibilityIdentifier("demo.gallery")
                }
                Section {
                    Toggle("Replay demo session", isOn: $replayDemoSession)
                } header: { Text("Development session source") } footer: {
                    Text("Uses recorded demo poses instead of the camera for new sessions. The Simulator always uses replay.")
                }
                Section("Development backend") {
                    TextField("Backend URL", text: $backend).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("Changing servers signs you out. Use a LAN hostname for a physical iPhone.").font(.caption).foregroundStyle(.secondary)
                    Button("Save backend URL") {
                        do { try state.changeBackend(backend) } catch { self.error = error.localizedDescription }
                    }.disabled(busy)
                }
                #endif
                Section {
                    Button("Log out") {
                        do { try state.logout() } catch { self.error = error.localizedDescription }
                    }.disabled(busy)
                    Button("Delete account", role: .destructive) { confirmDeletion = true }.disabled(busy)
                    if busy { ProgressView("Deleting account…") }
                } footer: {
                    Text("Deleting your account removes your sessions and personal data from the server and this iPhone. A connection is required.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                handedness = state.user?.handedness ?? .right
                emailReports = state.user?.emailReports ?? true
                spokenCues = state.spokenCues
                sharePose = state.sharePose
                #if DEBUG
                backend = state.backendURL
                #endif
            }
            .confirmationDialog("Delete your FormCoach account and all its data?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Delete account permanently", role: .destructive) {
                    busy = true; error = nil
                    Task {
                        do { try await state.deleteAccount() }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This cannot be undone.") }
        }
    }
}
