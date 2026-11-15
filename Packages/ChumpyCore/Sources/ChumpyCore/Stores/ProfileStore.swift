import Foundation

/// The profile and subscription store: JSON files in the shared App Group
/// container, one row per profile. Plays the role the Android client's Room
/// database played — the servers screen reads it, the connect flow resolves
/// against it (a balancer's members live here even when the list hides them).
///
/// All access is serialized on the store's own queue; reads are cheap, writes
/// rewrite the whole file (the store is small — a subscription's worth of rows).
public final class ProfileStore {

    private let directory: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "slop.miho.chumpy.swift.profilestore")

    public enum StoreError: Error, LocalizedError {
        case nothingRecognizable

        public var errorDescription: String? {
            switch self {
            case .nothingRecognizable:
                return "No recognizable server link found"
            }
        }
    }

    public init(
        directory: URL = ChumpyConstant.storeDir,
        defaults: UserDefaults = ChumpyConstant.sharedDefaults
    ) {
        self.directory = directory
        self.defaults = defaults
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    // MARK: - Profiles

    private var profilesFile: URL { directory.appendingPathComponent("profiles.json") }
    private var subscriptionsFile: URL { directory.appendingPathComponent("subscriptions.json") }

    /// Every stored profile, in store order.
    public func profiles() -> [Profile] {
        queue.sync { read(profilesFile) }
    }

    /// The profiles the servers list shows: neither hidden nor concealed.
    public func visibleProfiles() -> [Profile] {
        queue.sync { read(profilesFile).filter { !$0.hidden && !$0.concealed } }
    }

    public func saveProfiles(_ profiles: [Profile]) {
        queue.sync { write(profiles, to: profilesFile) }
    }

    public func profile(byID id: String) -> Profile? {
        queue.sync { read(profilesFile).first { $0.id == id } }
    }

    /// The profiles of one subscription; nil means the standalone (manual) group.
    public func profiles(ofSubscription subscriptionID: String?) -> [Profile] {
        queue.sync {
            read(profilesFile).filter { $0.subscriptionID == subscriptionID }
        }
    }

    // MARK: - Subscriptions

    public func subscriptions() -> [Subscription] {
        queue.sync { read(subscriptionsFile) }
    }

    public func saveSubscriptions(_ subscriptions: [Subscription]) {
        queue.sync { write(subscriptions, to: subscriptionsFile) }
    }

    public func subscription(byID id: String) -> Subscription? {
        queue.sync { read(subscriptionsFile).first { $0.id == id } }
    }

    // MARK: - Selection

    /// The profile a connect uses: the selection when it still resolves, the
    /// first visible profile otherwise.
    public func selectedProfile() -> Profile? {
        let settings = ConnectionStore.current(defaults: defaults)
        let visible = visibleProfiles()
        if let id = settings.selectedProfileID,
           let match = visible.first(where: { $0.id == id }) {
            return match
        }
        return visible.first
    }

    /// Selects a server: persists the choice and marks the row as just used.
    public func selectProfile(id: String) {
        ConnectionStore.update(defaults: defaults) { $0.selectedProfileID = id }
        queue.sync {
            var profiles = read(profilesFile)
            guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
            profiles[index].lastUsedAt = Date()
            write(profiles, to: profilesFile)
        }
    }

    // MARK: - Balancer members

    /// A balancer's members, resolved against the store, not the screen's
    /// list — the screen hides the members, the store keeps them: linkKeys
    /// from the column, rows from the subscription. A balancer whose members
    /// have all fallen away degrades to the whole subscription — still a
    /// pick, just a wider one. Ported from the Android client's
    /// `MainViewModel.applyConfigAndConnect`.
    public func resolvedMembers(for profile: Profile) -> [Profile] {
        guard profile.type == .balancer else { return [] }
        let keys = Set(profile.balancerMemberKeys)
        let rows = profiles(ofSubscription: profile.subscriptionID)
        let resolved = rows.filter { $0.type != .balancer && keys.contains($0.linkKey) }
        return resolved.isEmpty ? rows.filter { $0.type != .balancer } : resolved
    }

    // MARK: - Manual import

    /// Manual import: one or more share links (one per line), a WireGuard
    /// .conf body, or a whole raw subscription body — whose parsed profiles
    /// become the standalone group's rows. Returns the number of profiles
    /// actually stored — duplicates are skipped. Ported from the Android
    /// client's `SubscriptionRepository.addManualProfiles`; like the Room
    /// original, only the standalone group's rows are touched — a draft whose
    /// linkKey a subscription row already owns still lands as a fresh manual
    /// row.
    @discardableResult
    public func addManualProfiles(_ text: String) throws -> Int {
        let drafts: [Profile]
        if text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().hasPrefix("[interface]") {
            drafts = [LinkParsers.parseWireguardConf(text)].compactMap { $0 }
        } else {
            drafts = SubscriptionParser.parse(text)
        }
        guard !drafts.isEmpty else { throw StoreError.nothingRecognizable }

        return try queue.sync {
            let all = read(profilesFile)
            let old = all.filter { $0.subscriptionID == nil }
            var keyed: [String: Profile] = [:]
            for draft in drafts {
                keyed[draft.computeLinkKey()] = draft
            }
            let existing = Set(old.map(\.linkKey))
            let fresh = keyed.filter { !existing.contains($0.key) }.values
            var changed = 0

            var updated = old.map { row -> Profile in
                guard let draft = keyed[row.linkKey] else { return row }
                if row.type == .balancer {
                    var copy = row
                    copy.balancerMembers = draft.balancerMembers
                    copy.routingRules = draft.routingRules
                    copy.geodataSources = draft.geodataSources
                    if copy != row { changed += 1 }
                    return copy
                }
                if row.hidden && !draft.hidden {
                    var copy = row
                    copy.hidden = false
                    copy.remarks = draft.remarks
                    copy.sourceLink = draft.sourceLink
                    copy.routingRules = draft.routingRules
                    copy.geodataSources = draft.geodataSources
                    changed += 1
                    return copy
                }
                if row.routingRules != draft.routingRules
                    || row.geodataSources != draft.geodataSources {
                    var copy = row
                    copy.routingRules = draft.routingRules
                    copy.geodataSources = draft.geodataSources
                    changed += 1
                    return copy
                }
                return row
            }

            if !fresh.isEmpty || changed > 0 {
                let nextOrder = (old.map(\.order).max() ?? -1) + 1
                var stampedFresh: [Profile] = []
                for (offset, draft) in fresh.enumerated() {
                    var row = draft
                    row.id = UUID().uuidString
                    row.subscriptionID = nil
                    row.order = nextOrder + offset
                    row.linkKey = draft.computeLinkKey()
                    stampedFresh.append(row)
                }
                updated.append(contentsOf: stampedFresh)
                // The balancer's hidden members stay: the column still names them.
                let referenced = Set(
                    updated.filter { $0.type == .balancer }
                        .flatMap { $0.balancerMemberKeys }
                )
                let combined = updated.filter { !$0.hidden || referenced.contains($0.linkKey) }
                let others = all.filter { $0.subscriptionID != nil }
                write(combined + others, to: profilesFile)
            }
            return fresh.count + changed
        }
    }

    /// Deletes one standalone profile. A hidden balancer member the row backs
    /// stays (hidden) — the column still names its linkKey.
    public func deleteManualProfile(id: String) {
        queue.sync {
            let all = read(profilesFile)
            let old = all.filter { $0.subscriptionID == nil }
            let remaining = old.filter { $0.id != id }
            let referenced = Set(
                remaining.filter { $0.type == .balancer }
                    .flatMap { $0.balancerMemberKeys }
            )
            var combined = remaining
            for row in old where row.id == id && referenced.contains(row.linkKey) {
                var copy = row
                copy.hidden = true
                combined.append(copy)
            }
            combined = combined.filter { !$0.hidden || referenced.contains($0.linkKey) }
            let others = all.filter { $0.subscriptionID != nil }
            write(combined + others, to: profilesFile)
        }
    }

    /// Drops every standalone profile at once — the group's own delete.
    public func deleteManualProfiles() {
        queue.sync {
            let old = read(profilesFile)
            write(old.filter { $0.subscriptionID != nil }, to: profilesFile)
        }
    }

    // MARK: - Storage

    private func read<T: Decodable>(_ file: URL) -> [T] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([T].self, from: data)) ?? []
    }

    private func write<T: Encodable>(_ rows: [T], to file: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(rows) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
