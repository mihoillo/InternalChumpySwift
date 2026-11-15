import Foundation

/// One day of tunnel traffic: every session's counters summed into the day's
/// bucket. Ported from the Android client's `DailyTraffic`.
public struct DailyTraffic: Codable, Equatable {
    /// The local calendar's day ordinal; days are cut in the device's zone.
    public var epochDay: Int64
    /// Bytes the device received from the remote.
    public var rx: Int64
    /// Bytes the device sent to the remote.
    public var tx: Int64

    public init(epochDay: Int64, rx: Int64, tx: Int64) {
        self.epochDay = epochDay
        self.rx = rx
        self.tx = tx
    }
}

/// The week's daily traffic totals, kept across runs so the stats screen's
/// weekly chart survives restarts and disconnected days. Only aggregate byte
/// counts live here — no addresses, no keys, nothing the panel ever said.
/// A write a minute at most: the tunnel accumulates deltas in memory and
/// flushes them to today's bucket as the session runs. Ported from the
/// Android client's `DailyTrafficStore`; a file in the store directory plays
/// the cache file's role.
public final class DailyTrafficStore {

    private static let version = 1
    private static let fileName = "daily-traffic.json"

    private let file: URL
    private let queue = DispatchQueue(label: "slop.miho.chumpy.swift.dailytraffic")

    /// The local calendar the day buckets are cut on.
    private var calendar: Calendar

    public init(directory: URL = ChumpyConstant.storeDir, calendar: Calendar = .current) {
        self.file = directory.appendingPathComponent(Self.fileName)
        self.calendar = calendar
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    // MARK: - Days

    /// Today's bucket in the local zone.
    public func today(_ now: Date = Date()) -> Int64 {
        Self.epochDay(of: now, calendar: calendar)
    }

    /// The last seven days' buckets, oldest first; missing days simply are
    /// not in the list.
    public func readWeek(now: Date = Date()) -> [DailyTraffic] {
        queue.sync {
            let raw = readRaw()
            let firstDay = Self.epochDay(of: now, calendar: calendar) - 6
            return raw
                .filter { (firstDay...(firstDay + 6)).contains($0.epochDay) && $0.rx >= 0 && $0.tx >= 0 }
                .sorted { $0.epochDay < $1.epochDay }
        }
    }

    /// Adds `rx`/`tx` to today's bucket, keeps at most the last seven days,
    /// and returns the fresh week.
    @discardableResult
    public func addToday(rx: Int64, tx: Int64, now: Date = Date()) -> [DailyTraffic] {
        addDay(Self.epochDay(of: now, calendar: calendar), rx: rx, tx: tx, now: now)
    }

    /// The testable core of `addToday`: a day that is not within the last
    /// seven is a caller's mistake and lands nowhere.
    @discardableResult
    public func addDay(
        _ epochDay: Int64, rx: Int64, tx: Int64, now: Date = Date()
    ) -> [DailyTraffic] {
        queue.sync {
            let today = Self.epochDay(of: now, calendar: calendar)
            guard rx >= 0, tx >= 0,
                  (today - 6)...today ~= epochDay
            else { return readWeekLocked(now: now) }

            var days = readRaw()
            if let index = days.firstIndex(where: { $0.epochDay == epochDay }) {
                days[index].rx += rx
                days[index].tx += tx
            } else {
                days.append(DailyTraffic(epochDay: epochDay, rx: rx, tx: tx))
            }
            let week = days.sorted { $0.epochDay < $1.epochDay }.suffix(7)
            write(Array(week))
            return Array(week)
        }
    }

    // MARK: - Storage

    private func readRaw() -> [DailyTraffic] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["version"] as? Int == Self.version,
              let raw = json["days"] as? [[String: Any]]
        else { return [] }
        return raw.compactMap { day in
            guard let epochDay = day["day"] as? Int64,
                  let rx = day["rx"] as? Int64,
                  let tx = day["tx"] as? Int64
            else { return nil }
            return DailyTraffic(epochDay: epochDay, rx: rx, tx: tx)
        }
    }

    private func write(_ week: [DailyTraffic]) {
        let days = week.map { day -> [String: Any] in
            ["day": day.epochDay, "rx": day.rx, "tx": day.tx]
        }
        let json: [String: Any] = ["version": Self.version, "days": days]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private func readWeekLocked(now: Date) -> [DailyTraffic] {
        let firstDay = Self.epochDay(of: now, calendar: calendar) - 6
        return readRaw()
            .filter { (firstDay...(firstDay + 6)).contains($0.epochDay) }
            .sorted { $0.epochDay < $1.epochDay }
    }

    private static func epochDay(of date: Date, calendar: Calendar) -> Int64 {
        // The calendar's own day ordinal, not a UTC bucket: days are cut in
        // the device's zone, and a DST day is 23 or 25 hours long — an
        // 86400-based bucket would merge two local days once a year.
        guard let ordinal = calendar.ordinality(of: .day, in: .era, for: date) else {
            return Int64(date.timeIntervalSince1970 / 86_400)
        }
        return Int64(ordinal)
    }
}
