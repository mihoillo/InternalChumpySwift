import Foundation
import CFNetwork
import Compression

/// Fetches a subscription body with an overall deadline. When the tunnel is
/// up the request goes through the running core's loopback SOCKS inbound —
/// this is the way a blocked panel stays reachable, and the reason the config
/// always listens on it. Ported from the Android client's
/// `SubscriptionFetcher`; URLSession plays OkHttp's role.
public final class SubscriptionFetcher {

    /// A deliberately chatty client UA: panels key their response format off
    /// it. The v2rayNG keyword buys the generic link list, the plain name the
    /// raw-config body — both parsers handle those; sing-box/clash keywords
    /// would be answered with Clash YAML or sing-box JSON, so they stay out.
    public static let userAgent = "Chumpy/1.0 (iOS) v2rayNG/1.10"

    /// Panels that serve anything larger are doing something else; do not OOM the app.
    public static let maxBodyBytes = 8 * 1024 * 1024

    public struct FetchResult {
        public let body: String
        public let metadata: SubscriptionMetadata
    }

    public enum FetchError: Error, LocalizedError {
        case badURL
        case http(Int)
        case emptyBody
        case tooLarge

        public var errorDescription: String? {
            switch self {
            case .badURL: return "Not a valid URL"
            case .http(let code): return "HTTP \(code)"
            case .emptyBody: return "Empty subscription body"
            case .tooLarge: return "Subscription body too large"
            }
        }
    }

    /// Whether the fetch should ride the running core's loopback SOCKS
    /// inbound; read at fetch time, so a tunnel that just came up is live on
    /// the very next fetch.
    public var tunnelUp: () -> Bool

    public init(tunnelUp: @escaping () -> Bool = { false }) {
        self.tunnelUp = tunnelUp
    }

    // MARK: - Fetch

    /// Fetches a body with its panel metadata; throws `FetchError` with a
    /// readable message on failure.
    public func fetch(_ rawURL: String) async throws -> FetchResult {
        let url = try Self.validatedURL(rawURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await Self.run(request, tunnelUp: tunnelUp())

        guard (200..<300).contains(response.statusCode) else {
            throw FetchError.http(response.statusCode)
        }
        guard !data.isEmpty else { throw FetchError.emptyBody }

        let body = String(data: Self.ungzipped(data), encoding: .utf8) ?? ""
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FetchError.emptyBody }

        let metadata = SubscriptionHeaders.parse(allHeaderFields: response.allHeaderFields)
        return FetchResult(body: body, metadata: metadata)
    }

    /// Some panels answer a subscription URL with a single URL line — a
    /// nested subscription. One level of expansion, Hiddify-style, covers the
    /// panels that do it. Ported from the Android client's
    /// `fetchWithNestedExpansion`.
    public func fetchWithNestedExpansion(_ url: String) async throws -> FetchResult {
        let first = try await fetch(url)
        guard let nested = SubscriptionParser.isNestedSubscriptionURL(first.body),
              nested != url
        else { return first }
        let second = try await fetch(nested)
        // The nested response is the real one: its sources override the outer's per key.
        var metadata = second.metadata
        metadata.geodataSources = GeodataSources.merge(
            first.metadata.geodataSources, second.metadata.geodataSources
        )
        return FetchResult(body: second.body, metadata: metadata)
    }

    // MARK: - URL helpers

    /// A subscription URL without a scheme means https; hosts serving plain
    /// http spell it out themselves.
    public static func normalizeURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    /// The link host of a subscription URL — the fallback display name.
    public static func hostName(of rawURL: String) -> String {
        guard let components = URLComponents(string: normalizeURL(rawURL)),
              let host = components.host, !host.isEmpty
        else { return rawURL }
        return host
    }

    private static func validatedURL(_ raw: String) throws -> URL {
        guard let url = URL(string: normalizeURL(raw)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { throw FetchError.badURL }
        return url
    }

    // MARK: - Transport

    /// The completion-based API wrapped for the delegate-free control the
    /// async `data(for:)` does not give (it throws on non-2xx before the
    /// status code can be read).
    private static func run(
        _ request: URLRequest, tunnelUp: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: sessionConfiguration(tunnelUp: tunnelUp))
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    continuation.resume(throwing: FetchError.badURL)
                    return
                }
                let bytes = data ?? Data()
                if bytes.count > maxBodyBytes {
                    continuation.resume(throwing: FetchError.tooLarge)
                    return
                }
                continuation.resume(returning: (bytes, response))
            }
            task.resume()
        }
    }

    private static func sessionConfiguration(tunnelUp: Bool) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        if tunnelUp {
            // Through the running core's loopback SOCKS inbound.
            config.connectionProxyDictionary = [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFStreamPropertySOCKSProxyHostName as String: "127.0.0.1",
                kCFStreamPropertySOCKSProxyPort as String: XrayConfigBuilder.localSocksPort,
            ]
        }
        return config
    }

    /// URLSession decompresses the gzip it asked for; a server that gzips
    /// unasked rides through raw — the magic bytes tell those apart.
    private static func ungzipped(_ data: Data) -> Data {
        guard data.count >= 2, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B
        else { return data }
        return gunzip(data) ?? data
    }

    /// Minimal gzip decode: header walk, raw deflate payload, ignored trailer.
    private static func gunzip(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { // FEXTRA
            guard offset + 2 <= bytes.count else { return nil }
            let extra = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + extra
        }
        if flags & 0x08 != 0 { // FNAME
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 { // FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { // FHCRC
            offset += 2
        }
        guard offset < bytes.count - 8 else { return nil }
        let payload = bytes[offset..<(bytes.count - 8)]
        return inflate(Data(payload))
    }

    /// Raw DEFLATE via the Compression framework.
    private static func inflate(_ data: Data) -> Data? {
        let size = 4 * 1024 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let source = buffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_decode_buffer(
                destination, size,
                source, buffer.count,
                nil, COMPRESSION_ZLIB
            )
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }
}
