import Foundation

/// Subscription lifecycle: adding, refreshing and deleting, on top of the
/// file store. A refresh replaces the subscription's profile rows wholesale,
/// but profiles whose `linkKey` survives carry their identity — and with it
/// the selection state and the last measured ping — over to the new rows.
/// Ported from the Android client's `SubscriptionRepository` (the fetch-less
/// core; the app layer pairs it with `SubscriptionFetcher`).
extension ProfileStore {

    public enum SubscriptionError: Error, LocalizedError {
        case notFound
        case nothingParsed

        public var errorDescription: String? {
            switch self {
            case .notFound: return "Subscription not found"
            case .nothingParsed: return "No server links found in the response"
            }
        }
    }

    /// Creates a new subscription from a fetched body; the URL is the
    /// identity. The panel's geodata sources ride onto every row.
    @discardableResult
    public func addSubscription(
        url: String,
        name: String? = nil,
        body: String,
        metadata: SubscriptionMetadata
    ) throws -> Subscription {
        let parsed = Self.parsedRows(body: body, metadata: metadata)

        let id = UUID().uuidString
        let now = Date()
        let entity = Subscription(
            id: id,
            name: name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? metadata.title
                ?? SubscriptionFetcher.hostName(of: url),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: now,
            lastUpdateAttempt: now,
            lastUpdateSuccess: now,
            updateIntervalHours: metadata.updateIntervalHours,
            autoUpdate: true,
            uploadBytes: metadata.uploadBytes,
            downloadBytes: metadata.downloadBytes,
            totalBytes: metadata.totalBytes,
            expireEpochSeconds: metadata.expireEpochSeconds
        )
        queue.sync {
            write(read(subscriptionsFile) + [entity], to: subscriptionsFile)
            let all: [Profile] = read(profilesFile)
            write(all + stamped(parsed, subscriptionID: id, old: []), to: profilesFile)
        }
        return entity
    }

    /// Swaps a subscription's profiles in place from a re-fetched body.
    @discardableResult
    public func updateSubscription(
        id: String,
        body: String,
        metadata: SubscriptionMetadata
    ) throws -> Subscription {
        let parsed = Self.parsedRows(body: body, metadata: metadata)

        return try queue.sync {
            let subs: [Subscription] = read(subscriptionsFile)
            guard let index = subs.firstIndex(where: { $0.id == id }) else {
                throw SubscriptionError.notFound
            }
            var entity = subs[index]
            let old: [Profile] = read(profilesFile).filter { $0.subscriptionID == id }

            entity.name = metadata.title ?? entity.name
            entity.lastUpdateAttempt = Date()
            entity.lastUpdateSuccess = Date()
            entity.updateIntervalHours = metadata.updateIntervalHours
            entity.uploadBytes = metadata.uploadBytes
            entity.downloadBytes = metadata.downloadBytes
            entity.totalBytes = metadata.totalBytes
            entity.expireEpochSeconds = metadata.expireEpochSeconds
            entity.lastError = nil

            var updated = subs
            updated[index] = entity
            write(updated, to: subscriptionsFile)
            let others: [Profile] = read(profilesFile).filter { $0.subscriptionID != id }
            write(others + stamped(parsed, subscriptionID: id, old: old), to: profilesFile)
            return entity
        }
    }

    /// The failure lands on the card, not in a toast that is gone in a second.
    public func markSubscriptionUpdateFailed(id: String, message: String) {
        queue.sync {
            var subs: [Subscription] = read(subscriptionsFile)
            guard let index = subs.firstIndex(where: { $0.id == id }) else { return }
            subs[index].lastUpdateAttempt = Date()
            subs[index].lastError = message
            write(subs, to: subscriptionsFile)
        }
    }

    /// Drops a subscription and its profiles wholesale.
    public func deleteSubscription(id: String) {
        queue.sync {
            write(
                read(subscriptionsFile).filter { $0.id != id },
                to: subscriptionsFile
            )
            write(
                read(profilesFile).filter { $0.subscriptionID != id },
                to: profilesFile
            )
        }
    }

    /// The drafts of a fetched body, with the panel's geodata sources merged
    /// onto every row; throws when nothing parses.
    private static func parsedRows(
        body: String, metadata: SubscriptionMetadata
    ) throws -> [Profile] {
        let headerSources = GeodataSources.parseSafely(metadata.geodataSources)
        let parsed = SubscriptionParser.parse(body).map { draft in
            var row = draft
            row.geodataSources = GeodataSources.merge(headerSources, draft.geodataSources)
            return row
        }
        guard !parsed.isEmpty else { throw SubscriptionError.nothingParsed }
        return parsed
    }

    /// Stamps drafts as the subscription's rows: fresh ids and positions, and
    /// whatever identity survives the panel's next shipment — the ping, the
    /// pin, the user's own hide, the last use — carried over by linkKey.
    private func stamped(
        _ drafts: [Profile], subscriptionID: String, old: [Profile]
    ) -> [Profile] {
        let oldByKey = Dictionary(old.map { ($0.linkKey, $0) }, uniquingKeysWith: { first, _ in first })
        return drafts.enumerated().map { index, draft in
            let key = draft.computeLinkKey()
            let previous = oldByKey[key]
            var row = draft
            row.id = previous?.id ?? UUID().uuidString
            row.subscriptionID = subscriptionID
            row.order = index
            if row.remarks.isEmpty { row.remarks = previous?.remarks ?? "" }
            row.linkKey = key
            row.testDelayMillis = previous?.testDelayMillis
            row.lastTestAt = previous?.lastTestAt
            // The last use rides the identity like the ping does: the chip's
            // "last used" order keeps its memory through whatever ships next.
            row.lastUsedAt = previous?.lastUsedAt
            // The pin rides it too: a server the user pinned stays pinned
            // through whatever the panel ships next.
            row.pinned = previous?.pinned ?? false
            // The hide rides it too: a server the user hid stays out of sight
            // through whatever the panel ships next.
            row.concealed = previous?.concealed ?? false
            return row
        }
    }
}
