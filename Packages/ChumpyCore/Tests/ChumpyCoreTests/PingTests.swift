import XCTest
@testable import ChumpyCore

/// The delay-measurement document: the bare test config plus the loopback
/// SOCKS inbound the measuring fetch rides through, and the store method
/// that lands measured pings on rows.
final class PingConfigTests: XCTestCase {

    private var profile: Profile {
        var p = Profile(id: "1", type: .vless)
        p.remarks = "Reality exit"
        p.server = "reality.example.com"
        p.serverPort = 443
        p.password = "b831381d-6324-4d53-ad4f-8cda48b30811"
        p.network = "tcp"
        p.security = "reality"
        p.sni = "www.microsoft.com"
        return p
    }

    private func objectOf(_ config: String) throws -> [String: Any] {
        let data = try JSONSerialization.jsonObject(with: Data(config.utf8))
        return try XCTUnwrap(data as? [String: Any])
    }

    func testBuildPingInjectsLoopbackSocksInbound() throws {
        let config = try objectOf(XrayConfigBuilder.buildPing(profile, socksPort: 12345))
        let inbounds = try XCTUnwrap(config["inbounds"] as? [[String: Any]])
        XCTAssertEqual(1, inbounds.count)
        XCTAssertEqual("socks", inbounds[0]["protocol"] as? String)
        XCTAssertEqual("127.0.0.1", inbounds[0]["listen"] as? String)
        XCTAssertEqual(12345, inbounds[0]["port"] as? Int)

        // The rest of the bare document stands untouched.
        let outbounds = try XCTUnwrap(config["outbounds"] as? [[String: Any]])
        XCTAssertEqual(1, outbounds.count)
        XCTAssertEqual(XrayConfigBuilder.proxyTag, outbounds[0]["tag"] as? String)
        let routing = try XCTUnwrap(config["routing"] as? [String: Any])
        let rules = try XCTUnwrap(routing["rules"] as? [Any])
        XCTAssertEqual(0, rules.count)
    }

    func testBuildTestItselfHasNoInbounds() throws {
        let config = try objectOf(XrayConfigBuilder.buildTest(profile))
        let inbounds = try XCTUnwrap(config["inbounds"] as? [Any])
        XCTAssertEqual(0, inbounds.count)
    }

    func testPingProxyURL() {
        XCTAssertEqual("socks5://127.0.0.1:1080", XrayConfigBuilder.pingProxyURL(port: 1080))
    }
}

/// Measured pings landing on profile rows. Ported from the Android client's
/// `profiles.setDelay` semantics: identity untouched, nil = tested but
/// unreachable.
final class ProfileDelayTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: ProfileStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("delays-\(UUID().uuidString)", isDirectory: true)
        suiteName = "test.delays.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ProfileStore(directory: directory, defaults: defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        super.tearDown()
    }

    private func row(_ remarks: String) -> Profile {
        var p = Profile(id: UUID().uuidString, type: .vless)
        p.remarks = remarks
        p.server = "\(remarks).example.com"
        p.serverPort = 443
        p.password = "b831381d-6324-4d53-ad4f-8cda48b30811"
        return p
    }

    func testDelaysLandOnTheirOwnRowsOnly() throws {
        let one = row("one")
        let two = row("two")
        store.saveProfiles([one, two])

        let testedAt = Date(timeIntervalSince1970: 1_800_000_000)
        store.setProfileDelays([(id: one.id, delay: 123)], testedAt: testedAt)

        let rows = store.profiles()
        XCTAssertEqual(123, rows.first { $0.id == one.id }?.testDelayMillis)
        XCTAssertEqual(testedAt, rows.first { $0.id == one.id }?.lastTestAt)
        XCTAssertNil(rows.first { $0.id == two.id }?.testDelayMillis)
        XCTAssertNil(rows.first { $0.id == two.id }?.lastTestAt)
    }

    func testNilDelayMarksTestedUnreachable() throws {
        let one = row("one")
        store.saveProfiles([one])
        let testedAt = Date()
        store.setProfileDelays([(id: one.id, delay: 500)], testedAt: testedAt)
        store.setProfileDelays([(id: one.id, delay: nil)], testedAt: testedAt)

        let row = try XCTUnwrap(store.profiles().first)
        XCTAssertNil(row.testDelayMillis)
        XCTAssertEqual(testedAt, row.lastTestAt)
    }

    func testEmptyResultsWriteNothing() throws {
        let one = row("one")
        store.saveProfiles([one])
        store.setProfileDelays([], testedAt: Date())
        XCTAssertNil(store.profiles().first?.lastTestAt)
    }

    func testUnknownIDsAreIgnored() throws {
        let one = row("one")
        store.saveProfiles([one])
        store.setProfileDelays([(id: "gone", delay: 1)], testedAt: Date())
        XCTAssertNil(store.profiles().first?.testDelayMillis)
    }

    func testDelaySurvivesSubscriptionRefreshByLinkKey() throws {
        let link = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@one.example.com:443?security=tls#One"
        let sub = try store.addSubscription(
            url: "https://panel.example.com/sub", body: link, metadata: SubscriptionMetadata()
        )
        let id = store.profiles(ofSubscription: sub.id)[0].id
        store.setProfileDelays([(id: id, delay: 321)], testedAt: Date())

        try store.updateSubscription(
            id: sub.id, body: link, metadata: SubscriptionMetadata()
        )
        XCTAssertEqual(321, store.profiles(ofSubscription: sub.id)[0].testDelayMillis)
    }
}
