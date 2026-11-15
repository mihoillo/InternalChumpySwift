import XCTest
@testable import ChumpyCore

/// The servers list's four orders — the pins keep the ground floor under
/// every mode. Ported from the Android client's `ServersSort` tests.
final class ServersSortTests: XCTestCase {

    private func profile(
        id: String,
        order: Int = 0,
        remarks: String = "",
        delay: Int64? = nil,
        lastUsed: Date? = nil,
        pinned: Bool = false
    ) -> Profile {
        var p = Profile(id: id, type: .vless)
        p.order = order
        p.remarks = remarks
        p.testDelayMillis = delay
        p.lastUsedAt = lastUsed
        p.pinned = pinned
        return p
    }

    private func order(_ mode: ServersSort, _ rows: [Profile]) -> [String] {
        rows.sorted { mode.isOrdered($0, before: $1) }.map { $0.id }
    }

    func testDefaultFollowsPanelOrderWithPinsFirst() {
        let rows = [
            profile(id: "b", order: 1),
            profile(id: "a", order: 0),
            profile(id: "pin", order: 9, pinned: true),
        ]
        XCTAssertEqual(["pin", "a", "b"], order(.default, rows))
    }

    func testNameIsCaseFolded() {
        let rows = [
            profile(id: "upper", order: 0, remarks: "Zulu"),
            profile(id: "lower", order: 1, remarks: "alpha"),
            profile(id: "mixed", order: 2, remarks: "Bravo"),
        ]
        XCTAssertEqual(["lower", "mixed", "upper"], order(.name, rows))
    }

    func testPingSortsNeverMeasuredToTheBottom() {
        let rows = [
            profile(id: "never", order: 0),
            profile(id: "slow", order: 1, delay: 400),
            profile(id: "fast", order: 2, delay: 20),
            profile(id: "pin", order: 9, delay: 900, pinned: true),
        ]
        XCTAssertEqual(["pin", "fast", "slow", "never"], order(.ping, rows))
    }

    func testLastUsedIsFreshestFirst() {
        let old = Date(timeIntervalSince1970: 100)
        let fresh = Date(timeIntervalSince1970: 500)
        let rows = [
            profile(id: "never", order: 0),
            profile(id: "old", order: 1, lastUsed: old),
            profile(id: "fresh", order: 2, lastUsed: fresh),
        ]
        XCTAssertEqual(["fresh", "old", "never"], order(.lastUsed, rows))
    }
}
