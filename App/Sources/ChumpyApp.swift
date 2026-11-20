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
    /// The accent's own word, the Interface page's picker writes it:
    /// the hex of the fixed or custom color the whole app wears. The
    /// root hands the resolved accent to the environment, so every
    /// `Color.accentColor` — and every `Chumpy.accent`, its alias —
    /// follows the pick live.
    @AppStorage("accentHex") private var accentHex: String = ChumpyAccent.defaultHex
    /// The accent kind beside the hex: fixed (including custom), the
    /// theme-following monochrome, or the hidden rainbow behind mono's
    /// long press. Keeping the kind separate preserves the user's fixed
    /// color while either special mode is in play.
    @AppStorage("accentKind") private var accentKind = ChumpyAccent.Kind.fixed.rawValue
    @Environment(\.colorScheme) private var colorScheme
    /// Rainbow's own clock: sampled 30 times a second, quantized to whole
    /// hue degrees by the accent resolver. Its state only changes while the
    /// rainbow mode is active; every other accent renders without a clock.
    @State private var rainbowTime = Date.timeIntervalSinceReferenceDate
    private let rainbowClock = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    /// One resolution feeds the tint, the hand-painted accent, and its ink,
    /// so no role can lag a hue behind the others.
    private var resolvedAccent: Color {
        ChumpyAccent.color(
            kind: accentKind,
            hex: accentHex,
            colorScheme: colorScheme,
            time: rainbowTime
        )
    }

    init() {
        // The hex round-trip is the accent picker's only parser; keep its
        // channel order checked on every debug launch.
        assert(ChumpyAccent.color(hex: "#010203").hexString == "#010203")
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
                .tint(resolvedAccent)
                // `.tint` alone dresses the controls; `.accentColor` is
                // the word `Color.accentColor` itself reads, so the
                // hand-painted accents follow the pick too.
                .accentColor(resolvedAccent)
                .environment(\.chumpyAccentInk, ChumpyAccent.isLight(resolvedAccent) ? .black : .white)
                .preferredColorScheme(
                    themeMode == 1 ? .light : themeMode == 2 ? .dark : nil
                )
                .onReceive(rainbowClock) { now in
                    guard accentKind == ChumpyAccent.Kind.rainbow.rawValue else { return }
                    rainbowTime = now.timeIntervalSinceReferenceDate
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                // A pending submission is replaced, never doubled.
                SubscriptionAutoUpdate.schedule()
            }
        }
    }
}
