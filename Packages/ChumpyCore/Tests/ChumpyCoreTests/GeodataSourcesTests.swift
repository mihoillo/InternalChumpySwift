import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `GeodataSourcesTest`.
final class GeodataSourcesTests: XCTestCase {

    private let onadd = "happ://routing/onadd/"
    private let add = "happ://routing/add/"

    private func header(
        _ profile: String,
        prefix: String = "happ://routing/onadd/"
    ) -> String {
        prefix + LinkUtils.encodeBase64(profile)
    }

    private func sources(_ profile: String) -> [String: String] {
        (try? GeodataSources.parse(GeodataSources.fromHappHeader(header(profile)))) ?? [:]
    }

    private func profile(_ geoip: String?, _ geosite: String?) -> String {
        var entries: [String] = []
        if let geoip { entries.append(#""Geoipurl":"\#(geoip)""#) }
        if let geosite { entries.append(#""Geositeurl":"\#(geosite)""#) }
        return "{" + entries.joined(separator: ",") + "}"
    }

    func testPlainBase64HeaderYieldsBothDatabases() {
        let parsed = sources(profile("https://cdn.example.org/geoip.dat", "https://cdn.example.org/geosite.dat"))
        XCTAssertEqual("https://cdn.example.org/geoip.dat", parsed["geoip.dat"])
        XCTAssertEqual("https://cdn.example.org/geosite.dat", parsed["geosite.dat"])
    }

    func testURLEncodedBase64HeaderIsDecoded() {
        let payload = profile("https://cdn.example.org/geoip.dat", "https://cdn.example.org/geosite.dat")
        let encoded = LinkUtils.encodeURIComponent(LinkUtils.encodeBase64(payload))
        let parsed = (try? GeodataSources.parse(
            GeodataSources.fromHappHeader(onadd + encoded)
        )) ?? [:]
        XCTAssertEqual("https://cdn.example.org/geoip.dat", parsed["geoip.dat"])
        XCTAssertEqual("https://cdn.example.org/geosite.dat", parsed["geosite.dat"])
    }

    func testBase64URLWithoutPaddingIsDecoded() {
        // The trailing "ÿÿÿ" forces '+' or '/' into the standard alphabet.
        let payload = #"{"Geoipurl":"https://cdn.example.org/geoip.dat?q=ÿÿÿ","Geositeurl":"https://cdn.example.org/geosite.dat"}"#
        let standard = LinkUtils.encodeBase64(payload)
        XCTAssertTrue(standard.contains("+") || standard.contains("/"))
        let base64url = standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        var trimmed = base64url
        while trimmed.hasSuffix("=") { trimmed.removeLast() }
        let parsed = (try? GeodataSources.parse(
            GeodataSources.fromHappHeader(onadd + trimmed)
        )) ?? [:]
        XCTAssertEqual("https://cdn.example.org/geoip.dat?q=ÿÿÿ", parsed["geoip.dat"])
        XCTAssertEqual("https://cdn.example.org/geosite.dat", parsed["geosite.dat"])
    }

    func testUppercasePrefixIsAccepted() {
        let parsed = (try? GeodataSources.parse(
            GeodataSources.fromHappHeader(
                header(profile("https://cdn.example.org/geoip.dat", nil), prefix: "HAPP://ROUTING/ONADD/")
            )
        )) ?? [:]
        XCTAssertEqual("https://cdn.example.org/geoip.dat", parsed["geoip.dat"])
    }

    func testOlderAddPrefixIsAccepted() {
        let parsed = (try? GeodataSources.parse(
            GeodataSources.fromHappHeader(
                header(profile(nil, "https://cdn.example.org/geosite.dat"), prefix: add)
            )
        )) ?? [:]
        XCTAssertEqual("https://cdn.example.org/geosite.dat", parsed["geosite.dat"])
    }

    func testMissingKeyLeavesOnlyOtherDatabase() {
        let parsed = sources(profile("https://cdn.example.org/geoip.dat", nil))
        XCTAssertEqual("https://cdn.example.org/geoip.dat", parsed["geoip.dat"])
        XCTAssertNil(parsed["geosite.dat"])
    }

    func testEmptyURLsProduceNoSources() {
        XCTAssertEqual("", GeodataSources.fromHappHeader(header(profile("", ""))))
    }

    func testMalformedInputProducesNoSources() {
        let cases = [
            "",
            "not a link",
            onadd + "@@@",
            header("[]"),
            header("null"),
        ]
        for c in cases {
            XCTAssertEqual("", GeodataSources.fromHappHeader(c), "case: \(c)")
        }
    }

    func testOversizedHeaderIsIgnored() {
        let huge = onadd + String(repeating: "A", count: 256 * 1024 + 1)
        XCTAssertEqual("", GeodataSources.fromHappHeader(huge))
    }

    func testKeysAreMatchedCaseInsensitively() {
        let lower = (try? GeodataSources.parse(
            GeodataSources.fromHappHeader(header(#"{"geoipurl":"https://cdn.example.org/geoip.dat"}"#))
        )) ?? [:]
        XCTAssertEqual("https://cdn.example.org/geoip.dat", lower["geoip.dat"])

        let mixed = (try? GeodataSources.parse(
            GeodataSources.fromHappHeader(
                header(
                    #"{"GeoipUrl":"https://cdn.example.org/geoip.dat","GEOSITEURL":"https://cdn.example.org/geosite.dat"}"#
                )
            )
        )) ?? [:]
        XCTAssertEqual("https://cdn.example.org/geoip.dat", mixed["geoip.dat"])
        XCTAssertEqual("https://cdn.example.org/geosite.dat", mixed["geosite.dat"])
    }

    func testMergeKeepsOtherDatabaseAndLetsOverridesWin() {
        let defaults = #"{"geosite.dat":"https://header.example.org/geosite.dat","geoip.dat":"https://header.example.org/geoip.dat"}"#
        let overrides = #"{"geosite.dat":"https://body.example.org/geosite.dat"}"#
        let merged = (try? GeodataSources.parse(GeodataSources.merge(defaults, overrides))) ?? [:]
        XCTAssertEqual("https://body.example.org/geosite.dat", merged["geosite.dat"])
        XCTAssertEqual("https://header.example.org/geoip.dat", merged["geoip.dat"])
    }

    func testMergeToleratesMalformedSides() {
        let defaults = #"{"geosite.dat":"https://header.example.org/geosite.dat"}"#
        let malformedOverrides = (try? GeodataSources.parse(
            GeodataSources.merge(defaults, "not json")
        )) ?? [:]
        XCTAssertEqual("https://header.example.org/geosite.dat", malformedOverrides["geosite.dat"])
        let malformedDefaults = (try? GeodataSources.parse(
            GeodataSources.merge("not json", defaults)
        )) ?? [:]
        XCTAssertEqual("https://header.example.org/geosite.dat", malformedDefaults["geosite.dat"])
        XCTAssertEqual("", GeodataSources.merge("not json", "[]"))
    }

    func testMergeTakesAlreadyParsedDefaultsMap() {
        let merged = (try? GeodataSources.parse(
            GeodataSources.merge(
                ["geoip.dat": "https://header.example.org/geoip.dat"],
                #"{"geosite.dat":"https://body.example.org/geosite.dat"}"#
            )
        )) ?? [:]
        XCTAssertEqual("https://header.example.org/geoip.dat", merged["geoip.dat"])
        XCTAssertEqual("https://body.example.org/geosite.dat", merged["geosite.dat"])
    }

    func testParseSafelyTurnsGarbageIntoNoSources() {
        XCTAssertTrue(GeodataSources.parseSafely("not json").isEmpty)
        XCTAssertTrue(GeodataSources.parseSafely("[]").isEmpty)
        XCTAssertEqual(
            ["geosite.dat": "https://cdn.example.org/geosite.dat"],
            GeodataSources.parseSafely(#"{"geosite.dat":"https://cdn.example.org/geosite.dat"}"#)
        )
    }

    func testConfigBodySourcesWinOverHeader() {
        let fromHeader = GeodataSources.fromHappHeader(
            header(profile("https://header.example.org/geoip.dat", "https://header.example.org/geosite.dat"))
        )
        let bodyData = Data(
            #"{"geodata":{"assets":[{"file":"geosite.dat","url":"https://body.example.org/geosite.dat"}]}}"#.utf8
        )
        guard let bodyObj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            return XCTFail("bad json")
        }
        let fromBody = GeodataSources.fromConfig(bodyObj)
        let merged = (try? GeodataSources.parse(GeodataSources.merge(fromHeader, fromBody))) ?? [:]
        XCTAssertEqual("https://body.example.org/geosite.dat", merged["geosite.dat"])
        XCTAssertEqual("https://header.example.org/geoip.dat", merged["geoip.dat"])
    }

    func testValidFilename() {
        XCTAssertTrue(GeodataSources.validFilename("geoip.dat"))
        XCTAssertTrue(GeodataSources.validFilename("provider-abc123.dat"))
        XCTAssertFalse(GeodataSources.validFilename("../evil.dat"))
        XCTAssertFalse(GeodataSources.validFilename(".dat"))
        XCTAssertFalse(GeodataSources.validFilename("geoip.txt"))
    }

    func testRewriteRemapsGeoRefs() {
        let sources = #"{"geoip.dat":"https://cdn.example.org/geoip.dat","geosite.dat":"https://cdn.example.org/geosite.dat"}"#
        let rule: [String: Any] = [
            "type": "field",
            "domain": ["geosite:category-ads", "domain:plain.example"],
            "ip": ["geoip:ru", "10.0.0.0/8"],
        ]
        let rewritten = GeodataSources.rewrite(rule, sources)
        let domains = rewritten["domain"] as? [Any] ?? []
        XCTAssertEqual(2, domains.count)
        let first = JSONX.strValue(domains.first)
        XCTAssertEqual("ext:\(GeodataSources.filenameFor("https://cdn.example.org/geosite.dat")):category-ads", first)
        XCTAssertEqual("domain:plain.example", JSONX.strValue(domains.last))
        let ips = rewritten["ip"] as? [Any] ?? []
        XCTAssertEqual("ext:\(GeodataSources.filenameFor("https://cdn.example.org/geoip.dat")):ru", JSONX.strValue(ips.first))
        XCTAssertEqual("10.0.0.0/8", JSONX.strValue(ips.last))
    }
}
