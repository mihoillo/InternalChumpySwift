import SwiftUI

// MARK: - Accent color
// The actual tint color lives in Assets.xcassets (AccentColor).
// `Chumpy.accent` makes it easy to reference in code.

enum Chumpy {
    static let accent = Color("AccentColor")
}

// MARK: - Glass background
// Liquid Glass (iOS 26+) where the platform has it, the frosted material
// (iOS 15+) everywhere else — the baseline look stays native either way.

extension View {

    /// Glass background: `.glassEffect()` on iOS 26, `.regularMaterial`
    /// below.
    @ViewBuilder
    func chumpyGlassCard(cornerRadius: CGFloat = 20) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        }
    }

    /// Glass capsule (floating pill bar, chips): `.glassEffect()` on
    /// iOS 26, `.ultraThinMaterial` below.
    @ViewBuilder
    func chumpyGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }

    /// The pill's own edge treatment: Liquid Glass carries its own, the
    /// material capsule needs the hairline stroke and the shadow.
    @ViewBuilder
    func chumpyPillEdge() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        }
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
