import XCTest
@testable import ChumpyCore

/// Ported from the Android client's `DelayProbeTest` — the fallback semantics:
/// only the default URL's network-ish failures earn a retry against the
/// backup URL.
final class DelayProbeTests: XCTestCase {

    private let defaultURL = XrayConfigBuilder.defaultTestURL

    private func networkError(_ message: String) -> NSError {
        NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    func testSuccessReturnsFirstProbe() throws {
        var seen: [String] = []
        let result = try DelayProbe.measure(defaultURL) { url in
            seen.append(url)
            return 42
        }
        XCTAssertEqual(42, result)
        XCTAssertEqual([defaultURL], seen)
    }

    func testFailureOnNonDefaultURLRethrows() throws {
        var calls = 0
        XCTAssertThrowsError(
            try DelayProbe.measure("https://other.example.com/204") { _ in
                calls += 1
                throw networkError("connection reset")
            }
        )
        XCTAssertEqual(1, calls, "the backup URL is only earned on the default one")
    }

    func testNonNetworkFailureRethrows() throws {
        var calls = 0
        XCTAssertThrowsError(
            try DelayProbe.measure(defaultURL) { _ in
                calls += 1
                throw networkError("tls certificate mismatch")
            }
        )
        XCTAssertEqual(1, calls)
    }

    func testNetworkFailureRetriesBackupURL() throws {
        var seen: [String] = []
        let result = try DelayProbe.measure(defaultURL) { url in
            seen.append(url)
            if url == defaultURL { throw networkError("i/o timeout") }
            return 77
        }
        XCTAssertEqual([defaultURL, DelayProbe.backupURL], seen)
        XCTAssertEqual(77, result)
    }

    func testNetworkFailureOnBackupURLPropagates() throws {
        var calls = 0
        XCTAssertThrowsError(
            try DelayProbe.measure(defaultURL) { _ in
                calls += 1
                throw networkError("no such host")
            }
        )
        XCTAssertEqual(2, calls)
    }

    func testUnderlyingErrorChainIsWalked() throws {
        var calls = 0
        let result = try DelayProbe.measure(defaultURL) { url in
            calls += 1
            if url == defaultURL {
                let root = networkError("connection reset")
                throw NSError(
                    domain: "test", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "wrapped",
                        NSUnderlyingErrorKey: root,
                    ]
                )
            }
            return 88
        }
        XCTAssertEqual(88, result)
        XCTAssertEqual(2, calls, "the wrapped network failure earned the backup retry")
    }

    func testKeywordsRecognized() {
        for message in [
            "TLS handshake timeout",
            "read tcp: i/o timeout",
            "connection reset by peer",
            "dial tcp: no such host",
            "network is unreachable",
            "context deadline exceeded",
            "The request timed out",
        ] {
            XCTAssertTrue(
                DelayProbe.isNetworkFailure(networkError(message)),
                "expected network failure: \(message)"
            )
        }
        XCTAssertFalse(DelayProbe.isNetworkFailure(networkError("bad target")))
        XCTAssertFalse(DelayProbe.isNetworkFailure(networkError("")))
    }
}
