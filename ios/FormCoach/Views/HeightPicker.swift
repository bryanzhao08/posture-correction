import SwiftUI
import FormCore

/// Height entry in cm or feet and inches. 0 means not set.
struct HeightPicker: View {
    @Binding var heightCm: Double
    let metric: Bool
    let config: PlayerConfig
    private var options: [Int] {
        metric ? Array(Int(config.minHeightCm)...Int(config.maxHeightCm))
               : Array(Int((config.minHeightCm / 2.54).rounded(.up))...Int(config.maxHeightCm / 2.54))
    }
    var body: some View {
        Picker("Height", selection: Binding(
            get: { heightCm > 0 ? (metric ? Int(heightCm.rounded()) : Int((heightCm / 2.54).rounded())) : 0 },
            set: { heightCm = $0 == 0 ? 0 : (metric ? Double($0) : Double($0) * 2.54) })) {
            Text("Not set").tag(0)
            ForEach(options, id: \.self) { v in
                Text(metric ? "\(v) cm" : "\(v / 12)′\(v % 12)″").tag(v)
            }
        }.accessibilityIdentifier("player.height")
    }
}
