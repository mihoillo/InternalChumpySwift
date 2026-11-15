import Foundation
import CryptoKit

/// Prepares an Xray config's geodata: finds the databases its routing rules
/// reference, serves them from cache, downloads them from the panel's own
/// sources when they name any, rewrites the references onto the stored
/// files, and collects the leftovers. Ported from the Android client's
/// `GeodataFiles`; the directory is the core's own asset directory.
public actor GeodataFiles {

    public static let shared = GeodataFiles()

    public init() {}

    /// A downloaded database is served from cache this long, no matter what.
    static let cacheLifetime: TimeInterval = 86_400

    /// Provider files unreferenced this long are collected.
    static let collectionCutoff: TimeInterval = 7 * 86_400

    /// A pointer longer than this is junk.
    private static let maxPointerChars = 180

    /// The panel-named sources never cover a raw imported config's geosite
    /// needs; Xray's own rules-dat release is the standard fallback for it.
    static let standardGeositeURL =
        "https://github.com/XTLS/Xray-rules-dat/releases/latest/download/geosite.dat.gz"

    public enum PrepareError: Error, LocalizedError {
        case invalidReference
        case sourceMissing(file: String, categories: [String])
        case categoriesMissing([String])
        case downloadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidReference:
                return "Invalid geodata reference"
            case .sourceMissing(let file, let categories):
                return "Geodata source missing: \(file) (\(categories.joined(separator: ", ")))"
            case .categoriesMissing(let categories):
                return "Geodata categories missing: \(categories.joined(separator: ", "))"
            case .downloadFailed(let message):
                return "Geodata download failed: \(message)"
            }
        }
    }

    public struct Reference {
        public let value: String
        public let file: String
        public let category: String
    }

    // MARK: - Seeding

    /// The geo databases ship in the app bundle; the core wants them as
    /// plain files in its asset directory. The copy is unconditional: the
    /// databases are slim enough that re-placing them each start costs less
    /// than any version bookkeeping — and a build with changed databases
    /// always wins over whatever an older one had left on the device.
    /// Ported from the Android client's `XrayCore.copyGeoAssets`.
    nonisolated public static func seedBundled(
        bundle: Bundle = .main,
        directory: URL = ChumpyConstant.dataDir
    ) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["geosite.dat", "geoip.dat"] {
            let base = (name as NSString).deletingPathExtension
            let bundled = bundle.url(forResource: base, withExtension: "dat")
                ?? bundle.url(
                    forResource: base, withExtension: "dat", subdirectory: "Geodata"
                )
            guard let bundled else { continue }
            let target = directory.appendingPathComponent(name)
            let temporary = directory.appendingPathComponent("\(name).tmp")
            try? fm.removeItem(at: temporary)
            do {
                try fm.copyItem(at: bundled, to: temporary)
                if fm.fileExists(atPath: target.path) {
                    try? fm.removeItem(at: target)
                }
                try fm.moveItem(at: temporary, to: target)
            } catch {
                try? fm.removeItem(at: temporary)
            }
        }
    }

    // MARK: - Prepare

    /// Rewrites the config's routing so every geo reference points at a file
    /// the directory actually holds — cached, downloaded, or already there.
    ///
    /// The sources map names a database and the URL the panel serves it
    /// from; the download rides `fetch`, which writes the database to a
    /// temporary file. `protectedConfig` is the config the running core
    /// still holds (usually the current tunnel config) — its own references
    /// are protected from the collection pass.
    public func prepare(
        config: String,
        sources: String,
        directory: URL,
        allowStandardFallback: Bool = false,
        protectedConfig: String? = nil,
        now: Date = Date(),
        fetch: (_ url: String, _ target: URL) async throws -> Void
    ) async throws -> String {
        guard let data = config.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return config }

        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let refs = try Self.references(of: root)
        let urls = Dictionary(
            GeodataSources.parseSafely(sources).map { (GeodataSources.filenameFor($1), $1) },
            uniquingKeysWith: { first, _ in first }
        )

        var replacements: [String: String] = [:]
        for (file, requested) in Dictionary(grouping: refs, by: \.file) {
            let wanted = Set(requested.map { Self.categoryKey($0.category) })
            var url = urls[file]

            if url == nil {
                let available = GeodataCategories
                    .categories(ofFile: directory.appendingPathComponent(file)) ?? []
                let missing = wanted.subtracting(available)
                if missing.isEmpty { continue }
                if allowStandardFallback && file == "geosite.dat" {
                    url = Self.standardGeositeURL
                } else {
                    throw PrepareError.sourceMissing(
                        file: file, categories: missing.sorted()
                    )
                }
            }
            guard let url else { continue }

            // The cache: a pointer named after the URL holds the last
            // downloaded file's own name; the file is served while fresh and
            // covering, whatever the panel ships next.
            let pointer = directory.appendingPathComponent(
                "\(GeodataSources.filenameFor(url)).cache"
            )
            let cachedName = (try? String(contentsOf: pointer, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let validCachedName = cachedName.flatMap { name -> String? in
                guard name.count <= Self.maxPointerChars,
                      GeodataSources.validFilename(name)
                else { return nil }
                return name
            }
            let cached = validCachedName.map { directory.appendingPathComponent($0) }

            var cachedValid = false
            if let cached,
               let attributes = try? fm.attributesOfItem(atPath: cached.path),
               let size = (attributes[.size] as? NSNumber)?.int64Value,
               let modified = (attributes[.modificationDate] as? Date),
               size >= 1, size <= Int64(GeodataCategories.maxBytes),
               now.timeIntervalSince(modified) >= 0,
               now.timeIntervalSince(modified) <= Self.cacheLifetime,
               let present = GeodataCategories.categories(ofFile: cached),
               wanted.isSubset(of: present) {
                cachedValid = true
            }

            let selected: URL
            if cachedValid, let cached {
                selected = cached
            } else {
                do {
                    selected = try await download(
                        url: url, wanted: wanted,
                        pointer: pointer, directory: directory, cached: cached
                    ) { try await fetch($0, $1) }
                } catch let error as PrepareError {
                    // A database that lacks the wanted categories is a
                    // source problem, not a transport one — it surfaces as
                    // itself. The download failed otherwise; a stale cache
                    // that still covers the wanted categories beats a
                    // broken connect.
                    if let cached,
                       let present = GeodataCategories.categories(ofFile: cached),
                       wanted.isSubset(of: present) {
                        selected = cached
                    } else {
                        throw error
                    }
                } catch {
                    if let cached,
                       let present = GeodataCategories.categories(ofFile: cached),
                       wanted.isSubset(of: present) {
                        selected = cached
                    } else {
                        throw PrepareError.downloadFailed(error.localizedDescription)
                    }
                }
            }
            replacements[file] = selected.lastPathComponent
        }

        let prepared = Self.rewritten(root, replacements: replacements)
        let json = JSONX.toJSONString(prepared) ?? config

        // The collection pass: provider files the new config does not need
        // — and the running one still holds — fall away after a week.
        let protectedNames = Set(
            (try? Self.references(ofJSONString: json).map(\.file)) ?? []
        )
        .union(
            (try? Self.references(ofJSONString: protectedConfig ?? "").map(\.file)) ?? []
        )
        collectUnreferenced(
            in: directory, protected: protectedNames, now: now
        )
        return json
    }

    // MARK: - References

    /// The geo references of a routing rule set: every `geosite:`/`geoip:`
    /// /`ext:` value of the `domain`/`ip`/`source` fields.
    static func references(of root: [String: Any]) throws -> [Reference] {
        let routing = root["routing"] as? [String: Any]
        let rules = (routing?["rules"] as? [[String: Any]]) ?? []
        var result: [Reference] = []
        for rule in rules {
            for key in ["domain", "ip", "source"] {
                let value = rule[key]
                let values: [Any]
                if let array = value as? [Any] {
                    values = array
                } else if let value {
                    values = [value]
                } else {
                    continue
                }
                for element in values {
                    guard let text = JSONX.strValue(element) else { continue }
                    if text.hasPrefix("geosite:") {
                        result.append(Reference(
                            value: text, file: "geosite.dat",
                            category: String(text.dropFirst("geosite:".count))
                        ))
                    } else if text.hasPrefix("geoip:") {
                        result.append(Reference(
                            value: text, file: "geoip.dat",
                            category: String(text.dropFirst("geoip:".count))
                        ))
                    } else if text.hasPrefix("ext:") {
                        let parts = text.split(separator: ":", maxSplits: 2)
                            .map(String.init)
                        guard parts.count == 3, GeodataSources.validFilename(parts[1]) else {
                            throw PrepareError.invalidReference
                        }
                        result.append(Reference(
                            value: text, file: parts[1], category: parts[2]
                        ))
                    }
                }
            }
        }
        return result
    }

    static func references(ofJSONString json: String) throws -> [Reference] {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [] }
        return try references(of: root)
    }

    /// The category a rule means, in the container's own spelling: the
    /// negation and attribute decoration off, uppercased.
    static func categoryKey(_ category: String) -> String {
        var key = category
        if key.hasPrefix("!") { key = String(key.dropFirst()) }
        if let at = key.firstIndex(of: "@") {
            key = String(key[..<at])
        }
        return key.uppercased()
    }

    // MARK: - Download

    private func download(
        url: String,
        wanted: Set<String>,
        pointer: URL,
        directory: URL,
        cached: URL?,
        fetch: (_ url: String, _ target: URL) async throws -> Void
    ) async throws -> URL {
        let fm = FileManager.default
        let temporary = directory.appendingPathComponent(
            "geodata-\(UUID().uuidString).part"
        )
        defer { try? fm.removeItem(at: temporary) }

        try await fetch(url, temporary)
        guard let present = GeodataCategories.categories(ofFile: temporary) else {
            throw PrepareError.downloadFailed("invalid geodata")
        }
        let missing = wanted.subtracting(present)
        if !missing.isEmpty {
            throw PrepareError.categoriesMissing(missing.sorted())
        }

        let digest = SHA256.hash(data: try Data(contentsOf: temporary))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let target = directory.appendingPathComponent("provider-\(hex).dat")
        if fm.fileExists(atPath: target.path) {
            // Already stored under its content's own name; refresh its age.
            try? fm.setAttributes(
                [.modificationDate: Date()], ofItemAtPath: target.path
            )
        } else {
            try fm.moveItem(at: temporary, to: target)
        }
        try? Data(target.lastPathComponent.utf8).write(to: pointer, options: .atomic)
        return target
    }

    // MARK: - Rewriting

    /// The config with every geo reference aimed at the stored files.
    ///
    /// Deviation from the Kotlin original, which leaves `geoip:` values
    /// untouched: a downloaded `geoip.dat` replacement would be renamed out
    /// of the rules' reach — the rewrite covers `geoip:` exactly like
    /// `geosite:`.
    static func rewritten(
        _ root: [String: Any], replacements: [String: String]
    ) -> [String: Any] {
        guard !replacements.isEmpty,
              var routing = root["routing"] as? [String: Any],
              let rules = routing["rules"] as? [[String: Any]]
        else { return root }

        func remap(_ element: Any) -> Any {
            guard let text = JSONX.strValue(element) else { return element }
            if text.hasPrefix("ext:") {
                let parts = text.split(separator: ":", maxSplits: 2).map(String.init)
                if parts.count == 3, let replacement = replacements[parts[1]] {
                    return "ext:\(replacement):\(parts[2])" as NSString
                }
                return element
            }
            for (prefix, file) in [("geosite:", "geosite.dat"), ("geoip:", "geoip.dat")] {
                if text.hasPrefix(prefix), let replacement = replacements[file] {
                    return "ext:\(replacement):\(String(text.dropFirst(prefix.count)))"
                        as NSString
                }
            }
            return element
        }

        let rewrittenRules = rules.map { rule -> [String: Any] in
            var rule = rule
            for key in ["domain", "ip", "source"] {
                guard let value = rule[key] else { continue }
                if let array = value as? [Any] {
                    rule[key] = array.map(remap)
                } else {
                    rule[key] = remap(value)
                }
            }
            return rule
        }
        routing["rules"] = rewrittenRules
        var prepared = root
        prepared["routing"] = routing
        return prepared
    }

    // MARK: - Collection

    private func collectUnreferenced(
        in directory: URL, protected: Set<String>, now: Date
    ) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = now.addingTimeInterval(-Self.collectionCutoff)
        for file in files where file.lastPathComponent.hasPrefix("provider-")
            && file.pathExtension == "dat"
            && !protected.contains(file.lastPathComponent) {
            guard let modified = (try? file.resourceValues(
                forKeys: [.contentModificationDateKey]
            ))?.contentModificationDate, modified < cutoff
            else { continue }
            try? fm.removeItem(at: file)
        }
    }
}
