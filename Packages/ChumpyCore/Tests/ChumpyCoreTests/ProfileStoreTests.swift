import XCTest
@testable import ChumpyCore

/// The profile store: persistence, selection, balancer member resolution and
/// the manual import merge — the semantics ported from the Android client's
/// Room-backed repository.
final class ProfileStoreTests: XCTestCase {

    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: ProfileStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
        suiteName = "test.store.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ProfileStore(directory: directory, defaults: defaults)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        super.tearDown()
    }

    private func vless(_ server: String, remarks: String = "") -> Profile {
        var p = Profile(id: UUID().uuidString, type: .vless)
        p.remarks = remarks
        p.server = server
        p.serverPort = 443
        p.password = "b831381d-6324-4d53-ad4f-8cda48b30811"
        p.security = "tls"
        p.linkKey = p.computeLinkKey()
        return p
    }

    // MARK: - Persistence

    func testProfilesRoundTripThroughDisk() {
        store.saveProfiles([vless("one.example.com"), vless("two.example.com")])
        let fresh = ProfileStore(directory: directory, defaults: defaults)
        XCTAssertEqual(2, fresh.profiles().count)
        XCTAssertEqual("one.example.com", fresh.profiles().first?.server)
    }

    func testVisibleProfilesHideHiddenAndConcealed() {
        var hidden = vless("hidden.example.com")
        hidden.hidden = true
        var concealed = vless("concealed.example.com")
        concealed.concealed = true
        store.saveProfiles([vless("plain.example.com"), hidden, concealed])
        XCTAssertEqual(
            ["plain.example.com"],
            store.visibleProfiles().map(\.server)
        )
        // The store keeps them all; only the list hides them.
        XCTAssertEqual(3, store.profiles().count)
    }

    func testProfilesOfSubscriptionSplitsGroups() {
        var manual = vless("manual.example.com")
        manual.subscriptionID = nil
        var subbed = vless("sub.example.com")
        subbed.subscriptionID = "sub-1"
        store.saveProfiles([manual, subbed])
        XCTAssertEqual(
            ["manual.example.com"], store.profiles(ofSubscription: nil).map(\.server)
        )
        XCTAssertEqual(
            ["sub.example.com"], store.profiles(ofSubscription: "sub-1").map(\.server)
        )
    }

    // MARK: - Selection

    func testSelectedProfileFallsBackToFirstVisible() {
        store.saveProfiles([vless("one.example.com"), vless("two.example.com")])
        XCTAssertEqual("one.example.com", store.selectedProfile()?.server)
    }

    func testSelectProfilePersistsAndStampsLastUsed() {
        store.saveProfiles([vless("one.example.com"), vless("two.example.com")])
        store.selectProfile(id: store.profiles()[1].id)
        XCTAssertEqual("two.example.com", store.selectedProfile()?.server)
        XCTAssertNotNil(store.profile(byID: store.profiles()[1].id)?.lastUsedAt)
        // The choice survives a fresh store.
        XCTAssertEqual(
            "two.example.com",
            ProfileStore(directory: directory, defaults: defaults).selectedProfile()?.server
        )
    }

    func testSelectedProfileIgnoresMissingID() {
        store.saveProfiles([vless("one.example.com")])
        var settings = ConnectionSettings()
        settings.selectedProfileID = "gone"
        ConnectionStore.update(settings, defaults: defaults)
        XCTAssertEqual("one.example.com", store.selectedProfile()?.server)
    }

    // MARK: - Balancer members

    private func subbed(_ server: String, subscriptionID: String = "sub-1") -> Profile {
        var p = vless(server)
        p.subscriptionID = subscriptionID
        return p
    }

    private func balancerOver(_ members: [Profile], strategy: String = "random",
                              subscriptionID: String? = nil) -> Profile {
        var balancer = Profile(id: UUID().uuidString, subscriptionID: subscriptionID, type: .balancer)
        balancer.remarks = "Автовыбор"
        balancer.balancerStrategy = strategy
        balancer.balancerMembers = members.map(\.linkKey).joined(separator: "\n")
        return balancer
    }

    func testBalancerMembersResolveByLinkKey() {
        let first = subbed("first.example.com")
        let second = subbed("second.example.com")
        let balancer = balancerOver([first, second], subscriptionID: "sub-1")
        store.saveProfiles([first, second, balancer])
        XCTAssertEqual(
            ["first.example.com", "second.example.com"],
            store.resolvedMembers(for: balancer).map(\.server)
        )
    }

    func testFallenAwayMembersDegradeToWholeSubscription() {
        let first = subbed("first.example.com")
        let orphan = subbed("orphan.example.com")
        let balancer = balancerOver([first], subscriptionID: "sub-1")
        store.saveProfiles([first, orphan, balancer])
        XCTAssertEqual(
            ["first.example.com", "orphan.example.com"],
            store.resolvedMembers(for: balancer).map(\.server)
        )
    }

    func testPlainProfileResolvesNoMembers() {
        let profile = vless("plain.example.com")
        XCTAssertEqual(0, store.resolvedMembers(for: profile).count)
    }

    // MARK: - Manual import

    func testAddManualProfilesInsertsFreshRows() throws {
        let added = try store.addManualProfiles(
            "vless://b831381d-6324-4d53-ad4f-8cda48b30811@one.example.com:443?security=tls#One\n"
                + "vless://b831381d-6324-4d53-ad4f-8cda48b30811@two.example.com:443?security=tls#Two"
        )
        XCTAssertEqual(2, added)
        XCTAssertEqual(2, store.profiles().count)
        XCTAssertEqual("One", store.profiles().first?.remarks)
        XCTAssertNil(store.profiles().first?.subscriptionID)
        XCTAssertEqual(0, store.profiles().first?.order)
        XCTAssertEqual(1, store.profiles().last?.order)
    }

    func testSecondImportSkipsDuplicates() throws {
        let link = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@one.example.com:443?security=tls#One"
        XCTAssertEqual(1, try store.addManualProfiles(link))
        XCTAssertEqual(0, try store.addManualProfiles(link))
        XCTAssertEqual(1, store.profiles().count)
    }

    func testImportUnhidesHiddenMemberAndRefreshesBalancerColumns() throws {
        // A hidden member (a balancer's own row) comes back when re-imported.
        var hidden = vless("member.example.com")
        hidden.hidden = true
        store.saveProfiles([hidden])
        XCTAssertEqual(1, store.profiles().count)

        let link = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@member.example.com:443?security=tls#Member"
        XCTAssertEqual(1, try store.addManualProfiles(link))
        let rows = store.profiles()
        XCTAssertEqual(1, rows.count)
        XCTAssertFalse(rows[0].hidden)
        XCTAssertEqual("Member", rows[0].remarks)
    }

    func testImportRejectsUnrecognizableText() {
        XCTAssertThrowsError(try store.addManualProfiles("hello world"))
    }

    // MARK: - Deletion

    func testDeleteManualProfileKeepsReferencedMembers() {
        let member = vless("member.example.com")
        let balancer = balancerOver([member])  // standalone group
        store.saveProfiles([member, balancer])

        store.deleteManualProfile(id: member.id)
        // The member stays (hidden) — the balancer's column still names it.
        XCTAssertEqual(2, store.profiles().count)
        XCTAssertEqual(1, store.visibleProfiles().count)
        XCTAssertEqual(
            true,
            store.profiles().first { $0.id == member.id }?.hidden
        )
    }

    func testDeleteManualProfilesDropsOnlyStandalone() {
        var member = vless("member.example.com")
        member.subscriptionID = nil
        var subbed = vless("sub.example.com")
        subbed.subscriptionID = "sub-1"
        store.saveProfiles([member, subbed])

        store.deleteManualProfiles()
        XCTAssertEqual(["sub.example.com"], store.profiles().map(\.server))
    }
}
