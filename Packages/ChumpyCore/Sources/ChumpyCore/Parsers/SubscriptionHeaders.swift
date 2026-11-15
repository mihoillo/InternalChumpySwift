import Foundation

/// The metadata panels attach to a subscription response — Hiddify's dialect,
/// which is the de-facto standard. Ported from the Android client's
/// `SubscriptionHeaders`.
public struct SubscriptionMetadata: Codable, Equatable {
    public var title: String? = nil
    public var uploadBytes: Int64 = 0
    public var downloadBytes: Int64 = 0
    public var totalBytes: Int64 = 0
    public var expireEpochSeconds: Int64 = 0
    public var updateIntervalHours: Int? = nil
    public var geodataSources: String = ""
    /// The panel's `profile-logo`: a URL the card's avatar is downloaded from.
    public var logoURL: String? = nil

    public init() {}
}

public enum SubscriptionHeaders {

    /// Parses the interesting headers out of a response's header map.
    public static func parse(_ headers: [String: [String]]) -> SubscriptionMetadata {
        func first(_ name: String) -> String? {
            for (key, values) in headers {
                if key.caseInsensitiveCompare(name) == .orderedSame {
                    return values.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                }
            }
            return nil
        }

        var meta = SubscriptionMetadata()
        if let userinfo = first("subscription-userinfo") {
            let counters = parseUserinfo(userinfo)
            meta.uploadBytes = counters.uploadBytes
            meta.downloadBytes = counters.downloadBytes
            meta.totalBytes = counters.totalBytes
            meta.expireEpochSeconds = counters.expireEpochSeconds
        }
        if let title = first("profile-title").flatMap(parseTitle) {
            meta.title = title
        }
        if let disposition = first("content-disposition"), meta.title == nil {
            meta.title = parseFilename(disposition)
        }
        if let interval = first("profile-update-interval").flatMap(parseUpdateInterval) {
            meta.updateIntervalHours = interval
        }
        if let routing = first("routing") {
            meta.geodataSources = GeodataSources.fromHappHeader(routing)
        }
        if let logo = first("profile-logo") {
            meta.logoURL = logo
        }
        return meta
    }

    /// Convenience for `HTTPURLResponse.allHeaderFields` (`[AnyHashable: Any]`).
    public static func parse(allHeaderFields: [AnyHashable: Any]) -> SubscriptionMetadata {
        var headers: [String: [String]] = [:]
        for (key, value) in allHeaderFields {
            guard let name = key as? String else { continue }
            if let string = value as? String {
                headers[name] = [string]
            } else if let strings = value as? [String] {
                headers[name] = strings
            }
        }
        return parse(headers)
    }

    /// "upload=123; download=456; total=789; expire=1700000000" → its four numbers.
    public static func parseUserinfo(_ value: String) -> SubscriptionMetadata {
        var upload: Int64 = 0
        var download: Int64 = 0
        var total: Int64 = 0
        var expire: Int64 = 0
        for part in value.split(separator: ";") {
            guard let eqIdx = part.firstIndex(of: "="), eqIdx > part.startIndex else { continue }
            let key = String(part[..<eqIdx]).trimmingCharacters(in: .whitespaces).lowercased()
            let numberStr = String(part[part.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
            guard let number = Int64(numberStr) else { continue }
            switch key {
            case "upload": upload = number
            case "download": download = number
            case "total": total = number
            case "expire": expire = number
            default: break
            }
        }
        var meta = SubscriptionMetadata()
        meta.uploadBytes = upload
        meta.downloadBytes = download
        meta.totalBytes = total
        meta.expireEpochSeconds = expire
        return meta
    }

    /// Plain text, or "base64:…" encoded; both are in the wild.
    public static func parseTitle(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.lowercased().hasPrefix("base64:") {
            guard let decoded = LinkUtils.decodeBase64(trimmed.substringAfter(":")),
                  !decoded.trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return decoded.trimmingCharacters(in: .whitespaces)
        }
        // URLEncoded titles are common too.
        let decoded = LinkUtils.decodeURIComponent(trimmed)
        return decoded.isEmpty ? nil : decoded
    }

    /// "attachment; filename=Name.txt" → "Name".
    public static func parseFilename(_ value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "filename\\*?=\"?([^\";]+)\"?"),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value)
        else { return nil }
        var name = String(value[range]).trimmingCharacters(in: .whitespaces)
        if name.hasSuffix(".txt") { name = String(name.dropLast(".txt".count)) }
        if name.hasSuffix(".list") { name = String(name.dropLast(".list".count)) }
        return name.isEmpty ? nil : name
    }

    /// Hours, as the header carries it.
    public static func parseUpdateInterval(_ value: String) -> Int? {
        let cleaned = value.trimmingCharacters(in: .whitespaces).substringBefore(";")
        guard let hours = Double(cleaned), hours > 0 else { return nil }
        return max(1, Int(hours))
    }
}
