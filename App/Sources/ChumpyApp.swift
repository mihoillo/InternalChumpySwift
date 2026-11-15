import SwiftUI

@main
struct ChumpyApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The background refresh must be registered before launch finishes.
        SubscriptionAutoUpdate.register()
    }

    var body: some Scene {
        WindowGroup {
            MainShellView()
                .environmentObject(appState)
                .tint(Chumpy.accent)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                // A pending submission is replaced, never doubled.
                SubscriptionAutoUpdate.schedule()
            }
        }
    }
}
