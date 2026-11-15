import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `XrayConfigBuilderTest` — the routing
/// rules, asserted on their actual rendered shape: every rule must carry a
/// non-empty matcher.
final class XrayConfigBuilderTests: XCTestCase {

    private var profile: Profile {
        var p = Profile(id: "1", type: .vless)
        p.remarks = "Reality exit"
        p.server = "reality.example.com"
        p.serverPort = 443
        p.password = "b831381d-6324-4d53-ad4f-8cda48b30811"
        p.network = "tcp"
        p.security = "reality"
        p.sni = "www.microsoft.com"
        p.fingerprint = "chrome"
        p.publicKey = "pbk"
        p.shortID = "sid"
        return p
    }

    private func rulesOf(_ config: String) throws -> [[String: Any]] {
        let obj = try JSONSerialization.jsonObject(with: Data(config.utf8)) as? [String: Any]
        let routing = obj?["routing"] as? [String: Any]
        let rules = routing?["rules"] as? [Any] ?? []
        return rules.compactMap { $0 as? [String: Any] }
    }

    /// Asserts every rule carries at least one effective matcher field,
    /// and every array matcher is filled.
    private func assertAllRulesEffective(_ rules: [[String: Any]]) {
        for rule in rules {
            let scalar = rule.keys.contains { $0 == "port" || $0 == "network" }
            let arrayMatchers = rule.keys.filter { !["type", "outboundTag", "balancerTag", "port", "network"].contains($0) }
            XCTAssertTrue(scalar || !arrayMatchers.isEmpty, "rule has no matcher fields: \(rule)")
            for key in arrayMatchers {
                let array = rule[key] as? [Any] ?? []
                XCTAssertFalse(array.isEmpty, "\(key) is empty")
            }
        }
    }

    func testGlobalRulesAllCarryEffectiveFields() throws {
        let rules = try rulesOf(try XrayConfigBuilder.buildFull(profile: profile, mode: .global))
        XCTAssertEqual(3, rules.count)
        assertAllRulesEffective(rules)
        // The private nets go direct in every mode.
        XCTAssertTrue(rules.contains {
            ($0["ip"] as? [Any])?.first as? String == "geoip:private"
        })
        XCTAssertTrue(rules.contains {
            ($0["domain"] as? [Any])?.first as? String == "geosite:private"
        })
    }

    func testRuBypassRulesAllCarryEffectiveFields() throws {
        let rules = try rulesOf(try XrayConfigBuilder.buildFull(profile: profile, mode: .ru))
        XCTAssertEqual(6, rules.count)
        assertAllRulesEffective(rules)
        let domains = rules.flatMap { ($0["domain"] as? [Any] ?? []).compactMap { $0 as? String } }
        XCTAssertTrue(domains.contains("geosite:category-ru"), "category-ru missing")
        let ips = rules.flatMap { ($0["ip"] as? [Any] ?? []).compactMap { $0 as? String } }
        XCTAssertTrue(ips.contains("geoip:ru"), "geoip:ru missing")
        let protocols = rules.flatMap { ($0["protocol"] as? [Any] ?? []).compactMap { $0 as? String } }
        XCTAssertTrue(protocols.contains("bittorrent"), "bittorrent missing")
    }

    func testSmallRegionsRideTheTldInsteadOfGeositeList() throws {
        let rules = try rulesOf(try XrayConfigBuilder.buildFull(profile: profile, mode: .tr))
        let domains = rules.flatMap { ($0["domain"] as? [Any] ?? []).compactMap { $0 as? String } }
        XCTAssertEqual(["domain:tr"], domains.filter { $0 != "geosite:private" })
        let ips = rules.flatMap { ($0["ip"] as? [Any] ?? []).compactMap { $0 as? String } }
        XCTAssertTrue(ips.contains("geoip:tr"), "geoip:tr missing")
    }

    func testIranBypassCarriesGeositeListAndTld() throws {
        let rules = try rulesOf(try XrayConfigBuilder.buildFull(profile: profile, mode: .ir))
        let domains = rules.flatMap { ($0["domain"] as? [Any] ?? []).compactMap { $0 as? String } }
        XCTAssertTrue(domains.contains("geosite:category-ir"), "category-ir missing")
        XCTAssertTrue(domains.contains("domain:ir"), "domain:ir missing")
    }

    func testQuicBlockMatchesPortAndNetwork() throws {
        let rules = try rulesOf(try XrayConfigBuilder.buildFull(profile: profile, mode: .global))
        let quic = rules.first { $0["outboundTag"] as? String == "block" }
        XCTAssertEqual("443", quic?["port"] as? String)
        XCTAssertEqual("udp", quic?["network"] as? String)
    }

