import XCTest
@testable import ChumpyCore

/// Ported semantics of the Android client's `SubscriptionHeaders`.
final class SubscriptionHeadersTests: XCTestCase {

    func testParseReadsAllInterestingHeaders() {
        let meta = SubscriptionHeaders.parse([
            "Subscription-Userinfo": ["upload=111; download=222; total=333; expire=1700000000"],
            "Profile-Title": ["base64:" + LinkUtils.encodeBase64("Моя подписка")],
            "Profile-Update-Interval": ["12"],
            "Routing": [],
            "profile-logo": ["https://cdn.example.org/logo.png"],
        ])
        XCTAssertEqual("Моя подписка", meta.title)
        XCTAssertEqual(111, meta.uploadBytes)
        XCTAssertEqual(222, meta.downloadBytes)
        XCTAssertEqual(333, meta.totalBytes)
        XCTAssertEqual(1700000000, meta.expireEpochSeconds)
        XCTAssertEqual(12, meta.updateIntervalHours)
        XCTAssertEqual("https://cdn.example.org/logo.png", meta.logoURL)
    }

    func testContentDispositionFillsMissingTitle() {
        let meta = SubscriptionHeaders.parse([
            "content-disposition": ["attachment; filename=MyProvider.txt"],
        ])
        XCTAssertEqual("MyProvider", meta.title)
    }

    func testUserinfoParsing() {
        let meta = SubscriptionHeaders.parseUserinfo("upload=1; download=2; total=3; expire=4")
        XCTAssertEqual(1, meta.uploadBytes)
        XCTAssertEqual(2, meta.downloadBytes)
        XCTAssertEqual(3, meta.totalBytes)
        XCTAssertEqual(4, meta.expireEpochSeconds)

        let junk = SubscriptionHeaders.parseUserinfo("garbage; upload=abc; =9; total=9")
        XCTAssertEqual(9, junk.totalBytes)
        XCTAssertEqual(0, junk.uploadBytes)
    }

    func testTitleParsingVariants() {
        XCTAssertEqual("plain", SubscriptionHeaders.parseTitle("plain"))
        XCTAssertEqual("Base64 заголовок", SubscriptionHeaders.parseTitle("base64:" + LinkUtils.encodeBase64("Base64 заголовок")))
        XCTAssertEqual("URL encoded", SubscriptionHeaders.parseTitle("URL%20encoded"))
        XCTAssertNil(SubscriptionHeaders.parseTitle("base64:???"))
        XCTAssertNil(SubscriptionHeaders.parseTitle("   "))
    }

    func testUpdateIntervalParsing() {
        XCTAssertEqual(12, SubscriptionHeaders.parseUpdateInterval("12"))
        XCTAssertEqual(24, SubscriptionHeaders.parseUpdateInterval("24.0"))
        XCTAssertEqual(1, SubscriptionHeaders.parseUpdateInterval("0.5"))
        XCTAssertNil(SubscriptionHeaders.parseUpdateInterval("0"))
        XCTAssertNil(SubscriptionHeaders.parseUpdateInterval("abc"))
    }

    func testNestedSubscriptionURL() {
        let nested = "https://sub.example.org/link?id=42"
        XCTAssertEqual(nested, SubscriptionParser.isNestedSubscriptionURL(nested))
        XCTAssertNil(SubscriptionParser.isNestedSubscriptionURL("vless://uuid@1.2.3.4:443#x"))
        XCTAssertNil(SubscriptionParser.isNestedSubscriptionURL(
            "https://a.example.org\nhttps://b.example.org"
        ))
    }

    func testBase64WrappedLinkListParses() {
        let list = "vless://b831381d-6324-4d53-ad4f-8cda48b30811@1.2.3.4:443?security=tls#a\ntrojan://pass@5.6.7.8:443?security=tls#b"
        let wrapped = LinkUtils.encodeBase64(list)
        let profiles = SubscriptionParser.parse(wrapped)
        XCTAssertEqual(2, profiles.count)
        XCTAssertEqual(ProfileType.trojan, profiles.last?.type)
    }
}
