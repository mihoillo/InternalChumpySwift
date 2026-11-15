import Foundation
import ChumpyCore
import SwiftyXrayKit

/// Runs real delay measurements in the app process: a throwaway Xray instance
/// per profile, started from the ping document, fetching the test URL through
/// the config's own loopback SOCKS inbound. Ported from the Android client's
/// `XrayCore.measureOutboundDelay` + `DelayProbe` — there the temp cores ran
/// in the ":core" process, here the app's own.
enum DelayTester {

    /// The overall deadline of one measurement, seconds — the Go HTTP
    /// client's own timeout.
    private static let timeoutSeconds = 10

    /// A single measurement, blocking. Nil when the server is unreachable.
    static func measure(profile: Profile, testURL: String) -> Int64? {
        guard let port = (try? SwiftyXray.getFreePorts(1))?.first else { return nil }
        let config = XrayConfigBuilder.buildPing(profile, socksPort: port)
        let path = ChumpyConstant.configsDir
            .appendingPathComponent("ping_\(UUID().uuidString).json")
        do {
            try FileManager.default.createDirectory(
                at: ChumpyConstant.configsDir, withIntermediateDirectories: true
            )
            try config.write(to: path, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: path) }

            let datDir = ChumpyConstant.dataDir.path
            let proxy = XrayConfigBuilder.pingProxyURL(port: port)
            return try DelayProbe.measure(testURL) { target in
                let raw = try SwiftyXray.ping(
                    datDir: datDir, configPath: path.path,
                    timeout: timeoutSeconds, url: target, proxy: proxy
                )
                // The sentinels ride in `data` alongside the error — the
                // message stands in for the Go stack's own wording.
                if raw >= SwiftyXray.pingDelayTimeout {
                    throw Failure.timeout
                }
                if raw >= SwiftyXray.pingDelayError {
                    throw Failure.unreachable
                }
                return raw
            }
        } catch {
            return nil
        }
    }

    enum Failure: Error, LocalizedError {
        case timeout
        case unreachable

        var errorDescription: String? {
            switch self {
            case .timeout: return "context deadline exceeded"
            case .unreachable: return "connection reset"
            }
        }
    }
}
