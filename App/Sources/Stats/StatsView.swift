import SwiftUI
import ChumpyCore

/// Stats tab: live tunnel log (core log ring buffer) and traffic total.
/// Charts and packet-loss graphs come in M4.
struct StatsView: View {
    @State private var lines: [String] = ChumpyLog.shared.all
    @State private var traffic: String = "0 bytes"

    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavHost {
            List {
                Section("stats.overview") {
                    LabeledRow(label: "stats.trafficTotal", value: traffic)
                }
                Section("stats.coreLog") {
                    if lines.isEmpty {
                        Text("stats.empty")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(lines.enumerated().reversed()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("tab.stats")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(ticker) { _ in
            lines = ChumpyLog.shared.all
            let bytes = ChumpyConstant.sharedDefaults
                .double(forKey: ChumpyConstant.Keys.statsBytesTotal)
            traffic = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
        }
    }
}

private struct LabeledRow: View {
    let label: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
