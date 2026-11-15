import SwiftUI

@main
struct ChumpyApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainShellView()
                .environmentObject(appState)
                .tint(Chumpy.accent)
        }
    }
}
