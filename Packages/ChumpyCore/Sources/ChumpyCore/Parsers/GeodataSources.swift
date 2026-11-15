import Foundation
import CryptoKit

/// The geodata sources a subscription names: which databases its routing needs
/// and where the provider's own copies can be downloaded from. Ported from the
/// Android client's `GeodataSources`.
public enum GeodataSources {

    /// A routing header longer than this is junk; no real profile comes close.
    private static let maxHappHeaderChars = 256 * 1024
    private static let happOnAddPrefix = "happ://routing/onadd/"
    private static let happAddPrefix = "happ://routing/add/"

    public static func validFilename(_ name: String) -> Bool {
        guard !name.contains("..") else { return false }
        guard let regex = try? NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}\\.dat$") else {
            return false
        }
        let range = NSRange(name.startIndex..., in: name)
        return regex.firstMatch(in: name, range: range) != nil
    }

    /// Extracts the database URLs from a Happ routing header —
    /// `happ://routing/onadd/<data>` or the older `happ://routing/add/<data>`,
    /// where `<data>` is the base64 of a Happ routing profile.
    /// Only `Geoipurl`/`Geositeurl` are consumed, case-insensitively.
    public static func fromHappHeader(_ header: String) -> String {
        let value = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix: String?
        if value.lowercased().hasPrefix(happOnAddPrefix) {
            prefix = happOnAddPrefix
        } else if value.lowercased().hasPrefix(happAddPrefix) {
            prefix = happAddPrefix
        } else {
            prefix = nil
        }
        guard let prefix else { return "" }
        guard value.count <= maxHappHeaderChars else { return "" }
        guard let decoded = LinkUtils.decodeBase64(
            LinkUtils.decodeURIComponent(String(value.dropFirst(prefix.count)))
        ) else { return "" }
        guard let data = decoded.data(using: .utf8),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "" }

        var sources: [String: String] = [:]
        for (key, file) in [("geoipurl", "geoip.dat"), ("geositeurl", "geosite.dat")] {
            let url = JSONX.stringIgnoreCase(config, key)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !url.isEmpty {
                sources[file] = url
            }
        }
        return encode(sources)
    }

    /// The union of two source sets; `overrides` wins per database key.
    public static func merge(_ defaults: String, _ overrides: String) -> String {
        merge(parseSafely(defaults), overrides)
    }

    public static func merge(_ defaults: [String: String], _ overrides: String) -> String {
        var merged = defaults
        for (key, value) in parseSafely(overrides) {
            merged[key] = value
        }
        return encode(merged)
    }

    /// [parse] without the throw: a broken source becomes no sources.
    public static func parseSafely(_ sources: String) -> [String: String] {
        (try? parse(sources)) ?? [:]
    }

    private static func encode(_ sources: [String: String]) -> String {
        guard !sources.isEmpty else { return "" }
        return JSONX.toJSONString(
            sources.mapValues { $0 as NSString }
        ) ?? ""
    }

    /// From a raw config's `geodata`/`geox-url` blocks.
    public static func fromConfig(_ config: [String: Any]) -> String {
        var sources: [String: String] = [:]
        if let geodata = config["geodata"] as? [String: Any],
           let assets = geodata["assets"] as? [[String: Any]] {
            for entry in assets {
                let name = JSONX.strValue(entry["file"]) ?? ""
                let url = JSONX.strValue(entry["url"]) ?? ""
                if validFilename(name) && !url.isEmpty {
                    sources[name] = url
                }
            }
        }
        if let urls = config["geox-url"] as? [String: Any] {
            for key in ["geoip", "geosite"] {
                if let url = JSONX.strValue(urls[key]), !url.isEmpty,
                   sources["\(key).dat"] == nil {
                    sources["\(key).dat"] = url
                }
            }
        }
        return encode(sources)
    }

    /// Parses a sources JSON string; throws on malformed input.
    public static func parse(_ sources: String) throws -> [String: String] {
        guard !sources.trimmingCharacters(in: .whitespaces).isEmpty else { return [:] }
        guard let data = sources.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw GeodataError.invalidSources }
        var result: [String: String] = [:]
        for (key, value) in entries {
            guard let url = JSONX.strValue(value) else { throw GeodataError.invalidURL }
            guard validFilename(key) else { throw GeodataError.invalidFilename }
            result[key] = url
        }
        return result
    }

    public enum GeodataError: Error {
        case invalidSources
        case invalidURL
        case invalidFilename
    }

    /// The local filename a provider database is stored under.
    public static func filenameFor(_ url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "provider-\(hex).dat"
    }

    /// Rewrites `geosite:`/`geoip:`/`ext:` references in a routing rule onto the
    /// provider-named files the sources describe.
    public static func rewrite(_ rule: [String: Any], _ sources: String) -> [String: Any] {
        let files = parseSafely(sources)
        guard !files.isEmpty else { return rule }

        func remap(_ element: Any) -> Any {
            guard let text = JSONX.strValue(element) else { return element }
            let name: String
            let category: String
            if text.hasPrefix("geosite:") {
                name = "geosite.dat"
                category = String(text.dropFirst("geosite:".count))
            } else if text.hasPrefix("geoip:") {
                name = "geoip.dat"
                category = String(text.dropFirst("geoip:".count))
            } else if text.hasPrefix("ext:") {
                let rest = String(text.dropFirst("ext:".count))
                name = rest.substringBefore(":")
                category = text.substringAfter("ext:\(name):")
            } else {
                return element
            }
            guard let url = files[name] else { return element }
            return "ext:\(filenameFor(url)):\(category)" as NSString
        }

        var result = rule
        for key in ["domain", "ip", "source"] {
            guard let value = result[key] else { continue }
            if let array = value as? [Any] {
                result[key] = array.map(remap)
            } else {
                result[key] = remap(value)
            }
        }
        return result
    }
}
