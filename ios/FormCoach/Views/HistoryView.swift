import SwiftUI
import Charts

@MainActor
struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @State private var sport: Sport = .golf
    private var local: [LocalSession] { state.sessions.filter { $0.payload.sport == sport.rawValue } }
    private var remote: [SessionListItem] {
        let ids = Set(local.map(\.id))
        return (state.cache?.history[sport.rawValue] ?? []).filter { !ids.contains($0.clientID) }
    }
    private var entries: [HistoryEntry] {
        (local.map { HistoryEntry(id: $0.id, localID: $0.id, serverID: nil,
            startedAt: $0.payload.startedAt, score: $0.payload.summary.score,
            reps: $0.payload.summary.repCount, queued: $0.server == nil) }
         + remote.map { HistoryEntry(id: $0.clientID, localID: nil, serverID: $0.id,
            startedAt: $0.startedAt, score: $0.score, reps: $0.repCount, queued: false) })
        .sorted { Display.date($0.startedAt) > Display.date($1.startedAt) }
    }
    private var trend: [HistoryEntry] {
        let serverTrend = state.cache?.stats[sport.rawValue]?.trend ?? []
        let serverIDs = Set(serverTrend.map(\.id))
        let points = serverTrend.map { HistoryEntry(id: "server-\($0.id)", localID: nil, serverID: $0.id,
            startedAt: $0.startedAt, score: $0.score, reps: $0.repCount, queued: false) }
        let extra = local.filter { $0.server == nil || !serverIDs.contains($0.server!.id) }.map {
            HistoryEntry(id: $0.id, localID: $0.id, serverID: nil, startedAt: $0.payload.startedAt,
                score: $0.payload.summary.score, reps: $0.payload.summary.repCount, queued: $0.server == nil)
        }
        return (points + extra).sorted { Display.date($0.startedAt) < Display.date($1.startedAt) }
    }
    private var checkpoints: [Checkpoint] {
        var merged = Dictionary(uniqueKeysWithValues: (state.cache?.checkpoints[sport.rawValue] ?? []).map { ($0.id, $0) })
        for checkpoint in local.compactMap({ $0.server?.checkpoint }) { merged[checkpoint.id] = checkpoint }
        return merged.values.sorted { Display.date($0.createdAt) > Display.date($1.createdAt) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Sport", selection: $sport) {
                        ForEach(Sport.allCases) { sport in Text(sport.label).tag(sport) }
                    }
                }
                if let error = state.error { Section { ErrorNotice(message: error) } }
                if !trend.isEmpty || state.cache?.stats[sport.rawValue] != nil {
                    Section("Score trend") {
                        if trend.contains(where: { $0.score != nil }) {
                            Chart(trend) { point in
                                if let score = point.score {
                                    LineMark(x: .value("Session date", Display.date(point.startedAt)), y: .value("Score", score))
                                    PointMark(x: .value("Session date", Display.date(point.startedAt)), y: .value("Score", score))
                                }
                            }
                            .chartYScale(domain: 0...100).frame(height: 200)
                            .accessibilityLabel("\(sport.label) score trend, oldest to newest")
                            .accessibilityValue(trend.filter { $0.score != nil }.map {
                                "\(Display.date($0.startedAt).formatted(date: .abbreviated, time: .omitted)): \(Display.score($0.score))"
                            }.joined(separator: "; "))
                        } else { Text("Your score trend appears after a completed session syncs.") }
                        LabeledContent("Sessions", value: "\(state.sessionCount(sport))")
                        if let stats = state.cache?.stats[sport.rawValue] {
                            LabeledContent("Total synced reps", value: "\(stats.totalReps)")
                            LabeledContent("Average synced score", value: Display.score(stats.avgScore))
                            LabeledContent("Best synced score", value: Display.score(stats.bestScore))
                            LabeledContent("Recent synced average", value: Display.score(stats.recentAvgScore))
                        }
                        Text("Saved local sessions appear in the chart immediately; server statistics update after syncing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Sessions") {
                    if local.isEmpty && remote.isEmpty {
                        Text("No sessions yet. Practise to start your history.").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { session in
                        if let localID = session.localID {
                            NavigationLink {
                                LocalSummaryView(sessionID: localID)
                            } label: {
                                SessionRow(startedAt: session.startedAt, score: session.score, reps: session.reps, queued: session.queued)
                            }
                        } else if let serverID = session.serverID {
                            NavigationLink {
                                ServerDetailView(id: serverID)
                            } label: {
                                SessionRow(startedAt: session.startedAt, score: session.score, reps: session.reps, queued: false)
                            }
                        }
                    }
                }
                Section("Checkpoints") {
                    if checkpoints.isEmpty {
                        Text("A checkpoint is created every five sessions. Your reports are emailed when email reports are on.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(checkpoints) { checkpoint in
                        DisclosureGroup("Checkpoint \(checkpoint.number) · \(Display.score(checkpoint.avgScore))/100") {
                            Text(Display.date(checkpoint.createdAt), style: .date)
                            Text("\(checkpoint.sessions) sessions · \(checkpoint.totalReps) reps")
                            if let previous = checkpoint.previousAvgScore {
                                Text("Previous average: \(Display.score(previous))")
                            }
                            ForEach(Array(checkpoint.focusCues.enumerated()), id: \.offset) { _, cue in Text(cue) }
                            ComparisonRows(metrics: checkpoint.metrics)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .task(id: sport) { await state.refreshHistory(sport) }
            .refreshable { await state.syncPending(); await state.refreshHistory(sport) }
        }
    }
}
@MainActor
struct SessionRow: View {
    let startedAt: String
    let score: Double?
    let reps: Int
    let queued: Bool
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Display.date(startedAt), format: .dateTime.month().day().hour().minute())
                Text("\(reps) reps" + (queued ? " · Saved locally" : " · Synced")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Display.score(score)).font(.title2.bold()).monospacedDigit()
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}

private struct HistoryEntry: Identifiable {
    let id: String
    let localID: String?
    let serverID: Int?
    let startedAt: String
    let score: Double?
    let reps: Int
    let queued: Bool
}
