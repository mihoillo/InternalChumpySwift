import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `ClashYamlParserTest` — the Clash YAML
/// dialect, exercised on the shapes panels actually serve.
final class ClashYamlParserTests: XCTestCase {

    private let realityEntry = """
        - name: '🇩🇪  Германия #3'
          type: vless
          server: 1.2.3.4
          port: 443
          uuid: 00000000-1111-2222-3333-444444444444
          network: tcp
          udp: true
          tls: true
          servername: pl4.example.org
          client-fingerprint: edge
          reality-opts:
            public-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
            short-id: 0000000000000000
          flow: xtls-rprx-vision
        """

    func testVlessRealityEntryParses() {
        let profiles = ClashYamlParser.parse("proxies:\n\(realityEntry)\n")
        XCTAssertNotNil(profiles)
        guard let p = profiles, p.count == 1 else { return XCTFail("expected one") }
        XCTAssertEqual(ProfileType.vless, p[0].type)
        XCTAssertEqual("🇩🇪  Германия #3", p[0].remarks)
        XCTAssertEqual("1.2.3.4", p[0].server)
        XCTAssertEqual(443, p[0].serverPort)
        XCTAssertEqual("00000000-1111-2222-3333-444444444444", p[0].password)
        XCTAssertEqual("xtls-rprx-vision", p[0].flow)
        XCTAssertEqual("reality", p[0].security)
        XCTAssertEqual("pl4.example.org", p[0].sni)
        XCTAssertEqual("edge", p[0].fingerprint)
        XCTAssertEqual("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", p[0].publicKey)
        XCTAssertEqual("0000000000000000", p[0].shortID)
    }

    func testGrpcEntryWithBlockAlpnParses() {
        let yaml = """
        proxies:
        - name: '🇺🇸  США | Gemini'
          type: vless
          server: 1.2.3.6
          port: 443
          uuid: 9a14cdc4-9ef2-4f79-87ab-76206a11b1ea
          network: grpc
          tls: true
          servername: us4.example.org
          client-fingerprint: chrome
          grpc-opts:
            grpc-service-name: content.v1.Feed
          alpn:
          - h2
        """
        guard let p = ClashYamlParser.parse(yaml), p.count == 1 else { return XCTFail("expected one") }
        XCTAssertEqual("🇺🇸  США | Gemini", p[0].remarks)
        XCTAssertEqual("grpc", p[0].network)
        XCTAssertEqual("content.v1.Feed", p[0].serviceName)
        XCTAssertEqual("tls", p[0].security)
        XCTAssertEqual("us4.example.org", p[0].sni)
        XCTAssertEqual("h2", p[0].alpn)
    }

    func testWsEntryWithIndentedWsOptsParses() {
        let yaml = """
        proxies:
        - name: 🇸🇪  Швеция #2
          type: vless
          server: 1.2.3.7
          port: 443
          uuid: 9a14cdc4-9ef2-4f79-87ab-76206a11b1ea
          network: ws
          tls: true
          servername: se4.example.org
          ws-opts:
            path: /api-se4
            headers:
              Host: cdn.example.com
        """
        guard let p = ClashYamlParser.parse(yaml), p.count == 1 else { return XCTFail("expected one") }
        XCTAssertEqual("ws", p[0].network)
        XCTAssertEqual("/api-se4", p[0].path)
        XCTAssertEqual("cdn.example.com", p[0].host)
    }

