import Foundation

/// Connection preferences — the selected subscription and profile, the routing
/// mode and the delay test URL. Kept apart from the interface's own settings
/// the same way the connection screens are apart from the interface ones.
/// Ported from the Android client's `ConnectionStore`; the shared UserDefaults
/// suite plays the role Android's snapshot file played (the tunnel reads the
/// same values the app wrote, without a stale per-process cache).
public struct ConnectionSettings: Equatable {
    /// The subscription whose servers the servers screen shows; nil until one exists.
    public var selectedSubscriptionID: String?
    /// The profile a connect uses; restored across restarts.
    public var selectedProfileID: String?
    public var routingMode: RoutingMode
    /// The URL real delay measurements fetch through the tested outbound.
    public var testURL: String

    public init(
        selectedSubscriptionID: String? = nil,
        selectedProfileID: String? = nil,
        routingMode: RoutingMode = .global,
        testURL: String = XrayConfigBuilder.defaultTestURL
    ) {
        self.selectedSubscriptionID = selectedSubscriptionID
        self.selectedProfileID = selectedProfileID
        self.routingMode = routingMode
        self.testURL = testURL
    }
}

public enum ConnectionStore {

    private static let key = "chumpy.connection.settings"

    /// The settings as last written; defaults when never written.
    public static func current(defaults: UserDefaults = ChumpyConstant.sharedDefaults) -> ConnectionSettings {
        guard let data = defaults.data(forKey: key) else { return ConnectionSettings() }
        guard let settings = try? JSONDecoder().decode(SettingsSnapshot.self, from: data) else {
            return ConnectionSettings()
        }
        return ConnectionSettings(
            selectedSubscriptionID: settings.selectedSubscriptionID,
            selectedProfileID: settings.selectedProfileID,
            routingMode: settings.routingMode,
            testURL: settings.testURL.isEmpty ? XrayConfigBuilder.defaultTestURL : settings.testURL
        )
    }

    public static func update(
        _ settings: ConnectionSettings,
        defaults: UserDefaults = ChumpyConstant.sharedDefaults
    ) {
        let snapshot = SettingsSnapshot(
            selectedSubscriptionID: settings.selectedSubscriptionID,
            selectedProfileID: settings.selectedProfileID,
            routingMode: settings.routingMode,
            testURL: settings.testURL
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// Applies a transform to the current settings and persists the result.
    @discardableResult
    public static func update(
        defaults: UserDefaults = ChumpyConstant.sharedDefaults,
        _ transform: (ConnectionSettings) -> ConnectionSettings
    ) -> ConnectionSettings {
        let updated = transform(current(defaults: defaults))
        update(updated, defaults: defaults)
        return updated
    }

    private struct SettingsSnapshot: Codable {
        var selectedSubscriptionID: String?
        var selectedProfileID: String?
        var routingMode: RoutingMode
        var testURL: String
    }
}
