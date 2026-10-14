import SwiftUI
import FormCore

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
                if card.sport == "tennis" {
                    Text(StrokeEstimate.display(card.rep.strokeEstimate)?.text ?? "Stroke unclear · estimate")
                        .font(.caption2).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("rep.stroke.estimate")
                }
                Text("Rep \(card.index) · \(Display.score(card.rep.score))").font(.caption).monospacedDigit()
            }.padding(6).background(.black.opacity(0.85),in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain).accessibilityIdentifier("rep.feedback.card")
            .accessibilityLabel("Last rep \(card.index), \(card.shortLabel), score \(Display.score(card.rep.score)). Open correction" + (card.sport == "tennis" ? ". " + (StrokeEstimate.display(card.rep.strokeEstimate)?.text ?? "Stroke unclear · estimate") : ""))
    }
}
struct RepFeedbackDetail: View {
    let card: RepCard
    var replay:ReplaySelection? = nil
    @State private var showReplay=false
    @State private var showMotion=true
    private var hasMotion: Bool { card.corrected != nil && card.motion.count > 1 }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if hasMotion {
                        Picker("View", selection:$showMotion) {
                            Text("Replay").tag(true)
                            Text("Key moment").tag(false)
                        }.pickerStyle(.segmented).accessibilityIdentifier("rep.feedback.mode")
                    }
                    if hasMotion && showMotion {
                        MotionFixReplay(card:card).frame(maxHeight:440)
                        HStack(spacing:6) {
                            Capsule().fill(Color(red:1,green:0.35,blue:0.37)).frame(width:16,height:4)
                            Text("What you did")
                            Capsule().fill(Color(red:0.24,green:0.86,blue:0.52)).frame(width:16,height:4).padding(.leading,8)
                            Text("What to do")
                        }.font(.caption)
                        Text("Your recorded rep at half speed").font(.caption).foregroundStyle(.secondary)
                    } else {
                        RepFreezeFrame(card:card).frame(maxHeight:440)
                    }
                    if replay != nil { Button("Play replay") { showReplay=true }.buttonStyle(.borderedProminent).accessibilityIdentifier("rep.feedback.replay") }
                    Text(card.shortLabel).font(.title2.bold())
                    Text("Rep \(card.index) · Score \(Display.score(card.rep.score))").font(.headline)
                    if !(hasMotion && showMotion) {
                        Text(card.corrected == nil ? "Your pose (white)" : "Your pose (white) vs the fix (cyan)").font(.caption)
                    }
                    CoachingInstruction(text:card.cue,sport:card.sport,scope:"rep.\(card.id)")
                    if let cue=DemoCatalog.entry(card.cue,sport:card.sport,setup:false) { Text(cue.meaning).foregroundStyle(.secondary) }
                }.padding()
            }.navigationTitle("Last rep").navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("rep.feedback.detail")
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("rep.feedback.close") } }
        }.modifier(DemoPresentation())
            .fullScreenCover(isPresented:$showReplay) { if let replay=replay { ReplayView(selection:replay) } }
    }
}
