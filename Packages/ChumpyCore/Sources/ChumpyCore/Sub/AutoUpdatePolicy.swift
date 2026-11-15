import Foundation

/// When subscriptions auto-update: the interval each panel's
/// `profile-update-interval` header asks for, clamped, with a sensible
/// default; the due date each subscription's last refresh plus its interval
/// gives. The clamp bounds are the Android client's constants.
public enum AutoUpdatePolicy {

    public static let defaultHours = 24
    public static let minHours = 1
    public static let maxHours = 24 * 14

    /// BGTaskScheduler never fires sooner than fifteen minutes out; a due
    /// date closer than that simply means "as soon as the system allows".
    public static let schedulerLeadSeconds: TimeInterval = 15 * 60

    /// The interval a subscription refreshes on: the panel's hint when it
    /// gave one, the default otherwise — either way clamped.
    public static func effectiveIntervalHours(_ hint: Int?) -> Int {
        guard let hint, hint > 0 else { return defaultHours }
        return min(max(hint, minHours), maxHours)
    }

    /// When the subscription is next due for a refresh. A subscription that
    /// never updated is due from its last *attempt* — a long string of
    /// failures does not stall the schedule forever.
    public static func dueDate(of subscription: SubscriptionEntity) -> Date {
        let hours = effectiveIntervalHours(subscription.updateIntervalHours)
        let anchor = subscription.lastUpdateSuccess
            ?? subscription.lastUpdateAttempt
            ?? subscription.createdAt
        return anchor.addingTimeInterval(TimeInterval(hours) * 3600)
    }

    /// Whether the subscription wants a refresh now. The auto-update toggle
    /// decides; the interval says when.
    public static func isDue(_ subscription: SubscriptionEntity, now: Date = Date()) -> Bool {
        subscription.autoUpdate && dueDate(of: subscription) <= now
    }

    /// The soonest moment a background refresh has work to do — the task's
    /// earliest begin date. Nil when no subscription auto-updates.
    public static func nextRefreshDate(
        _ subscriptions: [SubscriptionEntity], now: Date = Date()
    ) -> Date? {
        guard let soonest = subscriptions
            .filter({ $0.autoUpdate })
            .map({ dueDate(of: $0) })
            .min()
        else { return nil }
        return max(soonest, now.addingTimeInterval(schedulerLeadSeconds))
    }
}
