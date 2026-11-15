import SwiftUI
import NetworkExtension
import Combine
import ChumpyCore

/// Root app state: owns the VPN profile manager, the tunnel status and the
/// profile store.
@MainActor
final class AppState: ObservableObject {

    enum AppStateError: LocalizedError {
        case noProfile

        var errorDescription: String? {
            switch self {
            case .noProfile:
                return String(localized: "error.noProfile", bundle: .main)
            }
        }
    }

    @Published private(set) var status: NEVPNStatus = .invalid
    @Published private(set) var connectedDate: Date?
    @Published private(set) var isProcessing = true
    @Published var lastError: String?

    /// The profile/subscription store the servers screen reads and the
    /// connect flow resolves against.
    let store = ProfileStore()

    private var manager: NETunnelProviderManager?
    private var cancellables = Set<AnyCancellable>()

    init() {
        Task(priority: .userInitiated) {
            await reload()
            isProcessing = false
        }
    }

    // MARK: - Manager plumbing (ported from the Mango reference client)

    func reload() async {
        cancellables.removeAll()
        manager = await Self.loadTunnelManager()

        NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshStatus()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .NEVPNConfigurationChange, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    self?.manager = await Self.loadTunnelManager()
                    self?.refreshStatus()
                }
            }
            .store(in: &cancellables)

        refreshStatus()
    }

    private func refreshStatus() {
        status = manager?.connection.status ?? .invalid
        connectedDate = manager?.connection.connectedDate
    }

    /// Installs the VPN profile (called on first connect).
    func saveToPreferences() async throws {
        let manager = NETunnelProviderManager()
        manager.localizedDescription = "Chumpy"
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = ChumpyConstant.tunnelBundleID
        configuration.serverAddress = "Chumpy"
        configuration.providerConfiguration = [:]
        configuration.excludeLocalNetworks = true
        manager.protocolConfiguration = configuration
        manager.isEnabled = true
        try await manager.saveToPreferences()
        self.manager = manager
        refreshStatus()
    }

    // MARK: - Connect / disconnect

    /// Selects a server: persists the choice and, if the tunnel is up,
    /// reloads the running core with the new profile in place — the interface
    /// stays, the session does not drop. Ported from the Android client's
    /// `MainViewModel.selectProfile`.
    func selectProfile(id: String) async {
        store.selectProfile(id: id)
        if status == .connected || status == .connecting || status == .reasserting {
            await connect()
        }
    }

    func toggle() async {
        switch status {
        case .connected, .connecting, .reasserting:
            stop()
        default:
            await connect()
        }
    }

    func connect() async {
        do {
            lastError = nil
            // Resolve the profile and build the config the tunnel will run —
            // the tunnel reads it fresh out of the shared defaults when it
            // starts. Ported from the Android client's
            // `MainViewModel.applyConfigAndConnect`.
            guard let profile = store.selectedProfile() else {
                throw AppStateError.noProfile
            }
            let members = store.resolvedMembers(for: profile)
            let settings = ConnectionStore.current()
            let config = try XrayConfigBuilder.buildFull(
                profile: profile,
                mode: settings.routingMode,
                members: members,
                testURL: settings.testURL
            )
            let defaults = ChumpyConstant.sharedDefaults
            defaults.set(config, forKey: ChumpyConstant.Keys.tunnelConfigJSON)
            defaults.set(
                profile.remarks.isEmpty ? profile.server : profile.remarks,
                forKey: ChumpyConstant.Keys.tunnelProfileName
            )

            if manager == nil {
                try await saveToPreferences()
                // give the system a moment to register the new profile
                try await Task.sleep(nanoseconds: 250_000_000)
                manager = await Self.loadTunnelManager() ?? manager
            }
            guard let manager else { return }
            if !manager.isEnabled {
                manager.isEnabled = true
                try await manager.saveToPreferences()
            }
            ChumpyConstant.sharedDefaults.set(
                Date().timeIntervalSince1970,
                forKey: ChumpyConstant.Keys.connectedAt
            )
            try manager.connection.startVPNTunnel()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        manager?.connection.stopVPNTunnel()
    }

    /// Removes the VPN profile entirely.
    func removeFromPreferences() async throws {
        guard let manager else { return }
        try await manager.removeFromPreferences()
        self.manager = nil
        refreshStatus()
    }

    private static func loadTunnelManager() async -> NETunnelProviderManager? {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        guard
            let match = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == ChumpyConstant.tunnelBundleID
            })
        else { return nil }
        try? await match.loadFromPreferences()
        return match
    }
}
