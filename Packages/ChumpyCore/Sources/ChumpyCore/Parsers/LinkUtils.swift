import Foundation

/// The string plumbing every link parser needs: base64 in both alphabets,
/// strict RFC 3986 component de/encoding, a small URI parser and IPv6 brackets.
/// Ported from the Android client's `LinkUtils` (originally v2rayNG, Apache-2.0).
public enum LinkUtils {

    // MARK: - Base64

    /// Base64 in the standard and the URL-safe alphabet, without line wraps.
    public static func decodeBase64(_ text: String) -> String? {
        guard let data = decodeBase64Bytes(text) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode, tolerating missing padding and stray whitespace — as bodies often are.
    public static func decode(_ text: String) -> String {
        decodeBase64(text) ?? ""
    }

    public static func encodeBase64(_ text: String, removePadding: Bool = false) -> String {
        var encoded = Data(text.utf8).base64EncodedString()
        if removePadding {
            while encoded.hasSuffix("=") { encoded.removeLast() }
        }
        return encoded
    }

    /// Both alphabets, both padded and stripped: re-pad, try standard, then URL-safe.
    private static func decodeBase64Bytes(_ text: String) -> Data? {
        let trimmed = String(text.filter { !$0.isWhitespace })
        guard !trimmed.isEmpty else { return nil }
        let padded = trimmed + String(repeating: "=", count: (4 - trimmed.count % 4) % 4)
        if let data = Data(base64Encoded: padded) { return data }
        // URL-safe alphabet fallback.
        let url = padded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: url)
    }

    // MARK: - RFC 3986 components

    /// Decode an encodeURIComponent part; '+' stays a literal plus, unlike form decoding.
    public static func decodeURIComponent(_ url: String) -> String {
        url.replacingOccurrences(of: "+", with: "%2B").removingPercentEncoding ?? url
    }

    /// Encode an encodeURIComponent part.
    public static func encodeURIComponent(_ url: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
        )
        return url.addingPercentEncoding(withAllowedCharacters: unreserved) ?? url
    }

    /// The characters URI parsers refuse, percent-encoded away.
    public static func fixIllegalURL(_ str: String) -> String {
        str
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "|", with: "%7C")
    }

    // MARK: - IPv6

    /// Brackets a bare IPv6 address; anything else passes through.
    public static func ipv6Brackets(_ address: String?) -> String {
        guard let address, !address.isEmpty else { return "" }
        if isIPv6Address(address) && !address.contains("[") {
            return "[\(address)]"
        }
        return address
    }

    public static func isIPv6Address(_ address: String) -> Bool {
        address.filter { $0 == ":" }.count >= 2 && !address.hasPrefix("[")
    }

    // MARK: - Ports

    /// Ports from links arrive as anything: "443", 443.0, "443#fragment".
    /// Takes the leading integer and falls back to 0 (unset) when unusable.
    public static func parsePort(_ raw: String?) -> Int {
        let cleaned = (raw?.substringBefore("#") ?? "").trimmingCharacters(in: .whitespaces)
        if let int = Int(cleaned) { return int }
        if let double = Double(cleaned) { return Int(double) }
        return 0
    }
}

// MARK: - URI

/// A minimal RFC 3986 URI, tolerant the way share links are: mirrors the
/// subset of `java.net.URI` the Android parsers rely on (raw query/fragment,
/// raw + decoded userInfo, bracket-stripped host, -1 port when absent).
public struct ParsedURI {
    public let scheme: String
    public let rawUserInfo: String?
    public let host: String?
    public let port: Int
    public let rawQuery: String?
    public let rawFragment: String?

    /// The decoded user info (the whole `user:pass` part before `@`).
    public var userInfo: String? {
        rawUserInfo.map { LinkUtils.decodeURIComponent($0) }
    }

    /// The host without IPv6 brackets.
    public var idnHost: String {
        (host ?? "").replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
    }

