import XCTest
@testable import ChumpyCore

/// The week's daily buckets: accumulation, the seven-day window and the
/// format's own guards. Ported from the Android client's
/// `DailyTrafficStoreTest` semantics; the day arithmetic runs on a fixed
/// UTC calendar so the buckets are deterministic.
final class DailyTrafficStoreTests: XCTestCase {

    private var directory: URL!
    private var store: DailyTrafficStore!
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("traffic-\(UUID().uuidString)", isDirectory: true)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        now = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 16, hour: 12)
        )
        store = DailyTrafficStore(directory: directory, calendar: calendar)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        super.tearDown()
    }

    private func date(daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: now)!
    }

    func testReadWeekEmptyWithoutFile() {
        XCTAssertEqual([], store.readWeek(now: now))
    }

    func testAddTodayAccumulates() {
        _ = store.addToday(rx: 100, tx: 50, now: now)
        let week = store.addToday(rx: 30, tx: 20, now: now)
        XCTAssertEqual(1, week.count)
        XCTAssertEqual(store.today(now), week[0].epochDay)
        XCTAssertEqual(130, week[0].rx)
        XCTAssertEqual(70, week[0].tx)

        let reread = store.readWeek(now: now)
        XCTAssertEqual([130], reread.map(\.rx))
    }

    func testDistinctDaysLandInDistinctBuckets() {
        _ = store.addToday(rx: 100, tx: 0, now: now)
        let yesterday = date(daysAgo: 1)
        _ = store.addToday(rx: 200, tx: 0, now: yesterday)
        let week = store.readWeek(now: now)
        XCTAssertEqual(2, week.count)
        XCTAssertEqual(store.today(yesterday), week[0].epochDay)
        XCTAssertEqual(200, week[0].rx)
        XCTAssertEqual(100, week[1].rx)
    }

    func testOlderThanAWeekFallsOff() {
        for daysAgo in 0...7 {
            _ = store.addDay(
                store.today(date(daysAgo: daysAgo)), rx: Int64(daysAgo + 1), tx: 0, now: now
            )
        }
        let week = store.readWeek(now: now)
        XCTAssertEqual(7, week.count)
        // The eight-day-old bucket (rx = 8) never landed; the list is
        // oldest first, so today (rx = 1) is the last.
        XCTAssertEqual([7, 6, 5, 4, 3, 2, 1], week.map(\.rx))
    }

    func testAddDayRejectsOlderThanAWeek() {
        let week = store.addDay(
            store.today(date(daysAgo: 10)), rx: 999, tx: 999, now: now
        )
        XCTAssertEqual([], week)
        XCTAssertEqual([], store.readWeek(now: now))
    }

    func testAddDayRejectsNegativeBytes() {
        _ = store.addToday(rx: 10, tx: 0, now: now)
        let week = store.addDay(store.today(now), rx: -1, tx: 0, now: now)
        XCTAssertEqual([10], week.map(\.rx))
    }

    func testCorruptFileReadsAsEmpty() {
        try? Data("not json".utf8).write(to: directory.appendingPathComponent("daily-traffic.json"))
        XCTAssertEqual([], store.readWeek(now: now))
    }

    func testWrongVersionReadsAsEmpty() {
        let json = #"{"version": 99, "days": [{"day": 1, "rx": 5, "tx": 5}]}"#
        try? Data(json.utf8).write(to: directory.appendingPathComponent("daily-traffic.json"))
        XCTAssertEqual([], store.readWeek(now: now))
    }
}
