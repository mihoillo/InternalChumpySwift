import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `Hysteria2ConfigParserTest`.
final class Hysteria2ConfigParserTests: XCTestCase {

    private func config(version: Int = 2, auth: String = #""auth": "test-password""#) -> String {
        let authClause = auth.isEmpty ? "" : ", \(auth)"
        return """
        {
          "remarks": "Test Hysteria2",
          "outbounds": [{
            "tag": "proxy",
            "protocol": "hysteria",
            "settings": {"address": "hy.example.com", "port": 443, "version": \(version)},
            "streamSettings": {
              "network": "hysteria",
              "hysteriaSettings": {"version": \(version)\(authClause)},
              "security": "tls",
              "tlsSettings": {"serverName": "sni.example.com", "alpn": ["h3"], "fingerprint": "chrome"}
            }
          }, {"tag": "direct", "protocol": "freedom"}]
        }
        """
    }

    func testJsonSubscriptionPreservesHysteria2EndpointAuthAndTls() throws {
        let profile = try XCTUnwrap(SubscriptionParser.parse("[\(config())]").first)
        XCTAssertEqual(ProfileType.hysteria2, profile.type)
        XCTAssertEqual("Test Hysteria2", profile.remarks)
        XCTAssertEqual("hy.example.com", profile.server)
        XCTAssertEqual(443, profile.serverPort)
        XCTAssertEqual("test-password", profile.password)
        XCTAssertEqual("hysteria", profile.network)
        XCTAssertEqual("tls", profile.security)
        XCTAssertEqual("sni.example.com", profile.sni)
        XCTAssertEqual("h3", profile.alpn)
        XCTAssertEqual("chrome", profile.fingerprint)

        let outbound = OutboundBuilder.build(profile)
        XCTAssertEqual("hysteria", outbound["protocol"] as? String)
        let stream = try XCTUnwrap(outbound["streamSettings"] as? [String: Any])
        let hysteria = try XCTUnwrap(stream["hysteriaSettings"] as? [String: Any])
        XCTAssertEqual("test-password", hysteria["auth"] as? String)
        let tls = try XCTUnwrap(stream["tlsSettings"] as? [String: Any])
        XCTAssertEqual("sni.example.com", tls["serverName"] as? String)
    }

    func testHysteriaV1IsNotImportedAsHysteria2() {
        XCTAssertNil(ConfigParser.parse(config(version: 1)))
    }

    func testHysteria2WithoutAuthenticationIsSkipped() {
        XCTAssertNil(ConfigParser.parse(config(auth: "")))
    }

    func testYamlPreservesTlsObfuscationAndPortHopping() throws {
        let profile = try XCTUnwrap(SubscriptionParser.parse("""
        proxies:
          - name: Test
            type: hysteria2
            server: hy.example.com
            port: 443
            password: test-password
            sni: sni.example.com
            obfs: salamander
            obfs-password: test-mask
            ports: 20000-20100
            hop-interval: 30
            skip-cert-verify: true
        """).first)
        XCTAssertEqual(ProfileType.hysteria2, profile.type)
        XCTAssertEqual("hysteria", profile.network)
        XCTAssertEqual("tls", profile.security)
        XCTAssertEqual("test-password", profile.password)
        XCTAssertEqual("test-mask", profile.obfsPassword)
        XCTAssertEqual("20000-20100", profile.portHopping)
        XCTAssertEqual("30", profile.portHoppingInterval)
        XCTAssertTrue(profile.allowInsecure)
    }

    func testHysteria2LinksUsePort443WhenOmitted() {
        XCTAssertEqual(
            443,
            LinkParsers.parse("hy2://test@hy.example.com?sni=sni.example.com")?.serverPort
        )
    }
}
