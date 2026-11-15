import XCTest
@testable import ChumpyCore

/// SubscriptionEntity lifecycle over the file store — the merge semantics ported
/// from the Android client's `SubscriptionRepository`.
final class SubscriptionStoreTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: ProfileStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("subs-\(UUID().uuidString)", isDirectory: true)
        suiteName = "test.subs.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ProfileStore(directory: directory, defaults: defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        super.tearDown()
    }

    private let linkOne = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@one.example.com:443?security=tls#One"
    private let linkTwo = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@two.example.com:443?security=tls#Two"
    private let linkThree = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@three.example.com:443?security=tls#Three"

    private var emptyMetadata: SubscriptionMetadata { SubscriptionMetadata() }

    func testAddSubscriptionStampsRowsWithIdentity() throws {
        let sub = try store.addSubscription(
            url: "https://panel.example.com/sub",
            body: "\(linkOne)\n\(linkTwo)",
            metadata: emptyMetadata
        )
        XCTAssertEqual("panel.example.com", sub.name)
        XCTAssertEqual("https://panel.example.com/sub", sub.url)
        XCTAssertNotNil(sub.lastUpdateSuccess)

        let rows = store.profiles(ofSubscription: sub.id)
        XCTAssertEqual(["One", "Two"], rows.map(\.remarks))
        XCTAssertEqual([0, 1], rows.map(\.order))
        XCTAssertFalse(rows.contains { $0.linkKey.isEmpty })
        // The store's whole list is the subscription's rows plus nothing else.
        XCTAssertEqual(2, store.profiles().count)
    }

    func testAddSubscriptionNameFallsBackToHeaderTitle() throws {
        var metadata = SubscriptionMetadata()
        metadata.title = "Panel's own name"
        let sub = try store.addSubscription(
            url: "https://panel.example.com/sub", body: linkOne, metadata: metadata
        )
        XCTAssertEqual("Panel's own name", sub.name)
    }

    func testAddSubscriptionPrefersExplicitName() throws {
        var metadata = SubscriptionMetadata()
        metadata.title = "Panel's own name"
        let sub = try store.addSubscription(
            url: "https://panel.example.com/sub",
            name: "My panel",
            body: linkOne,
            metadata: metadata
        )
        XCTAssertEqual("My panel", sub.name)
    }

    func testAddSubscriptionRejectsUnparsableBody() {
        XCTAssertThrowsError(
            try store.addSubscription(url: "https://x.example.com", body: "hello", metadata: emptyMetadata)
        )
    }

    func testAddSubscriptionMergesHeaderGeodataSources() throws {
        var metadata = SubscriptionMetadata()
        metadata.geodataSources = #"{"geosite.dat": "https://cdn.example.com/geosite.dat"}"#
        let sub = try store.addSubscription(url: "https://x.example.com", body: linkOne, metadata: metadata)
        XCTAssertEqual(
            ["geosite.dat": "https://cdn.example.com/geosite.dat"],
            GeodataSources.parseSafely(
                store.profiles(ofSubscription: sub.id).first?.geodataSources ?? ""
            )
        )
    }

    func testUpdateCarriesIdentityOverByLinkKey() throws {
        let sub = try store.addSubscription(
            url: "https://panel.example.com/sub",
            body: "\(linkOne)\n\(linkTwo)",
            metadata: emptyMetadata
        )
        // The user's state on the surviving rows.
        let firstID = store.profiles(ofSubscription: sub.id)[0].id
        var rows = store.profiles()
        rows[0].testDelayMillis = 123
        rows[0].pinned = true
        rows[0].concealed = true
        rows[0].lastUsedAt = Date()
        store.saveProfiles(rows)

        var metadata = SubscriptionMetadata()
        metadata.title = "Renamed panel"
        metadata.uploadBytes = 100
        metadata.totalBytes = 1000
        // One survives, one falls away, one is new.
        try store.updateSubscription(
            id: sub.id, body: "\(linkOne)\n\(linkThree)", metadata: metadata
        )

        let updatedSub = store.subscription(byID: sub.id)
        XCTAssertEqual("Renamed panel", updatedSub?.name)
        XCTAssertEqual(1000, updatedSub?.totalBytes)

        let rowsAfter = store.profiles(ofSubscription: sub.id)
        XCTAssertEqual(["One", "Three"], rowsAfter.map(\.remarks))
        XCTAssertEqual([0, 1], rowsAfter.map(\.order))
        // The survivor kept its identity and the user's state; the new row is fresh.
        let survivor = rowsAfter[0]
        XCTAssertEqual(firstID, survivor.id)
        XCTAssertEqual(123, survivor.testDelayMillis)
        XCTAssertEqual(true, survivor.pinned)
        XCTAssertEqual(true, survivor.concealed)
        XCTAssertNotNil(survivor.lastUsedAt)
        XCTAssertNil(rowsAfter[1].testDelayMillis)
        XCTAssertNotEqual(firstID, rowsAfter[1].id)
        // The fallen-away row is gone wholesale.
        XCTAssertFalse(store.profiles().contains { $0.remarks == "Two" })
    }

    func testUpdateUnknownSubscriptionThrows() {
        XCTAssertThrowsError(
            try store.updateSubscription(id: "gone", body: linkOne, metadata: emptyMetadata)
        )
    }

    func testMarkSubscriptionUpdateFailedLandsOnTheCard() throws {
        let sub = try store.addSubscription(url: "https://x.example.com", body: linkOne, metadata: emptyMetadata)
        store.markSubscriptionUpdateFailed(id: sub.id, message: "HTTP 500")
        let card = store.subscription(byID: sub.id)
        XCTAssertEqual("HTTP 500", card?.lastError)
        XCTAssertNotNil(card?.lastUpdateAttempt)
        // The failed refresh does not erase the last successful one.
        XCTAssertNotNil(card?.lastUpdateSuccess)
    }

    func testDeleteSubscriptionDropsRowsButKeepsManual() throws {
        let sub = try store.addSubscription(url: "https://x.example.com", body: linkOne, metadata: emptyMetadata)
        try store.addManualProfiles(linkThree)

        store.deleteSubscription(id: sub.id)
        XCTAssertEqual(0, store.profiles(ofSubscription: sub.id).count)
        XCTAssertEqual(0, store.subscriptions().count)
        XCTAssertEqual(["Three"], store.profiles().map(\.remarks))
    }

    // MARK: - Fetcher URL helpers

    func testNormalizeURLDefaultsToHTTPS() {
        XCTAssertEqual("https://panel.example.com/sub", SubscriptionFetcher.normalizeURL("panel.example.com/sub"))
        XCTAssertEqual("https://panel.example.com/sub", SubscriptionFetcher.normalizeURL("  https://panel.example.com/sub "))
        XCTAssertEqual("http://panel.example.com/sub", SubscriptionFetcher.normalizeURL("http://panel.example.com/sub"))
        XCTAssertEqual("HTTPS://PANEL.example.com/sub", SubscriptionFetcher.normalizeURL("HTTPS://PANEL.example.com/sub"))
    }

    func testHostNameOf() {
        XCTAssertEqual("panel.example.com", SubscriptionFetcher.hostName(of: "panel.example.com/sub"))
        XCTAssertEqual("x.example.com", SubscriptionFetcher.hostName(of: "https://x.example.com/token"))
    }
}
