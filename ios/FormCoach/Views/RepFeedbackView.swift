import SwiftUI

struct RepFreezeFrame: View {
    let card: RepCard
    var body: some View {
        Image(uiImage:FeedbackDrawing.image(card)).resizable().scaledToFit()
            .scaleEffect(x:card.frame.mirrored ? -1 : 1,y:1)
            .accessibilityLabel(card.corrected == nil ? "Your pose in white" : "Your pose in white, suggested correction in cyan with arrows")
    }
}
struct LastRepCard: View {
    let card: RepCard
    let open: () -> Void
    var body: some View {
        Button(action:open) {
            VStack(alignment:.leading,spacing:4) {
                RepFreezeFrame(card:card)
                Text(card.shortLabel).font(.caption.bold()).lineLimit(3)
                Text("Rep \(card.index) · \(Display.score(card.rep.score))").font(.caption).monospacedDigit()
            }.padding(6).background(.black.opacity(0.85),in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).accessibilityIdentifier("rep.feedback.card")
            .accessibilityLabel("Last rep \(card.index), \(card.shortLabel), score \(Display.score(card.rep.score)). Open correction")
    }
}
struct RepFeedbackDetail: View {
    let card: RepCard
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    RepFreezeFrame(card:card).frame(maxHeight:440)
                    Text(card.shortLabel).font(.title2.bold())
                    Text("Rep \(card.index) · Score \(Display.score(card.rep.score))").font(.headline)
                    Text(card.corrected == nil ? "Your pose (white)" : "Your pose (white) vs the fix (cyan)").font(.caption)
                    CoachingInstruction(text:card.cue,sport:card.sport,scope:"rep.\(card.id)")
                    if let cue=DemoCatalog.entry(card.cue,sport:card.sport,setup:false) { Text(cue.meaning).foregroundStyle(.secondary) }
                }.padding()
            }.navigationTitle("Last rep").navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("rep.feedback.detail")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("rep.feedback.close") } }
        }.modifier(DemoPresentation())
    }
}
