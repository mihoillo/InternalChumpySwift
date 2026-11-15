import SwiftUI

// MARK: - Accent color
// The actual tint color lives in Assets.xcassets (AccentColor).
// `Chumpy.accent` makes it easy to reference in code.

enum Chumpy {
    static let accent = Color("AccentColor")
}

// MARK: - Glass background
// Frosted glass (iOS 15+ materials) is the baseline everywhere.
//
// TODO(Liquid Glass): once the project is built with the iOS 26 SDK,
// replace the material with `.glassEffect()` gated by `#available(iOS 26, *)`
// (see docs: "Applying Liquid Glass to custom views"). The `.capsule` variant
// here is exactly the modifier that will migrate — the floating pill bar.

extension View {

    /// Frosted-glass background. Liquid Glass comes later (iOS 26+).
    func chumpyGlassCard(cornerRadius: CGFloat = 20) -> some View {
        background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    /// Frosted-glass capsule (floating pill bar, chips).
    func chumpyGlassCapsule() -> some View {
        background(.ultraThinMaterial, in: Capsule())
    }
}

// MARK: - Navigation (iOS 16 NavigationStack with iOS 15 fallback)

struct NavHost<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(root: content)
        } else {
            NavigationView(content: content)
                .navigationViewStyle(.stack)
        }
    }
}

extension View {
    func hostedInNavigation() -> some View {
        NavHost { self }
    }
}
