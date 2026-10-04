import SwiftUI

@main
@MainActor
struct FormCoachApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if state.user != nil { MainView() }
                else { AuthView() }
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
