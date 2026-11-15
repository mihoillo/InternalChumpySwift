import SwiftUI

/// The app shell: full-screen content with a floating frosted-glass pill bar,
/// mirroring the Android client's MainShell pill (to be upgraded to real
/// Liquid Glass on iOS 26 later).
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page: Page = .home

    enum Page: Int, CaseIterable, Identifiable {
        case home, servers, stats, settings

        var id: Int { rawValue }

        var icon: String {
            switch self {
            case .home: return "house"
            case .servers: return "square.stack.3d.up"
            case .stats: return "chart.bar"
            case .settings: return "gearshape"
            }
        }

        var titleKey: LocalizedStringKey {
            switch self {
            case .home: return "tab.home"
            case .servers: return "tab.servers"
            case .stats: return "tab.stats"
            case .settings: return "tab.settings"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 72)

            FloatingPillBar(selection: $page)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .home: HomeView()
        case .servers: ServersView()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }
}

/// The floating pill: frosted material capsule with a sliding selection pill.
struct FloatingPillBar: View {
    @Binding var selection: MainShellView.Page

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MainShellView.Page.allCases) { page in
                pillButton(for: page)
            }
        }
        .padding(6)
        .chumpyGlassCapsule()
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    }

    private func pillButton(for page: MainShellView.Page) -> some View {
        let isSelected = selection == page

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selection = page
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? page.icon + ".fill" : page.icon)
                    .font(.system(size: 17, weight: .medium))
                Text(page.titleKey)
                    .font(.system(size: 10, weight: .semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .matchedGeometryEffect(id: "pill-selection", in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @Namespace private var namespace
}
