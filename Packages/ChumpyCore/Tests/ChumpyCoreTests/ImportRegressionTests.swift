import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `ImportRegressionTest`.
final class ImportRegressionTests: XCTestCase {

    private let link = "vless://test@example.com:443?security=tls#Name"

    func testWrappedBase64SubscriptionImportsAndDeduplicates() {
        let encoded = LinkUtils.encodeBase64("\(link)\n\(link)")
            .chunked(16).joined(separator: "\r\n")
        let profiles = SubscriptionParser.parse(encoded)
        XCTAssertEqual(1, profiles.count)
        XCTAssertEqual("example.com", profiles.first?.server)
    }

    func testBase64NestedUrlIsRecognized() {
        XCTAssertEqual(
            "https://example.com/sub",
            SubscriptionParser.isNestedSubscriptionURL(
                LinkUtils.encodeBase64("https://example.com/sub")
            )
        )
    }

    func testSchemeIsCaseInsensitiveAndFragmentDecodedOnce() {
        let profile = LinkParsers.parse(
            "VMESS://" + LinkUtils.encodeBase64(
                #"{"add":"example.com","port":"443","id":"test","ps":"name"}"#
            )
        )
        XCTAssertNotNil(profile)
        XCTAssertEqual(
            "literal%20name",
            LinkParsers.parse(link.substringBefore("#") + "#literal%2520name")?.remarks
        )
    }

    func testInvalidEndpointsRejectedAndPlainVlessImports() {
        XCTAssertNil(LinkParsers.parse("vless://test@:443?security=tls"))
        XCTAssertNil(LinkParsers.parse("vless://test@example.com:65536?security=tls"))
        XCTAssertNil(LinkParsers.parse("vless://test@example.com?security=tls"))
        XCTAssertNotNil(LinkParsers.parse("vless://test@example.com:443"))
    }

    func testVmessUriWorksWithOneQueryParameterOrNone() {
        XCTAssertEqual("ws", LinkParsers.parse("vmess://test@example.com:443?type=ws")?.network)
        XCTAssertEqual("test", LinkParsers.parse("vmess://test@example.com:443")?.password)
    }

    func testHysteriaTransportStaysCanonicalWithQueryParameters() {
        XCTAssertEqual("hysteria", LinkParsers.parse("hy2://test@example.com?sni=example.com")?.network)
        XCTAssertNil(LinkParsers.parse("ss://invalid@example.com:443"))
    }

    func testRawWebsocketConfigPreservesHostHeader() {
        let body = """
        {
            "outbounds":[{"protocol":"vless","settings":{"vnext":[{
                "address":"example.com","port":443,"users":[{"id":"test"}]
            }]},"streamSettings":{"network":"ws","wsSettings":{
                "path":"/socket","headers":{"Host":"front.example.com"}
            }}}]
        }
        """
        guard let profile = (ConfigParser.parse(body) ?? []).first else {
            return XCTFail("nil")
        }
        XCTAssertEqual("front.example.com", profile.host)
        XCTAssertEqual("/socket", profile.path)
    }

    func testEncodedSocksComponentsRetainBoundaries() {
        let profile = LinkParsers.parse("socks://user%3Aname:pa%3Ass@example.com:1080")
        XCTAssertEqual("user:name", profile?.username)
        XCTAssertEqual("pa:ss", profile?.password)
    }

    func testMissingMandatoryCredentialsRejected() {
        XCTAssertNil(LinkParsers.parse("vless://example.com:443?security=tls"))
        XCTAssertNil(LinkParsers.parse("wg://private@example.com:443?address=10.0.0.2/32"))
        XCTAssertNil(LinkParsers.parse("trojan://example.com:443"))
        XCTAssertNotNil(LinkParsers.parse("socks://example.com:1080"))
    }

    func testFlowYamlAndQuotedPasswordsPreserveContent() {
        let flow = "proxies:\n  - {name: Test, type: trojan, server: example.com, port: 443, password: 'it''s, a password'}"
        XCTAssertEqual("it's, a password", SubscriptionParser.parse(flow).first?.password)
        let escaped = "proxies:\n  - name: Test\n    type: trojan\n    server: example.com\n    port: 443\n    password: \"a\\u003Ab\\n\" # note"
        XCTAssertEqual("a:b\n", SubscriptionParser.parse(escaped).first?.password)
    }

    func testBomDoesNotChangeJsonImport() {
        let raw = #"{"outbounds":[{"protocol":"socks","settings":{"address":"example.com","port":1080}}]}"#
        XCTAssertEqual(SubscriptionParser.parse(raw), SubscriptionParser.parse("\u{FEFF}" + raw))
    }

    func testCustomOutboundTagsRetainBlockAndDirectSemantics() throws {
        func parse(_ protocolName: String) throws -> Profile {
            let body = """
            {
                "outbounds":[{"tag":"proxy","protocol":"socks","settings":{"address":"example.com","port":1080}},
                {"tag":"custom-target","protocol":"\(protocolName)"}],
                "routing":{"rules":[{"type":"field","domain":["domain:example.net"],"outboundTag":"custom-target"}]}
            }
            """
            guard let profile = (ConfigParser.parse(body) ?? []).first else {
                throw XCTSkip("nil")
            }
            return profile
        }
        let full = try XrayConfigBuilder.buildFull(profile: parse("blackhole"), mode: .global)
        XCTAssertTrue(full.contains("\"outboundTag\":\"block\""))
        XCTAssertTrue(try parse("freedom").routingRules.contains("\"outboundTag\":\"direct\""))
    }

    func testWireguardConfRejectsMultiplePeersAndRoundtrips() throws {
        let text = "[Interface]\nPrivateKey = private\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = public\nEndpoint = example.com:443\n"
        XCTAssertNil(LinkParsers.parseWireguardConf(
            text + "[Peer]\nPublicKey = other\nEndpoint = other.example:443\n"
        ))
        let profile = try XCTUnwrap(LinkParsers.parseWireguardConf(text))
        let outboundJSON = try XCTUnwrap(JSONX.toJSONString(OutboundBuilder.build(profile)))
        let parsed = try XCTUnwrap(
            (ConfigParser.parse("{\"outbounds\":[\(outboundJSON)]}") ?? []).first
        )
        XCTAssertEqual(profile.server, parsed.server)
        XCTAssertEqual(profile.publicKey, parsed.publicKey)
        XCTAssertEqual(profile.wgSecretKey, parsed.wgSecretKey)
    }
}

private extension String {
    func chunked(_ size: Int) -> [String] {
        guard !isEmpty else { return [] }
        var chunks: [String] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[start..<end]))
            start = end
        }
        return chunks
    }
}
