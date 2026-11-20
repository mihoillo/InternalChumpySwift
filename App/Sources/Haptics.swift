import UIKit

/// The app's haptic word, ported from the Android client's `Haptics.kt`:
/// a very short poke for taps, a softer one for quiet results, and the
/// denied kicks for failures — all gated by the "Haptic feedback"
/// setting the Interface page owns.
enum Haptics {
    /// The gate every poke answers to — the Interface page's toggle.
    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticFeedback") as? Bool ?? true
    }

    /// The crisp tap poke — the Android client's ~15ms vibrator pulse.
    static func poke() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// The softer poke — a fresh ping answer, where the full tap
    /// amplitude would machine-gun across a sweep. A quarter of the
    /// poke's strength, the Android client's own quarter.
    static func softPoke() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.25)
    }

    /// Two crisp pokes in a row — "that worked", the tunnel coming up.
    static func successPokes() {
        guard isEnabled else { return }
        Task { @MainActor in
            for _ in 0..<2 {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// Three grumpy kicks — the denied-pull feedback, the tunnel
    /// failing to come up.
    static func failureKicks() {
        guard isEnabled else { return }
        Task { @MainActor in
            for _ in 0..<3 {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }
}
