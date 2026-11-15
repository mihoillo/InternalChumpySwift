import SwiftUI
import ChumpyCore

/// Stats tab, ported from the Android client's `StatsScreen` layout: the
/// week daily bars card first, the session's own traffic total, and the core
/// log — each a 28dp tonal card with an icon'd header line.
struct StatsView: View {
    @State private var lines: [String] = ChumpyLog.shared.all
    @State private var traffic: String = "0 bytes"
    @State private var week: [DailyTraffic] = []

    private let ticker = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavHost {
            ScrollView {
                VStack(spacing: 12) {
                    WeekTrafficCard(week: week)

                    ChartHeader(icon: "arrow.down.circle", title: "stats.trafficTotal")
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    totalTrafficCard

                    ChartHeader(icon: "doc.text", title: "stats.coreLog")
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    coreLogCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .navigationTitle("tab.stats")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { reload() }
        .onReceive(ticker) { _ in
            lines = ChumpyLog.shared.all
            reload()
        }
    }

    private func reload() {
        let bytes = ChumpyConstant.sharedDefaults
            .double(forKey: ChumpyConstant.Keys.statsBytesTotal)
        traffic = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .binary)
        week = DailyTrafficStore().readWeek()
    }

    // MARK: - Cards

    private var totalTrafficCard: some View {
        Text(traffic)
            .font(.system(size: 28, weight: .semibold))
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .chumpyCard()
    }

    private var coreLogCard: some View {
        Group {
            if lines.isEmpty {
                Text("stats.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated().reversed()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16)
        .chumpyCard()
    }
}

// MARK: - Chart header

/// The chart card's own header: the icon and the title on one line, the way
/// the Android client's `ChartHeader` wears it.
struct ChartHeader: View {
    let icon: String
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Week chart card

/// The last seven days' traffic as stacked bars — received over sent, both
/// directions of every session folded into the day's bucket, on the
/// card with its own header. iOS 15 has no Charts framework; rectangles are
/// the whole chart.
private struct WeekTrafficCard: View {

    let week: [DailyTraffic]

    /// The bars' height budget, points.
    private let barHeight: CGFloat = 96
    private let barWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartHeader(icon: "calendar", title: "stats.week")
            if week.isEmpty {
                Text("stats.week.empty")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(days, id: \.epochDay) { day in
                            bar(day)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    Text(totalText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .chumpyCard()
    }

    /// The week with its missing days filled as zero buckets, oldest first —
    /// the chart stands at seven columns whatever happened.
    private var days: [DailyTraffic] {
        guard let last = week.last else { return [] }
        var byDay = Dictionary(week.map { ($0.epochDay, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<7)
            .map { offset -> DailyTraffic in
                let epochDay = last.epochDay - Int64(offset)
                return byDay.removeValue(forKey: epochDay)
                    ?? DailyTraffic(epochDay: epochDay, rx: 0, tx: 0)
            }
            .reversed()
    }

    private var totalText: String {
        let rx = week.reduce(Int64(0)) { $0 + $1.rx }
        let tx = week.reduce(Int64(0)) { $0 + $1.tx }
        return String(
            format: NSLocalizedString("stats.week.total", bundle: .main, comment: ""),
            ByteCountFormatter.string(fromByteCount: rx + tx, countStyle: .binary),
            ByteCountFormatter.string(fromByteCount: rx, countStyle: .binary),
            ByteCountFormatter.string(fromByteCount: tx, countStyle: .binary)
        )
    }

    private var barPeak: Int64 {
        max(week.map { $0.rx + $0.tx }.max() ?? 1, 1)
    }

    private func bar(_ day: DailyTraffic) -> some View {
        let rxHeight = barHeight * CGFloat(day.rx) / CGFloat(barPeak)
        let txHeight = barHeight * CGFloat(day.tx) / CGFloat(barPeak)
        let idle = day.rx + day.tx == 0
        return VStack(spacing: 4) {
            VStack(spacing: 0) {
                // Received over sent — the way the tunnel counts the two
                // directions of the session.
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Chumpy.accent.opacity(0.85))
                    .frame(width: barWidth, height: max(rxHeight, 2))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: barWidth, height: max(txHeight, 0))
            }
            .frame(width: barWidth, height: barHeight, alignment: .bottom)
            .opacity(idle ? 0.25 : 1)
            Text(dayLabel(day))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func dayLabel(_ day: DailyTraffic) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: Self.date(of: day))
    }

    /// The calendar ordinal is not an epoch day; recover the date by
    /// counting back from today's ordinal on the same calendar.
    private static func date(of day: DailyTraffic) -> Date {
        let calendar = Calendar.current
        let todayOrdinal = calendar.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let offset = todayOrdinal - Int(day.epochDay)
        return calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
    }
}
