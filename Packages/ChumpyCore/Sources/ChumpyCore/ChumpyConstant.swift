import Foundation

/// Shared identifiers, paths and UserDefaults keys used by both the app
/// and the packet tunnel extension. The single source of truth for
/// cross-process state (App Group).
public enum ChumpyConstant {

    /// App Group shared by the app and the tunnel extension.
    public static let appGroupID = "group.slop.miho.chumpy.swift"

    /// Bundle identifier of the packet tunnel extension.
    public static let tunnelBundleID = "slop.miho.chumpy.swift.tunnel"

    /// UserDefaults suite shared with the tunnel extension.
    public static let sharedDefaults: UserDefaults =
        UserDefaults(suiteName: appGroupID) ?? .standard

    /// Root of the shared App Group container.
    public static var appGroupContainer: URL {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) ?? FileManager.default.temporaryDirectory
    }

    /// Directory holding Xray data (geo files etc.).
    public static var dataDir: URL {
        appGroupContainer
            .appendingPathComponent("Library/Application Support/Xray", isDirectory: true)
    }

    /// Directory where the final Xray config is written before start.
    public static var configsDir: URL {
        appGroupContainer
            .appendingPathComponent("Library/Application Support/Xray/configs", isDirectory: true)
    }

    /// Final config handed off to Xray inside the tunnel.
    public static var tunnelConfigPath: URL {
        configsDir.appendingPathComponent("config_final.json")
    }

    /// Directory holding the profile/subscription store files.
    public static var storeDir: URL {
        appGroupContainer
            .appendingPathComponent("Library/Application Support/Store", isDirectory: true)
    }

    public static func ensureDirectories() {
        let fm = FileManager.default
        for dir in [dataDir, configsDir, storeDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Keys used in the shared UserDefaults suite.
    public enum Keys {
        /// Full Xray JSON config for the currently selected profile.
        public static let tunnelConfigJSON = "chumpy.tunnel.configJSON"
        /// Human-readable name of the selected profile (for notifications).
        public static let tunnelProfileName = "chumpy.tunnel.profileName"
        /// Routing mode name, see `RoutingMode`.
        public static let routingMode = "chumpy.connection.routingMode"
        /// Delay-test URL.
        public static let testURL = "chumpy.connection.testURL"
        /// Cumulative transferred bytes since connect (Double).
        public static let statsBytesTotal = "chumpy.tunnel.stats.bytesTotal"
        /// Unix timestamp of the last stats update.
        public static let statsUpdatedAt = "chumpy.tunnel.stats.updatedAt"
        /// Unix timestamp when the tunnel connected (set by the app on start).
        public static let connectedAt = "chumpy.tunnel.connectedAt"
    }
}
