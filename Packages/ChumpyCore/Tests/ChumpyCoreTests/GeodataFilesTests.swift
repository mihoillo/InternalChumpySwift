import XCTest
@testable import ChumpyCore

/// Geodata preparation: downloads onto content-addressed files, the
/// pointer cache, the rewrites onto `ext:` references, the collection pass
/// and the URL guards. Ported from the Android client's
/// `GeodataFiles.prepare` semantics.
final class GeodataFilesTests: XCTestCase {

    typealias FetchError = SubscriptionFetcher.FetchError

    private var directory: URL!
    private var files: GeodataFiles!
    private var now: Date!

    /// The databases `fetch` serves.
    private var served: [String: Data] = [:]
    /// The URLs `fetch` was asked for, in order.
    private var fetched: [String] = []
    /// When set, `fetch` fails with this message instead of serving.
    private var fetchError: String?

    private let calendar = Calendar(identifier: .gregorian)

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("geodata-\(UUID().uuidString)", isDirectory: true)
        files = GeodataFiles()
        now = calendar.date(
            from: DateComponents(year: 2026, month: 11, day: 16, hour: 12)
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        files = nil
        super.tearDown()
    }

    // MARK: - Crafting

    private func varint(_ value: Int) -> [UInt8] {
        var remaining = UInt64(value)
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            out.append(byte)
        } while remaining != 0
        return out
    }

    private func container(_ names: [String]) -> Data {
        var data = Data()
        for name in names {
            var entry = Data([0x0A])
            entry.append(contentsOf: varint(name.utf8.count))
            entry.append(contentsOf: Array(name.utf8))
            data.append(0x0A)
            data.append(contentsOf: varint(entry.count))
            data.append(entry)
        }
        return data
    }

    private func config(rules: [[String: Any]]) -> String {
        let root: [String: Any] = [
            "outbounds": [["protocol": "freedom", "tag": "direct"]],
            "routing": ["rules": rules],
        ]
        return JSONX.toJSONString(root)!
    }

    private func rule(domain: Any, ip: Any? = nil, outbound: String = "direct") -> [[String: Any]] {
        var rule: [String: Any] = ["type": "field", "domain": domain, "outboundTag": outbound]
        if let ip { rule["ip"] = ip }
        return [rule]
    }

    private func sources(_ map: [String: String]) -> String {
        JSONX.toJSONString(map)!
    }

    private func domainValues(of json: String) -> [String] {
        let root = try! JSONSerialization.jsonObject(
            with: Data(json.utf8)
        ) as! [String: Any]
        let routing = root["routing"] as! [String: Any]
        let rules = routing["rules"] as! [[String: Any]]
        return JSONX.strings(rules[0]["domain"] as? [Any])
    }

    private func ipValues(of json: String) -> [String] {
        let root = try! JSONSerialization.jsonObject(
            with: Data(json.utf8)
        ) as! [String: Any]
        let routing = root["routing"] as! [String: Any]
        let rules = routing["rules"] as! [[String: Any]]
        return JSONX.strings(rules[0]["ip"] as? [Any])
    }

    private func canonical(_ json: String) -> String {
        let object = try! JSONSerialization.jsonObject(with: Data(json.utf8))
        let data = try! JSONSerialization.data(
            withJSONObject: object, options: [.sortedKeys]
        )
        return String(data: data, encoding: .utf8)!
    }

    private func fetch(url: String, target: URL) async throws -> Void {
        fetched.append(url)
        if let fetchError {
            _ = fetchError
            throw FetchError.http(500)
        }
        guard let data = served[url] else {
            throw FetchError.emptyBody
        }
        try data.write(to: target, options: .atomic)
        // A stable age, whatever the runner's wall clock says: the cache
        // freshness checks run against the test's own `now`.
        try? FileManager.default.setAttributes(
            [.modificationDate: now], ofItemAtPath: target.path
        )
    }

    // MARK: - Prepare

    private func prepare(
        _ config: String,
        sources: String = "{}",
        allowStandardFallback: Bool = false,
        protectedConfig: String? = nil
    ) async throws -> String {
        try await files.prepare(
            config: config,
            sources: sources,
            directory: directory,
            allowStandardFallback: allowStandardFallback,
            protectedConfig: protectedConfig,
            now: now,
            fetch: { url, target in try await self.fetch(url: url, target: target) }
        )
    }

    private func providerFiles() -> [String] {
        (try! FileManager.default.contentsOfDirectory(atPath: directory.path))
            .filter { $0.hasPrefix("provider-") && $0.hasSuffix(".dat") }
            .sorted()
    }

    // MARK: - No references

    func testConfigWithoutGeoReferencesPassesThrough() async throws {
        let config = self.config(rules: rule(domain: ["domain:example.com"]))
        let prepared = try await prepare(config)
        XCTAssertEqual(canonical(config), canonical(prepared))
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Download and rewrite

    func testDownloadRewritesGeositeReferences() async throws {
        served["https://panel.example/geosite.dat"] = container(["RU", "CN"])
        let config = self.config(
            rules: rule(domain: ["geosite:RU", "geosite:!CN@attr", "domain:example.com"])
        )
        let prepared = try await prepare(
            config, sources: sources(["geosite.dat": "https://panel.example/geosite.dat"])
        )

        let values = domainValues(of: prepared)
        XCTAssertEqual(3, values.count)
        XCTAssertEqual("domain:example.com", values[2])
        // Both references now point at the stored provider file, decoration
        // kept in the category part, the file part identical.
        let rewritten = values[0].split(separator: ":", maxSplits: 2).map(String.init)
        XCTAssertEqual("ext", rewritten[0])
        XCTAssertTrue(rewritten[1].hasPrefix("provider-"))
        XCTAssertTrue(rewritten[1].hasSuffix(".dat"))
        XCTAssertEqual("RU", rewritten[2])
        XCTAssertEqual(
            String(values[0].split(separator: ":", maxSplits: 2).dropFirst().first ?? ""),
            String(values[1].split(separator: ":", maxSplits: 2).dropFirst().first ?? "")
        )
        XCTAssertTrue(
            values[1].hasSuffix(":!CN@attr"),
            "the decoration survives in the category part: \(values[1])"
        )

        // The stored file and its pointer are in place, and the config's
        // reference names the very file the directory holds.
        XCTAssertEqual(1, providerFiles().count)
        let stored = rewritten[1]
        XCTAssertTrue(providerFiles().contains(stored))
        let pointer = directory.appendingPathComponent(
            "\(GeodataSources.filenameFor("https://panel.example/geosite.dat")).cache"
        )
        XCTAssertEqual(
            stored,
            try String(contentsOf: pointer, encoding: .utf8).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        )
    }

    func testGeoipReferencesAreRewrittenToo() async throws {
        served["https://panel.example/geoip.dat"] = container(["CN", "RU"])
        let config = self.config(rules: rule(domain: ["domain:example.com"], ip: ["geoip:CN"]))
        let prepared = try await prepare(
            config, sources: sources(["geoip.dat": "https://panel.example/geoip.dat"])
        )
        let values = ipValues(of: prepared)
        XCTAssertEqual(1, values.count)
        XCTAssertTrue(values[0].hasPrefix("ext:provider-"))
        XCTAssertTrue(values[0].hasSuffix(":CN"))
    }

    func testExtReferencesAreRewritten() async throws {
        served["https://panel.example/custom.dat"] = container(["RU"])
        let config = self.config(rules: rule(domain: ["ext:custom.dat:RU"]))
        let prepared = try await prepare(
            config, sources: sources(["custom.dat": "https://panel.example/custom.dat"])
        )
        let value = domainValues(of: prepared)[0]
        XCTAssertTrue(value.hasPrefix("ext:provider-"))
        XCTAssertTrue(value.hasSuffix(":RU"))
    }

    func testMissingSourceWithoutFallbackThrows() async throws {
        let config = self.config(rules: rule(domain: ["ext:custom.dat:RU"]))
        do {
            _ = try await prepare(config)
            XCTFail("prepare must throw without a source")
        } catch let error as GeodataFiles.PrepareError {
            guard case .sourceMissing(let file, let categories) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual("custom.dat", file)
            XCTAssertEqual(["RU"], categories)
        }
    }

    func testStandardFallbackCoversBareGeosite() async throws {
        served[GeodataFiles.standardGeositeURL] = container(["RU"])
        let config = self.config(rules: rule(domain: ["geosite:RU"]))
        let prepared = try await prepare(config, allowStandardFallback: true)
        XCTAssertEqual([GeodataFiles.standardGeositeURL], fetched)
        XCTAssertTrue(domainValues(of: prepared)[0].hasPrefix("ext:provider-"))
    }

    func testStandardFallbackIgnoredForGeoipAndCustomFiles() async throws {
        let config = self.config(rules: rule(domain: ["geoip:RU"], ip: ["geoip:RU"]))
        do {
            _ = try await prepare(config, allowStandardFallback: true)
            XCTFail("the fallback is geosite-only")
        } catch let error as GeodataFiles.PrepareError {
            guard case .sourceMissing = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testAvailableDatabaseSkipsTheDownload() async throws {
        try container(["RU", "CN"]).write(
            to: directory.appendingPathComponent("geosite.dat")
        )
        let config = self.config(rules: rule(domain: ["geosite:RU"]))
        let prepared = try await prepare(config)
        XCTAssertTrue(fetched.isEmpty)
        XCTAssertEqual(["geosite:RU"], domainValues(of: prepared))
    }

    func testCategoriesMissingThrows() async throws {
        served["https://panel.example/geosite.dat"] = container(["CN"])
        let config = self.config(rules: rule(domain: ["geosite:RU"]))
        do {
            _ = try await prepare(
                config, sources: sources(["geosite.dat": "https://panel.example/geosite.dat"])
            )
            XCTFail("a database without the wanted category must throw")
        } catch let error as GeodataFiles.PrepareError {
            guard case .categoriesMissing(let categories) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(["RU"], categories)
        }
    }

    func testInvalidExtReferenceThrows() async throws {
        let config = self.config(rules: rule(domain: ["ext:../evil.dat:RU"]))
        do {
            _ = try await prepare(config)
            XCTFail("an invalid reference must throw")
        } catch let error as GeodataFiles.PrepareError {
            guard case .invalidReference = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    // MARK: - The cache

    func testFreshCacheSkipsTheDownload() async throws {
        served["https://panel.example/geosite.dat"] = container(["RU"])
        let config = self.config(rules: rule(domain: ["geosite:RU"]))
        let url = sources(["geosite.dat": "https://panel.example/geosite.dat"])
        let first = try await prepare(config, sources: url)
        XCTAssertEqual(1, fetched.count)
        let second = try await prepare(config, sources: url)
        XCTAssertEqual(1, fetched.count, "the fresh cache must serve the second prepare")
        XCTAssertEqual(
            domainValues(of: first)[0], domainValues(of: second)[0]
        )
    }

    func testStaleCacheBeatsAFailedDownload() async throws {
        served["https://panel.example/geosite.dat"] = container(["RU"])
        let config = self.config(rules: rule(domain: ["geosite:RU"]))
        let url = sources(["geosite.dat": "https://panel.example/geosite.dat"])
        let first = try await prepare(config, sources: url)

        // The cached provider file ages past the cache lifetime.
        let stored = providerFiles()
        XCTAssertEqual(1, stored.count)
        let fm = FileManager.default
        try fm.setAttributes(
            [.modificationDate: now.addingTimeInterval(-2 * 86_400)],
            ofItemAtPath: directory.appendingPathComponent(stored[0]).path
        )

        fetchError = "offline"
        let second = try await prepare(config, sources: url)
        XCTAssertEqual(
            domainValues(of: first)[0], domainValues(of: second)[0],
            "the stale cache must serve when the download fails"
        )
    }

    func testCacheNotCoveringTheWantedCategoryIsRedownloaded() async throws {
        served["https://panel.example/geosite.dat"] = container(["RU"])
        let config = self.config(rules: rule(domain: ["geosite:RU"]))
        let url = sources(["geosite.dat": "https://panel.example/geosite.dat"])
        _ = try await prepare(config, sources: url)

        // The panel now ships the missing category too; the fresh but
        // non-covering cache must give way.
        served["https://panel.example/geosite.dat"] = container(["RU", "CN"])
        let extended = self.config(rules: rule(domain: ["geosite:RU", "geosite:CN"]))
        let prepared = try await prepare(extended, sources: url)
        XCTAssertEqual(2, fetched.count)

        // Both references aim at the new content-addressed file, with their
        // own categories intact.
        let values = domainValues(of: prepared)
        XCTAssertEqual(2, values.count)
        let fileParts = Set(values.map {
            String($0.split(separator: ":", maxSplits: 2).dropFirst().first ?? "")
        })
        XCTAssertEqual(1, fileParts.count)
        let categories = Set(values.map {
            String($0.split(separator: ":", maxSplits: 2).dropFirst(2).joined())
        })
        XCTAssertEqual(["CN", "RU"], categories.sorted())
        let filePart = values[0]
            .split(separator: ":", maxSplits: 2)
            .map(String.init)[1]
        // The old database stays until the collection week passes; the new
        // one joins it under its own content address.
        XCTAssertEqual(2, providerFiles().count)
        XCTAssertTrue(providerFiles().contains(filePart))
    }

    // MARK: - Collection

    private func touch(_ name: String, age: TimeInterval) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try container(["RU"]).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-age)],
            ofItemAtPath: url.path
        )
        return url
    }

    func testUnreferencedProviderFilesAreCollectedAfterAWeek() async throws {
        try touch("provider-gone.dat", age: 8 * 86_400)
        try touch("provider-fresh.dat", age: 86_400)
        let config = self.config(rules: rule(domain: ["domain:example.com"]))
        _ = try await prepare(config)
        let remaining = Set(providerFiles())
        XCTAssertFalse(remaining.contains("provider-gone.dat"))
        XCTAssertTrue(remaining.contains("provider-fresh.dat"))
    }

    func testReferencedProviderFileIsProtected() async throws {
        try touch("provider-kept.dat", age: 8 * 86_400)
        // The running config still needs the old file.
        let protected = self.config(rules: rule(domain: ["ext:provider-kept.dat:RU"]))
        let config = self.config(rules: rule(domain: ["domain:example.com"]))
        _ = try await prepare(config, protectedConfig: protected)
        XCTAssertTrue(Set(providerFiles()).contains("provider-kept.dat"))
    }

    func testProviderFilesReferencedByTheNewConfigSurvive() async throws {
        served["https://panel.example/geosite.dat"] = container(["RU"])
        let config = self.config(rules: rule(domain: ["geosite:RU"]))
        _ = try await prepare(
            config, sources: sources(["geosite.dat": "https://panel.example/geosite.dat"])
        )
        let stored = providerFiles()
        XCTAssertEqual(1, stored.count)

        // A second connect with the same config: the file is fresh (just
        // stored), but even the aging test above holds only because the
        // new config's own references are protected from collection.
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-8 * 86_400)],
            ofItemAtPath: directory.appendingPathComponent(stored[0]).path
        )
        _ = try await prepare(
            config, sources: sources(["geosite.dat": "https://panel.example/geosite.dat"])
        )
        // The stale file forced a re-download — served from the network
        // again and stored under the same content address.
        XCTAssertEqual(Set([stored[0]]), Set(providerFiles()))
    }

    // MARK: - Seeding

    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "dat")
            ?? Bundle.module.url(
                forResource: name, withExtension: "dat", subdirectory: "Geodata"
            )
        return try Data(contentsOf: XCTUnwrap(url))
    }

    func testSeedBundledPlacesTheDatabases() throws {
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: target) }
        GeodataFiles.seedBundled(bundle: Bundle.module, directory: target)
        XCTAssertEqual(try fixture("geosite"), try Data(contentsOf: target.appendingPathComponent("geosite.dat")))
        XCTAssertEqual(try fixture("geoip"), try Data(contentsOf: target.appendingPathComponent("geoip.dat")))
    }

    // MARK: - Category key

    func testCategoryKeyStripsDecoration() {
        XCTAssertEqual("RU", GeodataFiles.categoryKey("!RU@attr"))
        XCTAssertEqual("RU", GeodataFiles.categoryKey("ru"))
        XCTAssertEqual("RU", GeodataFiles.categoryKey("RU"))
        XCTAssertEqual("", GeodataFiles.categoryKey("!"))
        XCTAssertEqual("", GeodataFiles.categoryKey("@attr"))
    }

    // MARK: - Geodata URL guards

    func testValidatedGeodataURLAcceptsPlainHTTPS() throws {
        let url = try SubscriptionFetcher.validatedGeodataURL("https://panel.example/geosite.dat")
        XCTAssertEqual("panel.example", url.host)
    }

    func testValidatedGeodataURLRejectsEverythingElse() {
        for raw in [
            "http://panel.example/geosite.dat",
            "https://user:pass@panel.example/geosite.dat",
            "https://user@panel.example/geosite.dat",
            "ftp://panel.example/geosite.dat",
            "not a url",
        ] {
            XCTAssertThrowsError(try SubscriptionFetcher.validatedGeodataURL(raw)) { error in
                XCTAssertEqual(
                    FetchError.badGeodataURL, error as? FetchError, "rejected: \(raw)"
                )
            }
        }
    }

    func testFetchGeodataRejectsBadURLBeforeAnyRequest() async {
        let fetcher = SubscriptionFetcher(tunnelUp: { false })
        do {
            try await fetcher.fetchGeodata(
                "http://panel.example/geosite.dat",
                to: directory.appendingPathComponent("out.dat")
            )
            XCTFail("a non-HTTPS geodata URL must throw before any request")
        } catch let error as FetchError {
            XCTAssertEqual(.badGeodataURL, error)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
