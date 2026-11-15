import XCTest
@testable import ChumpyCore

final class LinkUtilsTests: XCTestCase {

    func testDecodeBase64BothAlphabetsAndPadding() {
        // standard, padded
        XCTAssertEqual("hello", LinkUtils.decodeBase64("aGVsbG8="))
        // standard, missing padding
        XCTAssertEqual("hello", LinkUtils.decodeBase64("aGVsbG8"))
        // url-safe, missing padding
        XCTAssertEqual("hello~?", LinkUtils.decodeBase64("aGVsbG9-Pw"))
        // whitespace tolerated
        XCTAssertEqual("hello", LinkUtils.decodeBase64(" aGVs\n bG8= "))
        // garbage
        XCTAssertNil(LinkUtils.decodeBase64("!!!not base64!!!"))
        XCTAssertNil(LinkUtils.decodeBase64(""))
    }

    func testEncodeBase64() {
        XCTAssertEqual("aGVsbG8=", LinkUtils.encodeBase64("hello"))
        XCTAssertEqual("aGVsbG8", LinkUtils.encodeBase64("hello", removePadding: true))
    }

    func testDecodeURIComponentKeepsLiteralPlus() {
        XCTAssertEqual("a b+c", LinkUtils.decodeURIComponent("a%20b+c"))
        XCTAssertEqual("a/b", LinkUtils.decodeURIComponent("a%2Fb"))
        // invalid sequences pass through
        XCTAssertEqual("a%zz", LinkUtils.decodeURIComponent("a%zz"))
    }

    func testURIComponentRoundTrip() {
        let samples = ["Tokyo", "привет мир", "a+b c/d", "🎉"]
        for s in samples {
            XCTAssertEqual(s, LinkUtils.decodeURIComponent(LinkUtils.encodeURIComponent(s)))
        }
    }

    func testIPv6Brackets() {
        XCTAssertEqual("[2001:db8::1]", LinkUtils.ipv6Brackets("2001:db8::1"))
        XCTAssertEqual("example.com", LinkUtils.ipv6Brackets("example.com"))
        XCTAssertEqual("[2001:db8::1]", LinkUtils.ipv6Brackets("[2001:db8::1]"))
        XCTAssertEqual("", LinkUtils.ipv6Brackets(nil))
    }

    func testParsePort() {
        XCTAssertEqual(443, LinkUtils.parsePort("443"))
        XCTAssertEqual(443, LinkUtils.parsePort("443#fragment"))
        XCTAssertEqual(443, LinkUtils.parsePort(" 443.0 "))
        XCTAssertEqual(0, LinkUtils.parsePort("abc"))
        XCTAssertEqual(0, LinkUtils.parsePort(nil))
    }

    func testParsedURI() {
        let uri = ParsedURI.parse(
            LinkUtils.fixIllegalURL("vless://uuid@host.example:443/path?type=ws&security=tls#Frag%20One")
        )
        XCTAssertNotNil(uri)
        guard let uri else { return }
        XCTAssertEqual("vless", uri.scheme)
        XCTAssertEqual("uuid", uri.rawUserInfo)
        XCTAssertEqual("uuid", uri.userInfo)
        XCTAssertEqual("host.example", uri.idnHost)
        XCTAssertEqual(443, uri.port)
        XCTAssertEqual("type=ws&security=tls", uri.rawQuery)
        XCTAssertEqual("Frag%20One", uri.rawFragment)
        XCTAssertEqual("Frag One", LinkUtils.decodeURIComponent(uri.rawFragment ?? ""))
        XCTAssertEqual(["type": "ws", "security": "tls"], uri.queryParams)
    }

    func testParsedURIIpv6Host() {
        let uri = ParsedURI.parse("vless://uuid@[2001:db8::1]:443?security=tls#v6")
        XCTAssertNotNil(uri)
        guard let uri else { return }
        XCTAssertEqual("2001:db8::1", uri.idnHost)
        XCTAssertEqual(443, uri.port)
        XCTAssertEqual("v6", LinkUtils.decodeURIComponent(uri.rawFragment ?? ""))
    }

    func testParsedURIAbsentPortIsMinusOne() {
        let uri = ParsedURI.parse("hy2://pass@host.example#x")
        XCTAssertNotNil(uri)
        XCTAssertEqual(-1, uri?.port ?? 0)
    }

    func testParsedURIFailsWithoutHost() {
        XCTAssertNil(ParsedURI.parse("vmess://"))
        XCTAssertNil(ParsedURI.parse("no-scheme-here"))
    }
}