    /// Parses `scheme://[userinfo@]host[:port][/path][?query][#fragment]`.
    /// Returns nil when there is no scheme/authority to speak of.
    public static func parse(_ string: String) -> ParsedURI? {
        guard let schemeRange = string.range(of: "://") else { return nil }
        let scheme = String(string[string.startIndex..<schemeRange.lowerBound])
        guard !scheme.isEmpty,
              scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." })
        else { return nil }

        var rest = String(string[schemeRange.upperBound...])

        // fragment
        var rawFragment: String?
        if let hashIdx = rest.firstIndex(of: "#") {
            rawFragment = String(rest[rest.index(after: hashIdx)...])
            rest = String(rest[..<hashIdx])
        }
        // query
        var rawQuery: String?
        if let queryIdx = rest.firstIndex(of: "?") {
            rawQuery = String(rest[rest.index(after: queryIdx)...])
            rest = String(rest[..<queryIdx])
        }
        // authority runs to the first '/'
        var authority = rest
        if let slashIdx = rest.firstIndex(of: "/") {
            authority = String(rest[..<slashIdx])
        }

        // userinfo: up to the LAST '@' (RFC 3986)
        var rawUserInfo: String?
        var hostPort = authority
        if let atIdx = authority.lastIndex(of: "@") {
            rawUserInfo = String(authority[..<atIdx])
            hostPort = String(authority[authority.index(after: atIdx)...])
        }

        // host[:port], bracket-aware for IPv6
        var host: String?
        var port = -1
        if hostPort.hasPrefix("[") {
            guard let closeIdx = hostPort.firstIndex(of: "]") else { return nil }
            host = String(hostPort[..<hostPort.index(after: closeIdx)])
            let after = String(hostPort[hostPort.index(after: closeIdx)...])
            if after.hasPrefix(":") {
                let portStr = String(after.dropFirst())
                guard portStr.allSatisfy({ $0.isNumber }) else { return nil }
                port = Int(portStr) ?? -1
            }
        } else if let colonIdx = hostPort.lastIndex(of: ":") {
            let maybePort = String(hostPort[hostPort.index(after: colonIdx)...])
            let maybeHost = String(hostPort[..<colonIdx])
            if maybePort.allSatisfy({ $0.isNumber }) && !maybePort.isEmpty {
                host = maybeHost
                port = Int(maybePort) ?? -1
            } else {
                host = hostPort
            }
        } else {
            host = hostPort
        }

        guard let host, !host.isEmpty else { return nil }

        return ParsedURI(
            scheme: scheme,
            rawUserInfo: rawUserInfo,
            host: host,
            port: port,
            rawQuery: rawQuery,
            rawFragment: rawFragment
        )
    }

    /// Query parameters, values component-decoded.
    public var queryParams: [String: String] {
        var result: [String: String] = [:]
        for pair in (rawQuery ?? "").split(separator: "&") {
            let pairStr = String(pair)
            guard !pairStr.isEmpty else { continue }
            if let eqIdx = pairStr.firstIndex(of: "=") {
                let key = String(pairStr[..<eqIdx])
                let value = LinkUtils.decodeURIComponent(String(pairStr[pairStr.index(after: eqIdx)...]))
                result[key] = value
            } else {
                result[pairStr] = ""
            }
        }
        return result
    }
}

// MARK: - String helpers (Kotlin stdlib semantics)

extension String {

    /// Kotlin `substringBefore`: everything before the first delimiter,
    /// or the whole string when the delimiter is missing.
    public func substringBefore(_ delimiter: String) -> String {
        guard let range = range(of: delimiter) else { return self }
        return String(self[..<range.lowerBound])
    }

    /// Kotlin `substringAfter`: everything after the first delimiter,
    /// or the whole string when the delimiter is missing.
    public func substringAfter(_ delimiter: String) -> String {
        guard let range = range(of: delimiter) else { return self }
        return String(self[range.upperBound...])
    }

    /// Kotlin `removeSurrounding`.
    public func removeSurrounding(_ prefix: String, _ suffix: String) -> String {
        guard hasPrefix(prefix), hasSuffix(suffix), count >= prefix.count + suffix.count else {
            return self
        }
        return String(dropFirst(prefix.count).dropLast(suffix.count))
    }
}
