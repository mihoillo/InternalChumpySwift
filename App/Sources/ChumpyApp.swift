import SwiftUI
import ChumpyCore

@main
struct ChumpyApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase
    /// The app's theme word, the Interface page's three tiles write it:
    /// 0 — the system's own scheme, 1 — always light, 2 — always dark.
    /// The root reads it so the whole app — every page, every card,
    /// every glass pill — flips at once, no page left behind.
    @AppStorage("themeMode") private var themeMode: Int = 0

    init() {
        // The background refresh must be registered before launch finishes.
        SubscriptionAutoUpdate.register()
        // The log is this session's story — the last one's mountain
        // doesn't survive the restart.
        ChumpyLog.shared.clear()
    }

    var body: some Scene {
        WindowGroup {
            MainShellView()
                .environmentObject(appState)
                .tint(Chumpy.accent)
                .preferredColorScheme(
                    themeMode == 1 ? .light : themeMode == 2 ? .dark : nil
                )
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                // A pending submission is replaced, never doubled.
                SubscriptionAutoUpdate.schedule()
            }
        }
    }
}
