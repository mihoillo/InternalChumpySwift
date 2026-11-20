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
    /// Whether a real-ping sweep over the list is running.
    @Published private(set) var isPinging = false
    /// How many standalone configs wait outside any subscription.
    @Published private(set) var manualProfileCount = 0
    /// How many rows stand concealed behind the group's reveal chip.
    @Published private(set) var concealedCount = 0
    /// The list's own standing order; the header's chip picks it.
    @Published private(set) var sort: ServersSort = .default
    /// The week's daily traffic totals — the quota runway math's own
    /// pace source (the subscription card's bar). Ported from the
    /// Android client's weekly traffic feed.
    @Published private(set) var week: [DailyTraffic] = []
    @Published var error: String?

    /// Whether the concealed rows stand in the list — the reveal mode's
    /// own flag; the view toggles it with the header's chip.
    var includeConcealed = false

    /// Whether a fetch should ride the running core's SOCKS inbound; the view
    /// binds it to the tunnel status on appear.
    var tunnelUp: () -> Bool = { false }

    private let store = ProfileStore()
    private let trafficStore = DailyTrafficStore()
    private lazy var fetcher = SubscriptionFetcher(
        tunnelUp: { [weak self] in self?.tunnelUp() ?? false }
    )

    /// The running sweep's generation; a stale one stops mid-flight.
    private var pingGeneration = 0

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
        let groupRows = store.profiles(ofSubscription: groupID)
        concealedCount = groupRows
            .filter { !$0.hidden && $0.concealed }.count
        // The pinned rows keep the top whatever the order says; the mode's
        // own key orders what stands above the pins' floor. Ported from the
        // Android client's `ServersSort.comparator()`.
        sort = settings.serversSort
        profiles = groupRows
            .filter { !$0.hidden && (includeConcealed || !$0.concealed) }
            .sorted { sort.isOrdered($0, before: $1) }
        week = trafficStore.readWeek()
        error = nil

        // The Android client's `observeProfiles()`: a list that landed
        // with rows never measured answers with its own sweep over just
        // them — the "servers ping themselves" behavior. Every answer
        // marks its row tested, so the sweep never re-arms itself; while
        // one is already in flight the extra call folds away on the flag.
        if profiles.contains(where: { $0.type != .balancer && $0.lastTestAt == nil }) {
            Task { await pingServers(onlyUntested: true) }
        }
    }

    /// The header's sort chip pick: the standing mode trades for the chosen
    /// one and the change rides the persisted settings.
    func setSort(_ mode: ServersSort) {
        guard mode != sort else { return }
        ConnectionStore.update { $0.serversSort = mode }
        reload()
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
            SubscriptionAutoUpdate.schedule()
            onDone(nil)
        } catch {
            self.error = error.localizedDescription
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
            self.error = error.localizedDescription
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
            SubscriptionAutoUpdate.schedule()
        } catch {
            store.markSubscriptionUpdateFailed(id: id, message: error.localizedDescription)
            reload()
            // After the reload — it clears the banner; the card keeps the message.
            self.error = error.localizedDescription
        }
    }

    /// The per-subscription auto-update toggle; the background schedule
    /// re-arms itself with the new set of due dates.
    func setSubscriptionAutoUpdate(id: String, enabled: Bool) {
        store.setSubscriptionAutoUpdate(id: id, enabled: enabled)
        reload()
        SubscriptionAutoUpdate.schedule()
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

    // MARK: - Row actions

    /// Pins or unpins a row — the pinned rows keep the top.
    func togglePinned(_ profile: Profile) {
        store.setProfilePinned(id: profile.id, pinned: !profile.pinned)
        reload()
    }

    /// Hides a row in the list or stands it back — the group's reveal chip
    /// is its way back. Ported from the Android client's row menu.
    func setConcealed(_ profile: Profile, concealed: Bool) {
        store.setProfileConcealed(id: profile.id, concealed: concealed)
        reload()
    }

    /// The reveal mode's own switch: the concealed rows stand in the list
    /// (dimmed, out of play) or fold away behind the chip again.
    func setRevealConcealed(_ on: Bool) {
        includeConcealed = on
        reload()
    }

    /// One row's own test — a single measurement core, its chip answering
    /// with its own number. Ported from the Android client's row menu
    /// "test" path.
    func pingOne(_ profile: Profile) async {
        guard profile.type != .balancer else { return }
        let delay = DelayTester.measure(
            profile: profile, testURL: ConnectionStore.current().testURL
        )
        store.setProfileDelays([(profile.id, delay)], testedAt: Date())
        reloadPreservingSweepState()
    }

    // MARK: - Real pings

    /// A real-ping sweep over the current list, one measurement core per
    /// profile, a handful at a time. Pull-to-refresh on the servers screen is
    /// this (`onlyUntested = false`); every profile's chip answers with its
    /// own number — or clears, when the server is unreachable. The automatic
    /// pass saves `onlyUntested = true` for rows never measured yet.
    /// Ported from the Android client's `MainViewModel.startServerSweep`.
    func pingServers(onlyUntested: Bool = false) async {
        if isPinging { return }
        let targets = profiles.filter {
            $0.type != .balancer && (!onlyUntested || $0.lastTestAt == nil)
        }
        guard !targets.isEmpty else { return }

        pingGeneration += 1
        let generation = pingGeneration
        isPinging = true
        defer {
            if generation == pingGeneration { isPinging = false }
        }

        // A handful of measurement cores at a time, the next queued profile
        // filling each finishing worker's slot — the Android sweep's own
        // pool, four workers instead of ten (the cores share this process).
        let testURL = ConnectionStore.current().testURL
        var batch: [(id: String, delay: Int64?)] = []

        await withTaskGroup(of: (Profile, Int64?).self) { group in
            var iterator = targets.makeIterator()
            let workerCount = min((targets.count - 1) / 10 + 1, 4)
            for _ in 0..<workerCount {
                guard let next = iterator.next() else { break }
                group.addTask { (next, DelayTester.measure(profile: next, testURL: testURL)) }
            }
            for await (profile, delay) in group {
                guard generation == pingGeneration, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                batch.append((profile.id, delay))
                if batch.count >= 5 {
                    store.setProfileDelays(batch, testedAt: Date())
                    batch.removeAll()
                    reloadPreservingSweepState()
                }
                if let next = iterator.next() {
                    group.addTask { (next, DelayTester.measure(profile: next, testURL: testURL)) }
                }
            }
        }
        if !batch.isEmpty, generation == pingGeneration {
            store.setProfileDelays(batch, testedAt: Date())
        }
        if generation == pingGeneration {
            reloadPreservingSweepState()
        }
    }

    /// The sweep's own refresh — `reload` clears the banner and re-reads the
    /// list; the pinging flag and the generation stand.
    private func reloadPreservingSweepState() {
        let wasPinging = isPinging
        reload()
        isPinging = wasPinging
    }
}