    func testVmessTrojanAndSsEntriesParse() {
        let yaml = """
        proxies:
        - name: vm
          type: vmess
          server: v.example.com
          port: 8443
          uuid: b831381d-6324-4d53-ad4f-8cda48b30811
          alterId: 0
          cipher: auto
          network: ws
          ws-opts:
            path: /ws
        - name: tj
          type: trojan
          server: t.example.com
          port: 443
          password: trojanpass
          sni: t.example.com
          skip-cert-verify: true
        - name: ss
          type: ss
          server: s.example.com
          port: 8388
          cipher: aes-256-gcm
          password: sspass
        """
        guard let profiles = ClashYamlParser.parse(yaml) else { return XCTFail("nil") }
        XCTAssertEqual(3, profiles.count)
        let vm = profiles[0]
        XCTAssertEqual(ProfileType.vmess, vm.type)
        XCTAssertEqual("b831381d-6324-4d53-ad4f-8cda48b30811", vm.password)
        XCTAssertEqual("auto", vm.method)
        XCTAssertEqual("ws", vm.network)
        XCTAssertEqual("/ws", vm.path)
        let tj = profiles[1]
        XCTAssertEqual(ProfileType.trojan, tj.type)
        XCTAssertEqual("trojanpass", tj.password)
        XCTAssertEqual("t.example.com", tj.sni)
        XCTAssertTrue(tj.allowInsecure)
        let ss = profiles[2]
        XCTAssertEqual(ProfileType.shadowsocks, ss.type)
        XCTAssertEqual("aes-256-gcm", ss.method)
        XCTAssertEqual("sspass", ss.password)
    }

    func testUnknownTypesAreSkippedAndOtherDialectsStayOut() {
        let mixed = "proxies:\n\(realityEntry)\n"
            + """
            - name: hy
              type: unsupported-protocol
              server: h.example.com
              port: 443
              password: hy

            """
        XCTAssertEqual(1, ClashYamlParser.parse(mixed)?.count)

        XCTAssertNil(ClashYamlParser.parse("vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443#x"))
        XCTAssertNil(ClashYamlParser.parse("[Interface]\nPrivateKey = x\n"))
    }

    func testSubscriptionParserHandsClashYamlThrough() {
        // ws paths and server names carry no "://", so the body reaches the reader raw.
        let yaml = "proxies:\n\(realityEntry)\nproxy-groups:\n- name: PROXY\n  type: select\nrules:\n- MATCH,PROXY\n"
        let profiles = SubscriptionParser.parse(yaml)
        XCTAssertEqual(1, profiles.count)
        XCTAssertEqual("🇩🇪  Германия #3", profiles.first?.remarks)
        // The MATCH,PROXY rule rode along, rewritten onto the session's proxy tag.
        let rules = profiles.first?.routingRules ?? ""
        XCTAssertTrue(rules.contains("MATCH") == false)
        XCTAssertTrue(rules.contains("tcp,udp"))
        XCTAssertTrue(rules.contains("\"outboundTag\":\"proxy\"") || rules.contains("\"outboundTag\": \"proxy\""))
    }

    // MARK: - MiniYaml

    func testMiniYamlFlowListsAndMaps() throws {
        let parsed = try MiniYaml.parse("proxies:\n- {name: a, type: vless, alpn: [h2, http/1.1]}\n")
        let root = try XCTUnwrap(parsed as? [String: Any?])
        let proxies = try XCTUnwrap(root["proxies"] as? [Any?])
        let proxy = try XCTUnwrap(proxies.first as? [String: Any?])
        XCTAssertEqual("a", proxy["name"] as? String)
        XCTAssertEqual("vless", proxy["type"] as? String)
        let alpn = try XCTUnwrap(proxy["alpn"] as? [Any?])
        XCTAssertEqual(["h2", "http/1.1"], alpn.compactMap { $0 as? String })
    }

    func testMiniYamlCommentsAndQuotedScalars() throws {
        let parsed = try MiniYaml.parse("mode: rule # the mode\nname: 'it''s quoted'\n")
        let root = try XCTUnwrap(parsed as? [String: Any?])
        XCTAssertEqual("rule", root["mode"] as? String)
        XCTAssertEqual("it's quoted", root["name"] as? String)
    }

    // MARK: - ClashRouting

    private func routingRules(of yaml: String) -> [[String: Any]] {
        let root = (try? MiniYaml.parse(yaml)) as? [String: Any?] ?? [:]
        let names: Set<String> = []
        let json = ClashRouting.parse(root, proxyNames: names)
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return array
    }

