#if DEBUG
import SwiftUI

@MainActor struct DemoGallery: View {
    @EnvironmentObject private var state:AppState
    @EnvironmentObject private var presenter:DemoPresenter
    @State private var query=""
    private let sports=["basketball","golf","pickleball","tennis"]
    private func entries(_ sport:String) -> [DemoCue] {
        let setup=DemoCatalog.entry(state.profiles?.sports[sport]?.camera ?? "",sport:sport,setup:true)!
        return ([setup]+DemoCatalog.cues.filter { $0.sport == sport }.sorted { $0.key < $1.key })
            .filter { query.isEmpty || $0.key.localizedCaseInsensitiveContains(query) || $0.meaning.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            Section { Text("Review all 40 demonstrations. Key moment pauses the movement at the cue's comparison phase; Replay returns to synchronized motion.").font(.subheadline) }
            ForEach(sports.filter { !entries($0).isEmpty },id:\.self) { sport in
                Section(sport.capitalized) {
                    ForEach(entries(sport)) { cue in
                        Button { DemoOffers.shared.isPresenting=true; presenter.cue=cue } label: {
                            VStack(alignment:.leading,spacing:4) {
                                Text(cue.key).font(.subheadline.monospaced())
                                Text(cue.meaning).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,5)
                        }.accessibilityIdentifier("gallery."+cue.key)
                    }
                }
            }
        }.navigationTitle("Demo gallery")
            .searchable(text:$query,placement:.navigationBarDrawer(displayMode:.always),prompt:"Search demos")
    }
}
#endif
