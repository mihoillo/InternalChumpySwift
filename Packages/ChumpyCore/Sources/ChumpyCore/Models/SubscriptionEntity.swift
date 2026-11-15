import Foundation

/// The id the standalone group's row wears — the home of configs pasted
/// outside any subscription. No row with this id stands in the subscriptions
/// store; it is the picker's synthetic first entry, resolved to the manual
/// profiles (whose `subscriptionID` is nil) wherever a real id would be.
/// Ported from the Android client's `STANDALONE_SUBSCRIPTION_ID`.
public let standaloneSubscriptionID = "standalone"

/// One subscription: a URL whose body is a set of server links, plus the
/// metadata panels attach via response headers — traffic counters and expiry
/// from `subscription-userinfo`, the display name from
/// `profile-title`/`content-disposition`, the refresh hint from
/// `profile-update-interval`. Ported from the Android client's
/// `SubscriptionEntity`.
public struct SubscriptionEntity: Codable, Equatable, Identifiable, Hashable {
    public var id: String
    /// Display name; falls back to the host of `url` until the panel names it.
    public var name: String
    public var url: String
    public var createdAt: Date

    /// Wall-clock time of the last fetch attempt, successful or not.
    public var lastUpdateAttempt: Date?
    /// Wall-clock time of the last successful refresh.
    public var lastUpdateSuccess: Date?
    /// The panel's `profile-update-interval` hint in hours; nil means "use the default".
    public var updateIntervalHours: Int?
    /// Whether the app keeps refreshing this subscription in the background.
    public var autoUpdate: Bool

    // Traffic counters from subscription-userinfo; zeros mean "not reported".
    public var uploadBytes: Int64
    public var downloadBytes: Int64
    public var totalBytes: Int64
    /// Expiry as epoch seconds; 0 means "not reported".
    public var expireEpochSeconds: Int64

    /// The message of the last failed update, shown on the subscription card.
    public var lastError: String?

    /// The pin the row menu drives: pinned subscriptions stand the picker's
    /// ground floor, first whatever the panel's birthday order says.
    public var pinned: Bool

    public init(
        id: String = "",
        name: String = "",
        url: String = "",
        createdAt: Date = Date(),
        lastUpdateAttempt: Date? = nil,
        lastUpdateSuccess: Date? = nil,
        updateIntervalHours: Int? = nil,
        autoUpdate: Bool = true,
        uploadBytes: Int64 = 0,
        downloadBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        expireEpochSeconds: Int64 = 0,
        lastError: String? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.createdAt = createdAt
        self.lastUpdateAttempt = lastUpdateAttempt
        self.lastUpdateSuccess = lastUpdateSuccess
        self.updateIntervalHours = updateIntervalHours
        self.autoUpdate = autoUpdate
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.totalBytes = totalBytes
        self.expireEpochSeconds = expireEpochSeconds
        self.lastError = lastError
        self.pinned = pinned
    }
}
