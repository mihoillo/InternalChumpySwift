import Foundation

/// Turns a subscription body into profiles. The body is either a list of share
/// links, one per line, or the same list base64-encoded as a whole; raw Xray
/// configs are `ConfigParser`'s to read. Ported from the Android client's
/// `SubscriptionParser`.
public enum SubscriptionParser {

    /// The parsed profiles, deduplicated, in body order; empty when nothing parsed.
    public static func parse(_ body: String) -> [Profile] {
        let text = decodeBody(body)
        // The raw-config dialect first: a config's own DNS block carries "https://"
        // addresses, which would otherwise read as a link list and swallow the body.
        if let configs = ConfigParser.parse(text) {
            return distinctByLinkKey(configs)
        }
        // Clash YAML next — panels serve it to Clash-flavoured clients.
        if let clash = ClashYamlParser.parse(text) {
            return distinctByLinkKey(clash)
        }
        let profiles = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { LinkParsers.parse(String($0)) }
        // Identical servers repeated in one body collapse to the first occurrence.
        return distinctByLinkKey(profiles)
    }

    /// Whether the whole body is one nested subscription URL rather than links —
    /// a single http(s) line that is not itself a proxy link.
    public static func isNestedSubscriptionURL(_ body: String) -> String? {
        let trimmed = decodeBody(body)
        let nonBlank = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        guard nonBlank.count == 1 else { return nil }
        guard
            trimmed.lowercased().hasPrefix("http://") ||
            trimmed.lowercased().hasPrefix("https://")
        else { return nil }
        return trimmed
    }

    private static func decodeBody(_ body: String) -> String {
        let trimmed = body
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return trimmed
        }
        // Clash YAML announces itself the same way.
        if trimmed.range(of: "(?m)^proxies:", options: .regularExpression) != nil {
            return trimmed
        }
        // Plain link lists announce themselves; base64 bodies don't.
        if trimmed.contains("://") { return trimmed }
        let decoded = LinkUtils.decode(trimmed)
        return decoded.isEmpty ? trimmed : decoded
    }

    private static func distinctByLinkKey(_ profiles: [Profile]) -> [Profile] {
        var seen = Set<String>()
        var result: [Profile] = []
        for profile in profiles {
            let key = profile.computeLinkKey()
            if seen.insert(key).inserted {
                result.append(profile)
            }
        }
        return result
    }
}