    func testClashRulesConvertToXrayRules() {
        let yaml = """
        mode: rule
        rules:
        - DOMAIN-SUFFIX,vk.com,DIRECT
        - DOMAIN-KEYWORD,yandex,PROXY
        - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
        - GEOIP,ru,DIRECT
        - SRC-IP-CIDR,192.168.1.0/24,DIRECT
        - DST-PORT,443,REJECT
        - PROCESS-NAME,Telegram,PROXY
        - MATCH,PROXY
        """
        let rules = routingRules(of: yaml)
        XCTAssertEqual(7, rules.count)
        XCTAssertTrue(rules.contains {
            ($0["domain"] as? [Any])?.first as? String == "domain:vk.com" &&
            $0["outboundTag"] as? String == "direct"
        })
        XCTAssertTrue(rules.contains {
            ($0["domain"] as? [Any])?.first as? String == "keyword:yandex" &&
            $0["outboundTag"] as? String == "proxy"
        })
        XCTAssertTrue(rules.contains {
            ($0["ip"] as? [Any])?.first as? String == "10.0.0.0/8"
        })
        XCTAssertTrue(rules.contains {
            ($0["ip"] as? [Any])?.first as? String == "geoip:ru"
        })
        XCTAssertTrue(rules.contains {
            ($0["source"] as? [Any])?.first as? String == "192.168.1.0/24"
        })
        XCTAssertTrue(rules.contains {
            $0["port"] as? String == "443" && $0["outboundTag"] as? String == "block"
        })
        // MATCH becomes the catch-all; PROCESS-NAME is skipped.
        XCTAssertTrue(rules.contains {
            $0["network"] as? String == "tcp,udp" && $0["outboundTag"] as? String == "proxy"
        })
    }

    func testUnsupportedRuleStopsConversion() {
        let yaml = """
        mode: rule
        rules:
        - SCRIPT,whatever,DIRECT
        - DOMAIN-SUFFIX,vk.com,DIRECT
        """
        XCTAssertEqual(0, routingRules(of: yaml).count)
    }

    func testNonRuleModeYieldsNothing() {
        let yaml = """
        mode: global
        rules:
        - MATCH,PROXY
        """
        XCTAssertEqual(0, routingRules(of: yaml).count)
    }

    func testInvalidMatcherStopsConversion() {
        // "A later rule must not overtake an unsupported earlier rule": the first
        // invalid matcher stops the whole conversion.
        let yaml = """
        mode: rule
        rules:
        - IP-CIDR,999.0.0.0/8,DIRECT
        - DOMAIN-SUFFIX,ok.com,DIRECT
        """
        XCTAssertEqual(0, routingRules(of: yaml).count)
    }

    func testPortRangeMatcherParses() {
        let yaml = """
        mode: rule
        rules:
        - DST-PORT,1000-2000,REJECT
        """
        let rules = routingRules(of: yaml)
        XCTAssertEqual(1, rules.count)
        XCTAssertEqual("1000-2000", rules[0]["port"] as? String)
        XCTAssertEqual("block", rules[0]["outboundTag"] as? String)
    }

    // MARK: - Panel body end-to-end (ClashPanelBodyTest)

