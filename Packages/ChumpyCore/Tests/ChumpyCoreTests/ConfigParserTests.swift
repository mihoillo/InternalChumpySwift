import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `ConfigParserTest` — the raw-config
/// subscription dialect, exercised on the shapes panels actually serve.
final class ConfigParserTests: XCTestCase {

    /// One server's config page: the vless+reality shape panel-style panels serve.
    private let single = """
    {
      "remarks": "🇩🇪 Германия #3",
      "outbounds": [
        {
          "tag": "🇩🇪 Германия #3",
          "protocol": "vless",
          "settings": {
            "vnext": [
              {
                "address": "1.2.3.4",
                "port": 443,
                "users": [
                  { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none", "flow": "xtls-rprx-vision" }
                ]
              }
            ]
          },
          "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
              "serverName": "pl4.example.org",
              "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
              "shortId": "0000000000000000",
              "fingerprint": "edge"
            }
          }
        },
        { "tag": "direct", "protocol": "freedom", "settings": {} },
        { "tag": "block", "protocol": "blackhole", "settings": {} }
      ],
      "routing": { "rules": [] },
      "dns": { "servers": [{ "address": "https://77.88.8.8/dns-query" }] }
    }
    """

    /// The aggregator: the same server again — plus one more — under group labels.
    private let aggregator = """
    {
      "remarks": "🇪🇺⚡️ Автовыбор",
      "outbounds": [
        {
          "tag": "auto-🇩🇪 Германия #3",
          "protocol": "vless",
          "settings": {
            "vnext": [
              {
                "address": "1.2.3.4",
                "port": 443,
                "users": [
                  { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none", "flow": "xtls-rprx-vision" }
                ]
              }
            ]
          },
          "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
              "serverName": "pl4.example.org",
              "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
              "shortId": "0000000000000000",
              "fingerprint": "edge"
            }
          }
        },
        {
          "tag": "auto-🇬🇧 Англия",
          "protocol": "vless",
          "settings": {
            "vnext": [
              {
                "address": "1.2.3.5",
                "port": 443,
                "users": [
                  { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none", "flow": "xtls-rprx-vision" }
                ]
              }
            ]
          },
          "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
              "serverName": "pl4.example.org",
              "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
              "shortId": "0000000000000000",
              "fingerprint": "edge"
            }
          }
        },
        { "tag": "direct", "protocol": "freedom", "settings": {} }
      ]
    }
    """

    func testSingleServerConfigParsesWithRemarksAsName() {
        let profiles = ConfigParser.parse(single)
        XCTAssertNotNil(profiles)
        guard let p = profiles, p.count == 1 else { return XCTFail("expected one profile") }
        XCTAssertEqual(ProfileType.vless, p[0].type)
        XCTAssertEqual("🇩🇪 Германия #3", p[0].remarks)
        XCTAssertEqual("1.2.3.4", p[0].server)
        XCTAssertEqual(443, p[0].serverPort)
        XCTAssertEqual("00000000-1111-2222-3333-444444444444", p[0].password)
        XCTAssertEqual("none", p[0].method)
        XCTAssertEqual("xtls-rprx-vision", p[0].flow)
        XCTAssertEqual("tcp", p[0].network)
        XCTAssertEqual("reality", p[0].security)
        XCTAssertEqual("pl4.example.org", p[0].sni)
        XCTAssertEqual("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", p[0].publicKey)
        XCTAssertEqual("0000000000000000", p[0].shortID)
        XCTAssertEqual("edge", p[0].fingerprint)
    }

    func testAggregatorCopiesOfIndividuallyNamedServersStayOut() {
        let profiles = ConfigParser.parse("[\(single),\(aggregator)]")
        guard let profiles else { return XCTFail("nil") }
        XCTAssertEqual(2, profiles.count)
        let germany = profiles.first { $0.server == "1.2.3.4" }
        XCTAssertEqual("🇩🇪 Германия #3", germany?.remarks)
        let england = profiles.first { $0.server == "1.2.3.5" }
        XCTAssertEqual("🇪🇺⚡️ Автовыбор auto-🇬🇧 Англия", england?.remarks)
    }

