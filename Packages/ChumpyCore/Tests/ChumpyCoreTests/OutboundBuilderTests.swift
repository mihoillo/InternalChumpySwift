import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `OutboundBuilderTest` — the outbound
/// rendering, focused on the case the core's loader is strictest about.
final class OutboundBuilderTests: XCTestCase {

    func testVlessRealityDeclaresItsSecurityType() {
        var profile = Profile(id: "1", type: .vless)
        profile.remarks = "Reality exit"
        profile.server = "reality.example.com"
        profile.serverPort = 443
        profile.password = "b831381d-6324-4d53-ad4f-8cda48b30811"
        profile.network = "tcp"
        profile.security = "reality"
        profile.flow = "xtls-rprx-vision"
        profile.sni = "www.microsoft.com"
        profile.fingerprint = "chrome"
        profile.publicKey = "pbkValue"
        profile.shortID = "sidValue"
        profile.spiderX = "/spider"

        let outbound = OutboundBuilder.build(profile)
        let stream = outbound["streamSettings"] as? [String: Any]
        XCTAssertEqual("reality", stream?["security"] as? String)
        XCTAssertNotNil(stream?["realitySettings"])
        let settings = outbound["settings"] as? [String: Any]
        XCTAssertEqual("xtls-rprx-vision", settings?["flow"] as? String)
    }

    func testVmessTlsDeclaresSecurityTypeAndDefaultsNetwork() {
        var profile = Profile(id: "1", type: .vmess)
        profile.remarks = "TLS exit"
        profile.server = "v2.example.com"
        profile.serverPort = 443
        profile.password = "b831381d-6324-4d53-ad4f-8cda48b30811"
        profile.network = ""
        profile.security = "tls"
        profile.sni = "v2.example.com"

        let outbound = OutboundBuilder.build(profile)
        let stream = outbound["streamSettings"] as? [String: Any]
        XCTAssertEqual("tls", stream?["security"] as? String)
        XCTAssertEqual("tcp", stream?["network"] as? String)
        XCTAssertNotNil(stream?["tlsSettings"])
    }

    func testPlainTcpOmitsStreamSettingsSection() {
        var profile = Profile(id: "1", type: .vless)
        profile.server = "192.168.1.10"
        profile.serverPort = 1080
        profile.password = "b831381d-6324-4d53-ad4f-8cda48b30811"

        XCTAssertNil(OutboundBuilder.build(profile)["streamSettings"])
    }

    func testHysteria2BuildsOwnTransportAndMask() {
        var profile = Profile(id: "1", type: .hysteria2)
        profile.server = "hy2.example.com"
        profile.serverPort = 443
        profile.password = "letmein"
        profile.obfsPassword = "obfspass"
        profile.portHopping = "20000-20100"
        profile.portHoppingInterval = "30"

        let outbound = OutboundBuilder.build(profile)
        XCTAssertEqual("hysteria", outbound["protocol"] as? String)
        let stream = outbound["streamSettings"] as? [String: Any]
        XCTAssertEqual("hysteria", stream?["network"] as? String)
        let hysteria = stream?["hysteriaSettings"] as? [String: Any]
        XCTAssertEqual("letmein", hysteria?["auth"] as? String)
        let mask = stream?["finalmask"] as? [String: Any]
        let udp = mask?["udp"] as? [[String: Any]] ?? []
        XCTAssertEqual(2, udp.count)
        XCTAssertEqual("salamander", udp.first?["type"] as? String)
        XCTAssertEqual("udphop", udp.last?["type"] as? String)
        let hop = udp.last?["settings"] as? [String: Any]
        XCTAssertEqual("20000-20100", hop?["remotePorts"] as? String)
    }

    func testWireguardSettings() {
        var profile = Profile(id: "1", type: .wireguard)
        profile.server = "5.6.7.8"
        profile.serverPort = 51820
        profile.wgSecretKey = "SECRET="
        profile.publicKey = "PUBKEY="
        profile.wgPresharedKey = "PSK="
        profile.wgLocalAddress = "10.0.0.2/32, fd00::2/128"
        profile.wgMTU = 1420
        profile.wgReserved = "1,2,3"

        let outbound = OutboundBuilder.build(profile)
        XCTAssertNil(outbound["streamSettings"])
        let settings = outbound["settings"] as? [String: Any]
        XCTAssertEqual("SECRET=", settings?["secretKey"] as? String)
        XCTAssertEqual(
            ["10.0.0.2/32", "fd00::2/128"],
            (settings?["address"] as? [Any])?.compactMap { $0 as? String }
        )
        let peers = (settings?["peers"] as? [Any])?.first as? [String: Any]
        XCTAssertEqual("PUBKEY=", peers?["publicKey"] as? String)
        XCTAssertEqual("PSK=", peers?["preSharedKey"] as? String)
        XCTAssertEqual("[5.6.7.8]:51820", peers?["endpoint"] as? String)
        XCTAssertEqual(1420, (settings?["mtu"] as? NSNumber)?.intValue)
        XCTAssertEqual(
            [1, 2, 3],
            (settings?["reserved"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue }
        )
    }

    func testIPv6HostGetsBrackets() {
        var profile = Profile(id: "1", type: .vless)
        profile.server = "2001:db8::1"
        profile.serverPort = 443
        profile.password = "b831381d-6324-4d53-ad4f-8cda48b30811"

        let outbound = OutboundBuilder.build(profile)
        let settings = outbound["settings"] as? [String: Any]
        XCTAssertEqual("[2001:db8::1]", settings?["address"] as? String)
    }
}
