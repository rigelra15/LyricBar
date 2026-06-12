import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ticker: LyricTicker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LyricBar")
                .font(.headline)

            Text(ticker.current.isEmpty ? "—" : ticker.current)
                .font(.title3)
                .bold()
                .lineLimit(2)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(LyricTicker())
}
