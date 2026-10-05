import SwiftUI
import FormCore

struct DemoCue: Decodable, Identifiable {
    let key: String, sport: String, text: String, meaning: String
    let wrongMotion: String, correctMotion: String
    var id: String { key }
    enum CodingKeys: String, CodingKey { case key, sport, text, meaning; case wrongMotion = "wrong_motion", correctMotion = "correct_motion" }
}
enum DemoCatalog {
    static let cues: [DemoCue] = {
        guard let url = Bundle.main.url(forResource: "cue_catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let cues = try? JSONDecoder().decode([DemoCue].self, from: data) else {
            assertionFailure("Missing cue catalog"); return []
        }
        assert(Set(cues.map(\.key)).isSubset(of: Set(DemoMotionTable.entries.keys)), "Missing animation entry")
        assert(["golf", "basketball", "tennis", "pickleball"].allSatisfy { DemoMotionTable.entries["setup." + $0] != nil })
        return cues
    }()
    static func entry(_ text: String, sport: String, setup: Bool) -> DemoCue? {
        if setup {
            let view = text.hasPrefix("From behind") ? "back" : (text.hasPrefix("Side-on") ? "side" : "front")
            return DemoCue(key: "setup." + sport + (sport == "tennis" ? "." + view : ""), sport: sport, text: text,
            meaning: "Place the phone on a stable tripod with your whole body visible.",
            wrongMotion: "The phone is too low and close to the player.", correctMotion: text) }
        return cues.first { $0.sport == sport && $0.text == text }
    }
}
@MainActor final class DemoOffers: ObservableObject {
    static let shared = DemoOffers()
    @Published var declined: Set<String> = []
    var isPresenting = false
}
@MainActor struct CoachingInstruction: View {
    let text: String
    let sport: String
    let scope: String
    var setup = false
    @EnvironmentObject private var state: AppState
    @AppStorage("offerMovementDemos") private var offersEnabled = true
    @ObservedObject private var offers = DemoOffers.shared
    @EnvironmentObject private var presenter: DemoPresenter
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
            if offersEnabled, let cue = DemoCatalog.entry(text, sport: sport, setup: setup) {
                let declined = offers.declined.contains(scope + cue.key)
                if !declined { Text("Want to see what this means?").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Show me") { offers.isPresenting = true; presenter.cue = cue }
                        .accessibilityIdentifier("demo.show." + cue.key)
                    if !declined {
                        Button("Not now") { offers.declined.insert(scope + cue.key) }.foregroundStyle(.secondary)
                    }
                }.font(.subheadline).buttonStyle(.borderless).frame(minHeight: 44)
            }
        }
    }
}

@MainActor final class DemoPresenter: ObservableObject { @Published var cue: DemoCue? }
/// A stable host keeps a setup demo open when the live HUD transitions into counting.
@MainActor struct DemoPresentation: ViewModifier {
    @StateObject private var presenter = DemoPresenter()
    @EnvironmentObject private var state: AppState
    func body(content: Content) -> some View {
        content.environmentObject(presenter)
            .fullScreenCover(item: $presenter.cue, onDismiss: { DemoOffers.shared.isPresenting = false }) { cue in
                HologramDemo(cue: cue, leftHanded: state.user?.handedness == .left).id(cue.key)
            }
    }
}
