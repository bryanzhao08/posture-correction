import SwiftUI

@main
@MainActor
struct FormCoachApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    @ViewBuilder private var accountContent: some View {
        if state.user != nil { MainView() } else { AuthView() }
    }
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if CommandLine.arguments.contains("-uiTesting") && CommandLine.arguments.contains("-demoGallery") { SettingsView() }
                else { accountContent }
                #else
                accountContent
                #endif
            }
            .modifier(DemoPresentation())
            .environmentObject(state)
            .tint(.accentColor)
            .task { await state.launch() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await state.syncPending() } }
            }
        }
    }
}
