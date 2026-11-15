import XCTest
@testable import ChumpyCore

/// The connection settings store: round-trip and defaults.
final class ConnectionStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.connection.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testCurrentIsDefaultWhenNeverWritten() {
        let settings = ConnectionStore.current(defaults: defaults)
        XCTAssertNil(settings.selectedSubscriptionID)
        XCTAssertNil(settings.selectedProfileID)
        XCTAssertEqual(RoutingMode.global, settings.routingMode)
        XCTAssertEqual(XrayConfigBuilder.defaultTestURL, settings.testURL)
    }

    func testRoundTripKeepsEveryField() {
        var settings = ConnectionSettings()
        settings.selectedSubscriptionID = "sub-1"
        settings.selectedProfileID = "profile-1"
        settings.routingMode = .ru
        settings.testURL = "https://example.com/204"
        ConnectionStore.update(settings, defaults: defaults)

        let read = ConnectionStore.current(defaults: defaults)
        XCTAssertEqual("sub-1", read.selectedSubscriptionID)
        XCTAssertEqual("profile-1", read.selectedProfileID)
        XCTAssertEqual(RoutingMode.ru, read.routingMode)
        XCTAssertEqual("https://example.com/204", read.testURL)
    }

    func testEmptyTestURLFallsBackToDefault() {
        var settings = ConnectionSettings()
        settings.testURL = ""
        ConnectionStore.update(settings, defaults: defaults)
        XCTAssertEqual(
            XrayConfigBuilder.defaultTestURL,
            ConnectionStore.current(defaults: defaults).testURL
        )
    }

    func testUpdateTransformAppliesAndPersists() {
        ConnectionStore.update(defaults: defaults) { $0.selectedProfileID = "p-9" }
        XCTAssertEqual("p-9", ConnectionStore.current(defaults: defaults).selectedProfileID)
    }
}