    func testBalancerSessionSpreadsMembersOverProxyTagPrefix() throws {
        var balancer = Profile(id: "9", type: .balancer)
        balancer.remarks = "Автовыбор"
        balancer.balancerStrategy = "leastping"
        var member2 = profile
        member2.id = "2"
        member2.server = "second.example.com"

        let configJSON = try XrayConfigBuilder.buildFull(
            profile: balancer,
            mode: .global,
            members: [profile, member2]
        )
        let config = try JSONSerialization.jsonObject(with: Data(configJSON.utf8)) as? [String: Any]

        // The members ride as their own outbounds: the first keeps the plain
        // proxy tag, the rest the prefix.
        let outbounds = config?["outbounds"] as? [[String: Any]] ?? []
        let tags = outbounds.compactMap { $0["tag"] as? String }
        XCTAssertEqual(["proxy", "proxy-2", "direct", "block"], tags)

        // One balancer over them all, the strategy the panel asked for.
        let routing = config?["routing"] as? [String: Any]
        let balancers = routing?["balancers"] as? [[String: Any]] ?? []
        XCTAssertEqual(1, balancers.count)
        XCTAssertEqual("balancer", balancers[0]["tag"] as? String)
        XCTAssertEqual("proxy", (balancers[0]["selector"] as? [Any])?.first as? String)
        let strategy = balancers[0]["strategy"] as? [String: Any]
        XCTAssertEqual("leastping", strategy?["type"] as? String)

        // The fall-through rides the balancer, and nothing else does.
        let rules = try rulesOf(configJSON)
        let catchAll = rules.last
        XCTAssertEqual("balancer", catchAll?["balancerTag"] as? String)
        XCTAssertEqual("tcp,udp", catchAll?["network"] as? String)
        XCTAssertTrue(rules.dropLast().allSatisfy { $0["balancerTag"] == nil })

        // The observing strategy gets its probe source.
        let observatory = config?["observatory"] as? [String: Any]
        XCTAssertEqual("proxy", (observatory?["subjectSelector"] as? [Any])?.first as? String)
        XCTAssertEqual("https://www.gstatic.com/generate_204", observatory?["probeURL"] as? String)
    }

    func testPlainSessionKeepsNoBalancerAndNoObservatory() throws {
        let configJSON = try XrayConfigBuilder.buildFull(profile: profile, mode: .global)
        let config = try JSONSerialization.jsonObject(with: Data(configJSON.utf8)) as? [String: Any]
        let routing = config?["routing"] as? [String: Any]
        XCTAssertNil(routing?["balancers"])
        XCTAssertNil(config?["observatory"])
        let outbounds = config?["outbounds"] as? [[String: Any]] ?? []
        XCTAssertEqual(["proxy", "direct", "block"], outbounds.compactMap { $0["tag"] as? String })
    }

    func testPanelRoutingRulesRideTheSessionRewritten() throws {
        let panelRules = """
        [
          { "type": "field", "domain": ["domain:vk.ru", "domain:yandex.ru"], "outboundTag": "direct" },
          { "type": "field", "domain": ["domain:googlesyndication.com"], "outboundTag": "block" },
          { "type": "field", "network": "udp", "port": "50000-65535", "balancerTag": "panel-VPN" },
          { "type": "field", "ip": ["203.0.113.0/24"], "outboundTag": "DIRECT" }
        ]
        """
        var balancer = Profile(id: "9", type: .balancer)
        balancer.remarks = "Автовыбор"
        balancer.balancerStrategy = "random"
        balancer.routingRules = panelRules
        var member2 = profile
        member2.id = "2"
        member2.server = "second.example.com"

        let rules = try rulesOf(
            try XrayConfigBuilder.buildFull(
                profile: balancer, mode: .global, members: [profile, member2]
            )
        )

        // Every carried rule keeps its effective fields and lands before the catch-all.
        XCTAssertEqual(8, rules.count)
        assertAllRulesEffective(Array(rules.prefix(7)))
        let ru = rules.first {
            ($0["domain"] as? [Any])?.first as? String == "domain:vk.ru"
        }
        XCTAssertEqual("direct", ru?["outboundTag"] as? String)
        let ads = rules.first {
            ($0["domain"] as? [Any])?.first as? String == "domain:googlesyndication.com"
        }
        XCTAssertEqual("block", ads?["outboundTag"] as? String)
        // The panel's own direct spelling, any case, still lands on the session's.
        let ipDirect = rules.first {
            ($0["ip"] as? [Any])?.first as? String == "203.0.113.0/24"
        }
        XCTAssertEqual("direct", ipDirect?["outboundTag"] as? String)
        // What the panel aimed at its balancer funnels to this session's one.
        let funnel = rules.first { $0["port"] as? String == "50000-65535" }
        XCTAssertEqual("balancer", funnel?["balancerTag"] as? String)
        XCTAssertEqual("balancer", rules.last?["balancerTag"] as? String)

        // A plain session funnels the same rule onto the proxy instead.
        var solo = profile
        solo.routingRules = panelRules
        let soloRules = try rulesOf(try XrayConfigBuilder.buildFull(profile: solo, mode: .global))
        XCTAssertTrue(soloRules.allSatisfy { $0["balancerTag"] == nil })
        let soloFunnel = soloRules.first { $0["port"] as? String == "50000-65535" }
        XCTAssertEqual("proxy", soloFunnel?["outboundTag"] as? String)
    }

    func testBalancerWithoutMembersThrows() {
        var balancer = Profile(id: "9", type: .balancer)
        balancer.remarks = "empty"
        XCTAssertThrowsError(try XrayConfigBuilder.buildFull(profile: balancer, mode: .global))
    }

    func testBuildTestIsBareSingleOutbound() throws {
        let configJSON = XrayConfigBuilder.buildTest(profile)
        let config = try JSONSerialization.jsonObject(with: Data(configJSON.utf8)) as? [String: Any]
        XCTAssertEqual(0, (config?["inbounds"] as? [Any])?.count)
        let outbounds = config?["outbounds"] as? [[String: Any]] ?? []
        XCTAssertEqual(1, outbounds.count)
        XCTAssertEqual("proxy", outbounds.first?["tag"] as? String)
        let routing = config?["routing"] as? [String: Any]
        XCTAssertEqual("AsIs", routing?["domainStrategy"] as? String)
        XCTAssertEqual(0, (routing?["rules"] as? [Any])?.count)
    }
}
