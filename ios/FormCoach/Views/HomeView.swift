import SwiftUI
import UIKit
import FormCore

@MainActor
struct MainView: View {
    var body: some View {
        TabView {
            HomeView().tabItem { Label("Practise", systemImage: "figure.golf") }
            HistoryView().tabItem { Label("History", systemImage: "chart.xyaxis.line") }
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
@MainActor
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedSport: Sport?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your next better rep.").font(.largeTitle.bold())
                        Text("Choose your sport, set up your tripod, and get moving.").foregroundStyle(.secondary)
                    }
                    if let error = state.error { ErrorNotice(message: error) }
                    if state.pendingCount > 0 {
                        HStack {
                            Label("\(state.pendingCount) session(s) waiting to sync", systemImage: "icloud.and.arrow.up")
                            Spacer()
                            Button("Retry") { Task { await state.syncPending() } }.frame(minHeight: 44).disabled(state.isSyncing)
                        }.font(.subheadline)
                    }
                    ForEach(Sport.allCases) { sport in
                        Button { selectedSport = sport } label: {
                            HStack(spacing: 16) {
                                Image(systemName: sport.symbol).font(.system(size: 36)).frame(width: 48).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(state.profiles?.sports[sport.rawValue]?.label ?? sport.label).font(.title2.bold())
                                    Text("\(state.sessionCount(sport)) sessions · Last score \(Display.score(state.lastScore(sport)))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                            .foregroundStyle(.primary).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(PracticeCardStyle())
                            .disabled(state.profiles?.sports[sport.rawValue] == nil)
                    }
                    Text("Sessions save on this iPhone first. You can practise offline after logging in.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Practise").navigationBarTitleDisplayMode(.inline)
            .refreshable { await state.syncPending(); await state.refreshHome() }
            .fullScreenCover(item: $selectedSport) { sport in
                if let profiles = state.profiles, let profile = profiles.sports[sport.rawValue], let user = state.user {
                    SessionFlow(profiles: profiles, sport: sport, profile: profile, handedness: user.handedness,
                                spokenCues: state.spokenCues, sharePose: state.sharePose)
                }
            }
        }
    }
}

private struct PracticeCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}
