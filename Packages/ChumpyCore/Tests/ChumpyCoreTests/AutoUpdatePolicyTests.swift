import XCTest
@testable import ChumpyCore

/// The auto-update schedule's arithmetic: the interval clamp, the due date
/// and the next refresh date the background task is scheduled at. Ported
/// from the Android client's constants; the due-date semantics are the
/// `scheduleAutoUpdate`/`Worker` pair's.
final class AutoUpdatePolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testEffectiveIntervalHours() {
        XCTAssertEqual(AutoUpdatePolicy.defaultHours, AutoUpdatePolicy.effectiveIntervalHours(nil))
        XCTAssertEqual(AutoUpdatePolicy.defaultHours, AutoUpdatePolicy.effectiveIntervalHours(0))
        XCTAssertEqual(AutoUpdatePolicy.defaultHours, AutoUpdatePolicy.effectiveIntervalHours(-5))
        XCTAssertEqual(1, AutoUpdatePolicy.effectiveIntervalHours(1))
        XCTAssertEqual(5, AutoUpdatePolicy.effectiveIntervalHours(5))
        XCTAssertEqual(24, AutoUpdatePolicy.effectiveIntervalHours(24))
        XCTAssertEqual(AutoUpdatePolicy.maxHours, AutoUpdatePolicy.effectiveIntervalHours(400))
        XCTAssertEqual(AutoUpdatePolicy.minHours, AutoUpdatePolicy.effectiveIntervalHours(1))
    }

    private func subscription(
        autoUpdate: Bool = true,
        intervalHours: Int? = nil,
        lastSuccess: Date? = nil,
        lastAttempt: Date? = nil,
        created: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> SubscriptionEntity {
        SubscriptionEntity(
            id: "s",
            name: "s",
            url: "https://x.example.com",
            createdAt: created,
            lastUpdateAttempt: lastAttempt,
            lastUpdateSuccess: lastSuccess,
            updateIntervalHours: intervalHours,
            autoUpdate: autoUpdate
        )
    }

    func testDueDateUsesLastSuccessAndInterval() {
        let sub = subscription(
            intervalHours: 12,
            lastSuccess: now.addingTimeInterval(-6 * 3600)
        )
        XCTAssertEqual(
            now.addingTimeInterval(6 * 3600),
            AutoUpdatePolicy.dueDate(of: sub)
        )
    }

    func testDueDateFallsBackToAttemptThenCreation() {
        let attemptOnly = subscription(
            intervalHours: 24,
            lastSuccess: nil,
            lastAttempt: now.addingTimeInterval(-3600)
        )
        XCTAssertEqual(
            now.addingTimeInterval(23 * 3600),
            AutoUpdatePolicy.dueDate(of: attemptOnly)
        )

        let fresh = subscription(intervalHours: 24)
        XCTAssertEqual(
            fresh.createdAt.addingTimeInterval(24 * 3600),
            AutoUpdatePolicy.dueDate(of: fresh)
        )
    }

    func testIsDueRespectsToggleAndTime() {
        let due = subscription(
            intervalHours: 1,
            lastSuccess: now.addingTimeInterval(-2 * 3600)
        )
        XCTAssertTrue(AutoUpdatePolicy.isDue(due, now: now))

        let off = subscription(
            autoUpdate: false,
            intervalHours: 1,
            lastSuccess: now.addingTimeInterval(-2 * 3600)
        )
        XCTAssertFalse(AutoUpdatePolicy.isDue(off, now: now))

        let fresh = subscription(
            intervalHours: 24,
            lastSuccess: now.addingTimeInterval(-3600)
        )
        XCTAssertFalse(AutoUpdatePolicy.isDue(fresh, now: now))
    }

    func testNextRefreshDateIsTheSoonestDueDate() {
        let first = subscription(
            intervalHours: 24,
            lastSuccess: now.addingTimeInterval(-30 * 3600)
        )
        let second = subscription(
            intervalHours: 24,
            lastSuccess: now.addingTimeInterval(-5 * 3600)
        )
        // The soonest due date here lies in the past — the scheduler lead
        // is what stands between it and "as soon as the system allows".
        XCTAssertEqual(
            now.addingTimeInterval(AutoUpdatePolicy.schedulerLeadSeconds),
            AutoUpdatePolicy.nextRefreshDate([first, second], now: now)
        )
    }

    func testNextRefreshDateIgnoresNonAutoSubscriptions() {
        let off = subscription(
            autoUpdate: false,
            intervalHours: 24,
            lastSuccess: now.addingTimeInterval(-30 * 3600)
        )
        XCTAssertNil(AutoUpdatePolicy.nextRefreshDate([off], now: now))
        XCTAssertNil(AutoUpdatePolicy.nextRefreshDate([], now: now))
    }

    func testNextRefreshDateNeverCloserThanSchedulerLead() {
        let overdue = subscription(
            intervalHours: 1,
            lastSuccess: now.addingTimeInterval(-48 * 3600)
        )
        XCTAssertEqual(
            now.addingTimeInterval(AutoUpdatePolicy.schedulerLeadSeconds),
            AutoUpdatePolicy.nextRefreshDate([overdue], now: now)
        )
    }
}
