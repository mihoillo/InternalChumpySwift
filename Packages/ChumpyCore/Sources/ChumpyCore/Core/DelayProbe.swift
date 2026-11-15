import Foundation

/// A single delay measurement with the panel-blocking fallback: the default
/// test URL is Google's; when it fails with a network-ish error the probe
/// retries once against Cloudflare's. Ported from the Android client's
/// `DelayProbe`; the measuring core itself is injected, so this is testable
/// anywhere.
public enum DelayProbe {

    /// The fallback when the default test URL is unreachable — panels block
    /// Google harder than they block Cloudflare.
    public static let backupURL = "https://cp.cloudflare.com/generate_204"

    /// Measures the delay of `url` through `probe`. Throws when the
    /// measurement fails and no fallback applies.
    public static func measure(
        _ url: String,
        probe: (String) throws -> Int64
    ) throws -> Int64 {
        do {
            return try probe(url)
        } catch {
            let networkFailure = isNetworkFailure(error)
            if url != XrayConfigBuilder.defaultTestURL || !networkFailure { throw error }
            return try probe(backupURL)
        }
    }

    /// Whether the failure looks like the network's own doing rather than
    /// the server's — the only failures worth a retry against the backup URL.
    /// The cause chain is walked like the Kotlin original; the messages come
    /// from the Go HTTP stack the measuring fetch runs on.
    static func isNetworkFailure(_ error: Error) -> Bool {
        var current: Error? = error
        var depth = 0
        while let failure = current, depth < 8 {
            let message = (failure as? LocalizedError)?.errorDescription
                ?? failure.localizedDescription
            let lowered = message.lowercased()
            if networkFailureKeywords.contains(where: lowered.contains) {
                return true
            }
            current = (failure as NSError).userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return false
    }

    /// The Kotlin original's list, plus the Swift-native "timed out" —
    /// URLError's wording for the same class of failure.
    private static let networkFailureKeywords = [
        "tls handshake timeout",
        "i/o timeout",
        "connection reset",
        "no such host",
        "network is unreachable",
        "context deadline exceeded",
        "timed out",
    ]
}
