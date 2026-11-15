import SwiftUI
import Combine
import ChumpyCore

/// The servers screen's own state: the subscriptions, the selected group's
/// profiles and the actions over both. Ported from the Android client's
/// `MainViewModel` (the servers half); the store is file-backed, so this
/// instance and `AppState`'s see the same rows.
@MainActor
final class ServersViewModel: ObservableObject {

    @Published private(set) var subscriptions: [SubscriptionEntity] = []
    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var selectedSubscriptionID: String?
    @Published private(set) var selectedProfileID: String?
    @Published private(set) var updatingSubscriptionID: String?
    /// How many standalone configs wait outside any subscription.
    @Published private(set) var manualProfileCount = 0
    @Published var error: String?

    /// Whether a fetch should ride the running core's SOCKS inbound; the view
    /// binds it to the tunnel status on appear.
    var tunnelUp: () -> Bool = { false }

    private let store = ProfileStore()
    private lazy var fetcher = SubscriptionFetcher(
        tunnelUp: { [weak self] in self?.tunnelUp() ?? false }
    )

    /// The standalone group's synthetic card.
    var selectedSubscription: SubscriptionEntity? {
        guard let id = selectedSubscriptionID else { return nil }
        if id == standaloneSubscriptionID {
            return SubscriptionEntity(
                id: standaloneSubscriptionID,
                name: String(localized: "servers.standalone", bundle: .main)
            )
        }
        return subscriptions.first { $0.id == id }
    }

    var isStandaloneSelected: Bool {
        selectedSubscriptionID == standaloneSubscriptionID
    }

    // MARK: - Reading

    func reload() {
        let settings = ConnectionStore.current()
        let allSubs = store.subscriptions().sorted { $0.createdAt < $1.createdAt }
        let manualRows = store.profiles(ofSubscription: nil)
            .filter { !$0.hidden && !$0.concealed }
        manualProfileCount = manualRows.count

        // Deleted while selected: fall back to the first, or to nothing at
        // all. The standalone group keeps its selection only while it has
        // something in it.
        let resolved: String?
        if let stored = settings.selectedSubscriptionID,
           stored == standaloneSubscriptionID && manualProfileCount > 0
           || allSubs.contains(where: { $0.id == stored }) {
            resolved = stored
        } else if let first = allSubs.first {
            resolved = first.id
        } else if manualProfileCount > 0 {
            resolved = standaloneSubscriptionID
        } else {
            resolved = nil
        }

        subscriptions = allSubs
        selectedSubscriptionID = resolved
        selectedProfileID = settings.selectedProfileID
        let groupID = resolved == standaloneSubscriptionID ? nil : resolved
        profiles = store.profiles(ofSubscription: groupID)
            .filter { !$0.hidden && !$0.concealed }
        error = nil
    }

    // MARK: - Selection

    /// Switches the servers screen to another subscription; the profile pick
    /// clears with it.
    func selectSubscription(_ id: String) {
        guard selectedSubscriptionID != id else { return }
        ConnectionStore.update { settings in
            settings.selectedSubscriptionID = id
            settings.selectedProfileID = nil
        }
        reload()
    }

    // MARK: - Adding

    /// Adds a subscription by URL — or, for a paste without a scheme, treats
    /// it as manual profiles.
    func addSubscription(
        url: String, name: String? = nil, onDone: (String?) -> Void = { _ in }
    ) async {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if !lowered.hasPrefix("http://") && !lowered.hasPrefix("https://") {
            addManualProfiles(trimmed, onDone: onDone)
            return
        }
        do {
            let fetched = try await fetcher.fetchWithNestedExpansion(trimmed)
            let sub = try store.addSubscription(
                url: trimmed, name: name, body: fetched.body, metadata: fetched.metadata
            )
            // The group the servers landed in becomes the shown one.
            ConnectionStore.update { $0.selectedSubscriptionID = sub.id }
            reload()
            onDone(nil)
        } catch {
            error = error.localizedDescription
            onDone(error.localizedDescription)
        }
    }

    /// Manual import: a link, a WireGuard .conf body, a raw config, or a list
    /// of links.
    func addManualProfiles(_ text: String, onDone: (String?) -> Void = { _ in }) {
        do {
            let count = try store.addManualProfiles(text)
            if count > 0 {
                ConnectionStore.update { settings in
                    settings.selectedSubscriptionID = standaloneSubscriptionID
                    settings.selectedProfileID = nil
                }
                reload()
                onDone(nil)
            } else {
                let message = String(localized: "servers.import.nothingNew", bundle: .main)
                error = message
                onDone(message)
            }
        } catch {
            error = error.localizedDescription
            onDone(error.localizedDescription)
        }
    }

    // MARK: - Refresh / delete

    /// Refreshes a subscription; the standalone group has no URL to
    /// re-fetch — its rows are only ever the user's own pastes.
    func updateSubscription(_ id: String) async {
        guard id != standaloneSubscriptionID, updatingSubscriptionID == nil else { return }
        updatingSubscriptionID = id
        defer { updatingSubscriptionID = nil }
        do {
            guard let sub = store.subscription(byID: id) else { return }
            let fetched = try await fetcher.fetchWithNestedExpansion(sub.url)
            try store.updateSubscription(id: id, body: fetched.body, metadata: fetched.metadata)
            reload()
        } catch {
            store.markSubscriptionUpdateFailed(id: id, message: error.localizedDescription)
            reload()
            // After the reload — it clears the banner; the card keeps the message.
            self.error = error.localizedDescription
        }
    }

    /// Deletes a subscription and everything it brought in — or the
    /// standalone group.
    func deleteSubscription(_ id: String) {
        if id == standaloneSubscriptionID {
            store.deleteManualProfiles()
        } else {
            store.deleteSubscription(id: id)
        }
        let settings = ConnectionStore.current()
        if settings.selectedSubscriptionID == id {
            ConnectionStore.update { settings in
                settings.selectedSubscriptionID = nil
                settings.selectedProfileID = nil
            }
        }
        reload()
    }

    /// Deletes one loose config — the pick clears with the row if it pointed
    /// there; the rest of the group stands.
    func deleteManualProfile(_ id: String) {
        store.deleteManualProfile(id: id)
        if ConnectionStore.current().selectedProfileID == id {
            ConnectionStore.update { $0.selectedProfileID = nil }
        }
        reload()
    }
}