    func testLoneAggregatorStillHandsOverItsServers() {
        let profiles = ConfigParser.parse(aggregator) ?? []
        XCTAssertEqual(2, profiles.count)
        XCTAssertEqual(
            Set(["🇪🇺⚡️ Автовыбор auto-🇩🇪 Германия #3", "🇪🇺⚡️ Автовыбор auto-🇬🇧 Англия"]),
            Set(profiles.map(\.remarks))
        )
    }

    func testFlatSettingsDialectParses() {
        let flat = """
        {
          "outbounds": [
            {
              "tag": "flat",
              "protocol": "vless",
              "settings": {
                "address": "example.com",
                "port": 8443,
                "id": "b831381d-6324-4d53-ad4f-8cda48b30811",
                "encryption": "none",
                "flow": "",
                "level": 8
              },
              "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": { "serverName": "example.com", "alpn": ["h2", "http/1.1"] },
                "wsSettings": { "path": "/ws", "host": "cdn.example.com" }
              }
            }
          ]
        }
        """
        guard let p = ConfigParser.parse(flat), p.count == 1 else { return XCTFail("nil") }
        XCTAssertEqual(ProfileType.vless, p[0].type)
        XCTAssertEqual("example.com", p[0].server)
        XCTAssertEqual(8443, p[0].serverPort)
        XCTAssertEqual("b831381d-6324-4d53-ad4f-8cda48b30811", p[0].password)
        XCTAssertEqual("tls", p[0].security)
        XCTAssertEqual("h2,http/1.1", p[0].alpn)
        XCTAssertEqual("ws", p[0].network)
        XCTAssertEqual("/ws", p[0].path)
        XCTAssertEqual("cdn.example.com", p[0].host)
    }

