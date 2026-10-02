import SwiftUI

@MainActor
struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.callout).foregroundStyle(.primary)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
    }
}
@MainActor
struct ScoreBar: View {
    let score: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: min(100, max(0, score ?? 0)), total: 100)
                .tint(.accentColor)
            Text("\(Display.score(score)) / 100").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Metric score")
        .accessibilityValue(score.map { "\(Display.score($0)) out of 100" } ?? "No data")
    }
}
@MainActor
struct ComparisonRows: View {
    let metrics: [MetricComparison]
    var body: some View {
        ForEach(metrics) { metric in
            VStack(alignment: .leading, spacing: 8) {
                Text(metric.label).font(.headline)
                Text("You: \(Display.number(metric.value, unit: metric.unit)) · Pro: \(Display.number(metric.pro, unit: metric.unit))")
                    .font(.subheadline)
                if let previous = metric.previous {
                    Text("Previous: \(Display.number(previous, unit: metric.unit)) · \(metric.direction?.capitalized ?? "No comparison")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScoreBar(score: metric.score)
            }.padding(.vertical, 8)
        }
    }
}
