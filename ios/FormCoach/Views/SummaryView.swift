import SwiftUI
import FormCore

@MainActor
struct LocalSummaryView: View {
    @EnvironmentObject private var state: AppState
    let sessionID: String
    var body: some View {
        Group {
            if let local = state.sessions.first(where: { $0.id == sessionID }) {
                SummaryContent(sport: local.payload.sport, startedAt: local.payload.startedAt,
                    duration: local.payload.durationS, summary: local.payload.summary, reps: local.payload.reps,
                    comparison: local.server?.comparison, checkpoint: local.server?.checkpoint) {
                    Section("Saved on this iPhone") {
                        if local.server == nil {
                            Label(state.isSyncing ? "Uploading…" : "Upload queued", systemImage: "icloud.and.arrow.up")
                            Text("Your session is safe locally. Comparisons appear after syncing.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Label("Synced", systemImage: "checkmark.icloud")
                            if local.recording != nil && !local.poseUploaded { Text("Pose data upload queued.").font(.caption) }
                        }
                        if let error = local.uploadError { ErrorNotice(message: error) }
                        if local.server == nil || local.recording != nil {
                            Button("Retry upload") { Task { await state.syncPending() } }.disabled(state.isSyncing)
                        }
                    }
                }
            } else { ContentUnavailableView("Session unavailable", systemImage: "doc.questionmark") }
        }.navigationTitle("Session summary").navigationBarTitleDisplayMode(.inline)
    }
}
@MainActor
struct ServerDetailView: View {
    @EnvironmentObject private var state: AppState
    let id: Int
    @State private var session: SessionOut?
    @State private var error: String?
    var body: some View {
        Group {
            if let session = session {
                SummaryContent(sport: session.sport, startedAt: session.startedAt, duration: session.durationS,
                               summary: session.summary, reps: session.reps, comparison: session.comparison,
                               checkpoint: session.checkpoint) { EmptyView() }
            } else if let error = error {
                VStack(spacing: 16) {
                    ErrorNotice(message: error)
                    Button("Retry") { Task { await load() } }.buttonStyle(.borderedProminent)
                }.padding(24)
            } else { ProgressView("Loading session…") }
        }.navigationTitle("Session detail").navigationBarTitleDisplayMode(.inline)
            .task { await load() }
    }
    @MainActor private func load() async {
        error = nil
        session = state.cachedDetail(id)
        do { session = try await state.detail(id) } catch { if session == nil { self.error = error.localizedDescription } }
    }
}
@MainActor
struct SummaryContent<Status: View>: View {
    @EnvironmentObject private var state: AppState
    let sport: String
    let startedAt: String
    let duration: Double
    let summary: SessionSummary
    let reps: [Rep]
    let comparison: Comparison?
    let checkpoint: Checkpoint?
    @ViewBuilder let status: () -> Status
    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize: CGFloat = 64
    init(sport: String, startedAt: String, duration: Double, summary: SessionSummary, reps: [Rep],
         comparison: Comparison?, checkpoint: Checkpoint?, @ViewBuilder status: @escaping () -> Status) {
        self.sport = sport
        self.startedAt = startedAt
        self.duration = duration
        self.summary = summary
        self.reps = reps
        self.comparison = comparison
        self.checkpoint = checkpoint
        self.status = status
    }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text(SessionContext.label(sport, summary: summary, profile: state.profiles?.sports[sport])).font(.title2.bold())
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        VStack(alignment: .leading) {
                            Text(Display.score(summary.score)).font(.system(size: scoreFontSize, weight: .bold, design: .rounded)).monospacedDigit()
                            Text("SESSION SCORE").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading) {
                            Text("\(summary.repCount)").font(.largeTitle.bold()).monospacedDigit()
                            Text("REPS").font(.caption.bold()).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine)
                    Text(Display.date(startedAt), style: .date).font(.subheadline).foregroundStyle(.secondary)
                    Text("\(Int(duration / 60)) min \(Int(duration) % 60) sec · Active \(Int(summary.activeS)) sec · Rest \(Int(summary.passiveS)) sec")
                        .font(.caption).foregroundStyle(.secondary)
                    if summary.repCount == 0 {
                        Text(summary.view == nil ? "No completed reps were counted. Set up face-on, hold still until Ready, then complete a full motion." : "No completed reps were counted. Use your selected camera view, hold still until Ready, then complete a full motion.")
                    }
                    HStack {
                        Text("Form: \(Display.score(summary.formScore))")
                        Spacer()
                        Text("Consistency: \(Display.score(summary.consistency))")
                    }.font(.subheadline)
                }.padding(.vertical, 8)
            }
            status()
            Section("Coaching focus") {
                if summary.topCues.isEmpty { Text("Complete more reps to get coaching cues.").foregroundStyle(.secondary) }
                ForEach(Array(summary.topCues.enumerated()), id: \.offset) { _, cue in CoachingInstruction(text: cue, sport: sport, scope: sport + ":" + startedAt) }
            }
            Section("Your metrics and professional targets") {
                if let profile = state.profiles?.sports[sport] {
                    ForEach(profile.effective(for: summary.view).metrics, id: \.id) { spec in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(spec.label).font(.headline)
                            Text("You: \(Display.number(summary.metrics[spec.id]?.mean, unit: spec.unit))")
                            Text("Pro target: \(Display.number(spec.mean, unit: spec.unit)) ± \(Display.number(spec.tol, unit: spec.unit))")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let metric = summary.metrics[spec.id] {
                                Text("\(metric.n) reps · SD \(Display.number(metric.sd, unit: spec.unit))").font(.caption).foregroundStyle(.secondary)
                            }
                            ScoreBar(score: summary.metrics[spec.id]?.score)
                        }.padding(.vertical, 8)
                    }
                }
            }
            Section("Ignored motions") {
                let ignored = summary.rejected.values.reduce(0, +)
                Text("\(ignored) motion(s) ignored").font(.headline)
                if summary.rejected.isEmpty { Text("No motions were rejected.").foregroundStyle(.secondary) }
                ForEach(summary.rejected.keys.sorted(), id: \.self) { reason in
                    LabeledContent(reason.replacingOccurrences(of: "_", with: " ").capitalized,
                                   value: "\(summary.rejected[reason] ?? 0)")
                }
                Text("Only completed motions that pass the sport’s movement checks count as reps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !summary.types.isEmpty {
                Section("Rep types") {
                    ForEach(summary.types.keys.sorted(), id: \.self) { type in
                        LabeledContent(type.capitalized, value: "\(summary.types[type] ?? 0)")
                    }
                }
            }
            if let comparison = comparison {
                Section("Compared with your previous sessions") {
                    if let previous = comparison.previousAvgScore, let delta = comparison.scoreDelta {
                        Text(String(format: "%+.1f points", delta)).font(.title2.bold())
                        Text("Previous average \(Display.score(previous)) across \(comparison.previousSessions) sessions.")
                        Text(delta > 0 ? "Your session score improved." : (delta < 0 ? "Your session score decreased." : "Your session score stayed the same."))
                    } else { Text("This is your starting point. Future sessions will show your progress.") }
                    ComparisonRows(metrics: comparison.metrics)
                }
            }
            if let checkpoint = checkpoint {
                Section("Checkpoint \(checkpoint.number) completed") {
                    Text("\(checkpoint.sessions) sessions · \(checkpoint.totalReps) reps · Average \(Display.score(checkpoint.avgScore))")
                    ForEach(Array(checkpoint.focusCues.enumerated()), id: \.offset) { _, cue in CoachingInstruction(text: cue, sport: sport, scope: sport + ":" + startedAt) }
                }
            }
            if !reps.isEmpty {
                Section("Every counted rep") {
                    ForEach(Array(reps.enumerated()), id: \.offset) { index, rep in
                        DisclosureGroup("Rep \(index + 1) · \(rep.type.capitalized) · \(Display.score(rep.score))/100") {
                            ForEach(rep.metrics.keys.sorted(), id: \.self) { metric in
                                let spec = state.profiles?.sports[sport]?.effective(for: summary.view).metrics.first { $0.id == metric }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(spec?.label ?? metric)
                                    Text(Display.number(rep.metrics[metric], unit: spec?.unit ?? ""))
                                    ScoreBar(score: rep.scores[metric])
                                }.padding(.vertical, 8)
                            }
                            ForEach(Array(rep.cues.enumerated()), id: \.offset) { _, cue in CoachingInstruction(text: cue, sport: sport, scope: sport + ":" + startedAt) }
                        }
                    }
                }
            }
        }
    }
}
