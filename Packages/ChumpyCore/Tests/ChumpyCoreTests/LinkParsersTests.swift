import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `LinkParsersTest`: the share-link parsers
/// exercised on the shapes that actually appear in the wild.
final class LinkParsersTests: XCTestCase {

    private func b64(_ s: String) -> String {
        Data(s.utf8).base64EncodedString()
    }

    private func b64url(_ s: String) -> String {
        var out = Data(s.utf8).base64EncodedString()
        out = out.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        while out.hasSuffix("=") { out.removeLast() }
        return out
    }

    func testVmessQRJSONParses() {
        let json = """
        {"v":"2","ps":"Helsinki","add":"v2.example.com","port":"443","id":"b831381d-6324-4d53-ad4f-8cda48b30811","aid":"0","net":"ws","type":"none","host":"cdn.example.com","path":"/ws","tls":"tls","scy":"auto"}
        """
        let p = LinkParsers.parse("vmess://" + b64(json))
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.vmess, p.type)
        XCTAssertEqual("Helsinki", p.remarks)
        XCTAssertEqual("v2.example.com", p.server)
        XCTAssertEqual(443, p.serverPort)
        XCTAssertEqual("b831381d-6324-4d53-ad4f-8cda48b30811", p.password)
        XCTAssertEqual("ws", p.network)
        XCTAssertEqual("/ws", p.path)
        XCTAssertEqual("tls", p.security)
    }

    func testSourceLinkRidesAlongVerbatim() {
        let link = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443?security=tls#Tokyo"
        XCTAssertEqual(link, LinkParsers.parse("  \(link)  ")?.sourceLink)
        // A config body is not a link — it arrives by its own door, carrying none.
        let conf = "[Interface]\nPrivateKey=ABCDEF=\n[Peer]\nPublicKey=PUBKEY=\nEndpoint=5.6.7.8:51820"
        XCTAssertNil(LinkParsers.parseWireguardConf(conf)?.sourceLink)
    }

    func testVmessURIParses() {
        let p = LinkParsers.parse(
            "vmess://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:8000?type=tcp&security=none#remarks"
        )
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.vmess, p.type)
        XCTAssertEqual("1.2.3.4", p.server)
        XCTAssertEqual(8000, p.serverPort)
        XCTAssertEqual("remarks", p.remarks)
    }

    func testVlessRealityParses() {
        let p = LinkParsers.parse(
            "vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?"
                + "encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.google.com"
                + "&fp=chrome&pbk=PUBLICKEY&sid=ab12&spx=%2F#RealityNode"
        )
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.vless, p.type)
        XCTAssertEqual("xtls-rprx-vision", p.flow)
        XCTAssertEqual("reality", p.security)
        XCTAssertEqual("www.google.com", p.sni)
        XCTAssertEqual("chrome", p.fingerprint)
        XCTAssertEqual("PUBLICKEY", p.publicKey)
        XCTAssertEqual("ab12", p.shortID)
    }

    func testSsSip002WithPluginParses() {
        let p = LinkParsers.parse(
            "ss://" + b64url("aes-256-gcm:pass123")
                + "@1.2.3.4:8388?plugin=v2ray-plugin%3Dmode%3Dwebsocket#SipNode"
        )
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.shadowsocks, p.type)
        XCTAssertEqual("aes-256-gcm", p.method)
        XCTAssertEqual("pass123", p.password)
        XCTAssertEqual(8388, p.serverPort)
        XCTAssertEqual("SipNode", p.remarks)
    }

    func testSsLegacyBase64Parses() {
        let whole = b64url("aes-128-gcm:legacy@1.2.3.4:8388")
        let p = LinkParsers.parse("ss://\(whole)#Legacy")
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.shadowsocks, p.type)
        XCTAssertEqual("aes-128-gcm", p.method)
        XCTAssertEqual("legacy", p.password)
        XCTAssertEqual(8388, p.serverPort)
    }

    func testHy2WithObfsAndHoppingParses() {
        let p = LinkParsers.parse(
            "hy2://letmein@1.2.3.4:443?obfs=salamander&obfs-password=obfspass"
                + "&mport=20000-20100&mportinterval=30#Hy2Node"
        )
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.hysteria2, p.type)
        XCTAssertEqual("letmein", p.password)
        XCTAssertEqual("obfspass", p.obfsPassword)
        XCTAssertEqual(443, p.serverPort)
        XCTAssertEqual("20000-20100", p.portHopping)
        XCTAssertEqual("30", p.portHoppingInterval)
    }

    func testSocksParses() {
        let p = LinkParsers.parse("socks://user:pass@1.2.3.4:1080#SocksNode")
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.socks, p.type)
        XCTAssertEqual("user", p.username)
        XCTAssertEqual("pass", p.password)
        XCTAssertEqual(1080, p.serverPort)
    }

    func testWireguardConfParses() {
        let conf = """
        [Interface]
        PrivateKey = ABCDEF=
        Address = 10.0.0.2/32, fd00::2/128
        DNS = 1.1.1.1
        MTU = 1420

        [Peer]
        PublicKey = PUBKEY=
        PresharedKey = PSK=
        AllowedIPs = 0.0.0.0/0, ::/0
        Endpoint = 5.6.7.8:51820
        PersistentKeepalive = 25
        """
        let p = LinkParsers.parseWireguardConf(conf)
        XCTAssertNotNil(p)
        guard let p else { return }
        XCTAssertEqual(ProfileType.wireguard, p.type)
        XCTAssertEqual("ABCDEF=", p.wgSecretKey)
        XCTAssertEqual(
            "10.0.0.2/32, fd00::2/128".replacingOccurrences(of: " ", with: ""),
            p.wgLocalAddress.replacingOccurrences(of: " ", with: "")
        )
        XCTAssertEqual(51820, p.serverPort)
        XCTAssertEqual("PUBKEY=", p.publicKey)
        XCTAssertEqual("PSK=", p.wgPresharedKey)
        XCTAssertEqual(1420, p.wgMTU)
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(LinkParsers.parse("not a link"))
        XCTAssertNil(LinkParsers.parse("vmess://not-base64-json!!!"))
    }

    func testLinkKeyIsStableAcrossRemarksChangesAndIds() {
        let a = LinkParsers.parse("socks://user:pass@1.2.3.4:1080#A")
        let b = LinkParsers.parse("socks://user:pass@1.2.3.4:1080#B")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(a?.computeLinkKey(), b?.computeLinkKey())
    }
}