    func testShareLinkBodiesAreNotThisDialect() {
        XCTAssertNil(ConfigParser.parse("vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?security=tls#x"))
        XCTAssertNil(ConfigParser.parse("[not json at all"))
        XCTAssertNil(ConfigParser.parse(#"{"outbounds": "not-an-array"}"#))
        XCTAssertNil(ConfigParser.parse(#"{"dns": {"servers": []}}"#))
    }

    /// The balancer-bearing bundle: the same two servers, plus a routing balancer over them.
    private let balanced = """
    {
      "remarks": "Автовыбор",
      "outbounds": [
        {
          "tag": "auto-🇩🇪 Германия #3",
          "protocol": "vless",
          "settings": {
            "vnext": [
              { "address": "1.2.3.4", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none", "flow": "xtls-rprx-vision" } ] }
            ]
          },
          "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "serverName": "pl4.example.org", "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "shortId": "0000000000000000", "fingerprint": "edge" } }
        },
        {
          "tag": "auto-🇬🇧 Англия",
          "protocol": "vless",
          "settings": {
            "vnext": [
              { "address": "1.2.3.5", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none", "flow": "xtls-rprx-vision" } ] }
            ]
          },
          "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "serverName": "pl4.example.org", "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "shortId": "0000000000000000", "fingerprint": "edge" } }
        }
      ],
      "routing": {
        "balancers": [
          { "tag": "auto_Balancer", "selector": ["auto-"], "strategy": { "type": "leastPing" } }
        ]
      }
    }
    """

    func testBalancerParsesAsProfileOverMembersLinkKeys() {
        let profiles = ConfigParser.parse("[\(single),\(balanced)]")
        guard let profiles else { return XCTFail("nil") }
        let balancer = profiles.first { $0.type == .balancer }
        XCTAssertNotNil(balancer)
        XCTAssertEqual("Автовыбор", balancer?.remarks)
        XCTAssertEqual("leastping", balancer?.balancerStrategy)
        XCTAssertFalse(balancer?.hidden ?? true)
        let keys = Set(balancer?.balancerMemberKeys ?? [])
        XCTAssertEqual(2, keys.count)
        let germany = profiles.first { $0.server == "1.2.3.4" }
        XCTAssertEqual("🇩🇪 Германия #3", germany?.remarks)
        XCTAssertFalse(germany?.hidden ?? true)
        let england = profiles.first { $0.server == "1.2.3.5" }
        XCTAssertEqual("Автовыбор auto-🇬🇧 Англия", england?.remarks)
        XCTAssertEqual(true, england?.hidden)
        for p in profiles where p.type != .balancer {
            XCTAssertTrue(keys.contains(p.computeLinkKey()))
        }
    }

    func testBalancerUnderTwoMembersDroppedFallbackCarriesIt() {
        func body(selector: [String], fallback: String?) -> String {
            let selectorJson = selector.isEmpty
                ? "[]"
                : "[" + selector.map { "\"\($0)\"" }.joined(separator: ",") + "]"
            let fallbackJson = fallback.map { "\"\($0)\"" } ?? "null"
            return """
            {
              "outbounds": [
                { "tag": "a", "protocol": "vless", "settings": { "vnext": [ { "address": "1.1.1.1", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none" } ] } ] } },
                { "tag": "b", "protocol": "vless", "settings": { "vnext": [ { "address": "2.2.2.2", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none" } ] } ] } }
              ],
              "routing": {
                "balancers": [
                  { "tag": "x", "selector": \(selectorJson), "fallbackTag": \(fallbackJson) }
                ]
              }
            }
            """
        }

        // A selector that matches only one of two outbounds, no fallback: not worth an entry.
        let noFallback = ConfigParser.parse(body(selector: ["a"], fallback: nil))
        XCTAssertFalse((noFallback ?? []).contains { $0.type == .balancer })

        // With the fallback joining in: a degraded balancer still beats none.
        let carried = ConfigParser.parse(body(selector: ["a"], fallback: "b"))
        XCTAssertEqual(1, (carried ?? []).filter { $0.type == .balancer }.count)
        let balancer = carried?.first { $0.type == .balancer }
        XCTAssertEqual(2, balancer?.balancerMemberKeys.count)
    }

    func testUnknownStrategiesFallBackToRandom() {
        let body = balanced.replacingOccurrences(of: "\"leastPing\"", with: "\"chaos\"")
        let balancer = ConfigParser.parse(body)?.first { $0.type == .balancer }
        XCTAssertEqual("random", balancer?.balancerStrategy)
    }

    func testPickEverythingBalancerFilesMembersAwayHidden() {
        let body = """
        {
          "routing": {
            "rules": [ { "type": "field", "network": "tcp,udp", "balancerTag": "Super_Balancer" } ],
            "balancers": [ { "tag": "Super_Balancer", "selector": ["proxy"], "strategy": { "type": "leastLoad" } } ]
          },
          "outbounds": [
            {
              "tag": "proxy",
              "protocol": "vless",
              "settings": { "vnext": [ { "address": "1.2.3.8", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none" } ] } ] },
              "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless-grpc" }, "security": "reality", "realitySettings": { "serverName": "okmarket.example.org", "publicKey": "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC", "shortId": "000000" } }
            },
            {
              "tag": "proxy-2",
              "protocol": "vless",
              "settings": { "vnext": [ { "address": "1.2.3.9", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none" } ] } ] },
              "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless-grpc" }, "security": "reality", "realitySettings": { "serverName": "bitrix.example.org", "publicKey": "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD", "shortId": "a1b2c3d4" } }
            },
            { "tag": "direct", "protocol": "freedom" },
            { "tag": "block", "protocol": "blackhole" }
          ]
        }
        """
        guard let profiles = ConfigParser.parse(body) else { return XCTFail("nil") }
        XCTAssertEqual(3, profiles.count)
        let balancer = profiles.filter { $0.type == .balancer }
        XCTAssertEqual(1, balancer.count)
        XCTAssertEqual("Super", balancer[0].remarks)
        XCTAssertEqual("leastload", balancer[0].balancerStrategy)
        XCTAssertEqual(2, balancer[0].balancerMemberKeys.count)
        let members = profiles.filter { $0.type == .vless }
        XCTAssertEqual(2, members.count)
        XCTAssertTrue(members.allSatisfy { $0.hidden })
        XCTAssertFalse(balancer[0].hidden)
    }

    func testRoutingRulesRideProfilesFiltered() {
        let body = """
        {
          "remarks": "🇪🇺 Автовыбор",
          "routing": {
            "rules": [
                { "type": "field", "protocol": ["bittorrent"], "outboundTag": "direct" },
                { "type": "field", "outboundTag": "direct" },
                { "ip": ["203.0.113.0/24"], "outbound": "BLOCK" },
                { "type": "field", "domain": ["domain:vk.ru", "domain:yandex.ru"], "outboundTag": "direct" },
                { "type": "field", "network": "tcp,udp", "balancerTag": "panel-VPN" },
                { "type": "field", "network": "udp", "port": "443,853", "outboundTag": "block" }
            ],
            "balancers": [ { "tag": "panel-VPN", "selector": ["proxy"], "strategy": { "type": "leastPing" } } ]
          },
          "outbounds": [
            {
              "tag": "proxy",
              "protocol": "vless",
              "settings": { "vnext": [ { "address": "1.2.3.4", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none" } ] } ] },
              "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "serverName": "pl4.example.org", "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "shortId": "0000000000000000", "fingerprint": "edge" } }
            },
            {
              "tag": "proxy-2",
              "protocol": "vless",
              "settings": { "vnext": [ { "address": "1.2.3.5", "port": 443, "users": [ { "id": "00000000-1111-2222-3333-444444444444", "encryption": "none" } ] } ] },
              "streamSettings": { "network": "tcp", "security": "reality", "realitySettings": { "serverName": "pl4.example.org", "publicKey": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "shortId": "0000000000000000", "fingerprint": "edge" } }
            }
          ]
        }
        """
        guard let profiles = ConfigParser.parse(body) else { return XCTFail("nil") }
        func rulesOf(_ p: Profile) -> [[String: Any]] {
            guard let data = p.routingRules.data(using: .utf8),
                  let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return [] }
            return array
        }
        let rules = rulesOf(profiles.first { $0.type == .vless }!)
        let balancerRules = rulesOf(profiles.first { $0.type == .balancer }!)

        XCTAssertEqual(4, rules.count)
        XCTAssertEqual(4, balancerRules.count)
        XCTAssertTrue(rules.contains { rule in
            let protocols = JSONX.strings(rule["protocol"] as? [Any])
            return protocols == ["bittorrent"] && (rule["outboundTag"] as? String) == "direct"
        })
        let ru = rules.first { JSONX.strings($0["domain"] as? [Any]).isEmpty == false }
        XCTAssertNotNil(ru)
        XCTAssertEqual(["domain:vk.ru", "domain:yandex.ru"], JSONX.strings(ru?["domain"] as? [Any]))
        XCTAssertEqual("direct", ru?["outboundTag"] as? String)
        // The "outbound" alias became "outboundTag", the original target kept verbatim.
        let blocked = rules.first { !JSONX.strings($0["ip"] as? [Any]).isEmpty }
        XCTAssertEqual("BLOCK", blocked?["outboundTag"] as? String)
        // The catch-alls never made it in.
        XCTAssertTrue(rules.allSatisfy { $0["balancerTag"] == nil })
        XCTAssertTrue(rules.allSatisfy { ($0["network"] as? String) != "tcp,udp" })
    }

    func testSubscriptionParserHandsRawConfigsWithHttpsDNSTrap() {
        // The DNS block carries "https://" — the link-list reader would swallow the body.
        let profiles = SubscriptionParser.parse("[\(single),\(aggregator)]")
        XCTAssertEqual(2, profiles.count)
        let germany = profiles.first { $0.server == "1.2.3.4" }
        XCTAssertEqual(ProfileType.vless, germany?.type)
        XCTAssertEqual("🇩🇪 Германия #3", germany?.remarks)

        // Base64-wrapped configs land through the same door.
        let wrapped = Data("[\(single)]".utf8).base64EncodedString()
        XCTAssertEqual(1, SubscriptionParser.parse(wrapped).count)
    }

    func testLinkListsStillParseAfterTheNewDoor() {
        let profiles = SubscriptionParser.parse(
            "vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?security=tls&type=tcp#x\n"
                + "trojan://pass@5.6.7.8:443?security=tls#y"
        )
        XCTAssertEqual(2, profiles.count)
        XCTAssertTrue(profiles.allSatisfy { !$0.server.isEmpty })
    }
}