    private func panelBody() -> String {
        """
        proxies:
        - name: '🇩🇪  Тестия #1'
          type: vless
          server: 1.2.3.4
          port: 443
          uuid: 00000000-1111-2222-3333-444444444444
          network: tcp
          udp: true
          tls: true
          servername: de4.example.org
          client-fingerprint: edge
          reality-opts:
            public-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
            short-id: '0000000000000000'
          flow: xtls-rprx-vision
        - name: '🇩🇪  Тестия #1 (копия)'
          type: vless
          server: 1.2.3.4
          port: 443
          uuid: 00000000-1111-2222-3333-444444444444
          network: tcp
          udp: true
          tls: true
          servername: de4.example.org
          client-fingerprint: edge
          reality-opts:
            public-key: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
            short-id: '0000000000000000'
          flow: xtls-rprx-vision
        - name: '🇬🇧  Тестланд #2'
          type: vless
          server: 1.2.3.5
          port: 443
          uuid: 00000000-1111-2222-3333-444444444444
          network: grpc
          udp: true
          tls: true
          servername: gb4.example.org
          client-fingerprint: chrome
          grpc-opts:
            grpc-service-name: vlgrpc
          alpn:
          - h2
        - name: '🇫🇮  Тестия #3'
          type: vless
          server: 1.2.3.6
          port: 443
          uuid: 00000000-1111-2222-3333-444444444444
          network: ws
          udp: true
          ws-opts:
            path: /api-test
        - name: '🇳🇱  Тест #4'
          type: trojan
          server: 1.2.3.7
          port: 443
          password: fake-trojan-password
          udp: true
          sni: nl4.example.org
          alpn:
          - h2
          network: grpc
          tls: true
          client-fingerprint: chrome
          grpc-opts:
            grpc-service-name: ajv
        proxy-groups:
        - name: PROXY
          type: select
          proxies:
          - auto
          - DIRECT
          - '🇩🇪  Тестия #1'
        - name: auto
          type: url-test
          proxies:
          - '🇩🇪  Тестия #1'
          - '🇬🇧  Тестланд #2'
          url: http://www.gstatic.com/generate_204
          interval: 300
        rules:
        - DOMAIN-SUFFIX,example.com,DIRECT
        - RULE-SET,category-ru,DIRECT
        - MATCH,PROXY
        """
    }

    func testPanelBodyParsesEveryShapeItServes() {
        guard let profiles = ClashYamlParser.parse(panelBody()) else {
            return XCTFail("nil")
        }
        // Five entries in the body; the duplicate endpoint collapses.
        XCTAssertEqual(4, profiles.count)
        XCTAssertTrue(profiles.allSatisfy { $0.type == .vless || $0.type == .trojan })
        XCTAssertEqual(3, profiles.filter { $0.type == .vless }.count)
        // The body's one trojan entry, next to the vless fleet.
        let trojan = profiles.filter { $0.type == .trojan }.first
        XCTAssertEqual("🇳🇱  Тест #4", trojan?.remarks)
        XCTAssertEqual("fake-trojan-password", trojan?.password)
        XCTAssertEqual("grpc", trojan?.network)
        XCTAssertEqual("ajv", trojan?.serviceName)
        XCTAssertEqual("h2", trojan?.alpn)
        XCTAssertEqual("nl4.example.org", trojan?.sni)
        XCTAssertTrue(profiles.allSatisfy { !$0.server.isEmpty && $0.serverPort > 0 })
        XCTAssertTrue(
            profiles.filter { $0.type == .vless }
                .allSatisfy { $0.password == "00000000-1111-2222-3333-444444444444" }
        )

        // The three transports the panel serves, all present.
        XCTAssertTrue(profiles.contains { $0.network == "tcp" && $0.security == "reality" })
        XCTAssertTrue(profiles.contains {
            $0.network == "grpc" && $0.alpn == "h2" && !$0.serviceName.isEmpty
        })
        XCTAssertTrue(profiles.contains { $0.network == "ws" && !$0.path.isEmpty })

        // Spot-check the first reality entry, field by field.
        let first = profiles.first { $0.network == "tcp" && $0.security == "reality" }
        XCTAssertEqual("reality", first?.security)
        XCTAssertEqual(443, first?.serverPort)
        XCTAssertEqual("edge", first?.fingerprint)
        XCTAssertFalse(first?.publicKey.isEmpty ?? true)
        XCTAssertFalse(first?.shortID.isEmpty ?? true)
        XCTAssertEqual("xtls-rprx-vision", first?.flow)
    }
}
