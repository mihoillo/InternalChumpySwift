import Foundation
import BackgroundTasks
import ChumpyCore

/// The periodic background refresh of due subscriptions. iOS has no
/// WorkManager; one registered `BGAppRefreshTask` stands in for the Android
/// client's per-subscription job: scheduled at the soonest due date, and when
/// the system fires it, refreshing every subscription whose interval has
/// elapsed, then scheduling the next cycle. The system decides when it
/// actually runs — usually while the device charges overnight.
enum SubscriptionAutoUpdate {

    static let taskIdentifier = "slop.miho.chumpy.swift.subscription-refresh"

    /// Registers the handler; call once per launch, before the app finishes
    /// launching.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier, using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// (Re)schedules the refresh at the soonest due date. Replacing a
    /// pending submission of the same identifier is the API's own way — no
    /// cancel first. On the simulator the API is unavailable; the failure is
    /// logged, never fatal.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = AutoUpdatePolicy.nextRefreshDate(
            ProfileStore().subscriptions()
        ) ?? Date(timeIntervalSinceNow: 6 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            ChumpyLog.shared.append(
                "auto-update schedule failed: \(error.localizedDescription)"
            )
        }
    }

    /// Cancels a pending submission — the auto-update toggle turned off
    /// everywhere.
    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let work = Task {
            await refreshDue()
            schedule()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            schedule()
            task.setTaskCompleted(success: false)
        }
    }

    /// Refreshes every due subscription; failures land on the card, the
    /// cycle goes on.
    static func refreshDue() async {
        let store = ProfileStore()
        let fetcher = SubscriptionFetcher(tunnelUp: tunnelUp)
        for subscription in store.subscriptions() where AutoUpdatePolicy.isDue(subscription) {
            do {
                let fetched = try await fetcher.fetchWithNestedExpansion(subscription.url)
                try store.updateSubscription(
                    id: subscription.id, body: fetched.body, metadata: fetched.metadata
                )
            } catch {
                store.markSubscriptionUpdateFailed(
                    id: subscription.id, message: error.localizedDescription
                )
            }
        }
    }

    /// Whether the tunnel is up, from the outside: the provider writes its
    /// stats timestamp every second it runs, so a fresh one means the core
    /// is live and a blocked panel is best reached through its loopback
    /// SOCKS inbound.
    private static func tunnelUp() -> Bool {
        let last = ChumpyConstant.sharedDefaults
            .double(forKey: ChumpyConstant.Keys.statsUpdatedAt)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < 10
    }
}
