import SwiftUI

/// The app shell: full-screen content with Chumpy's two-pill floating bar —
/// the tabs' pill on the left, the round gear button on the right. Ported
/// from the Android client's `FloatingBottomBar`: Liquid Glass on iOS 26,
/// frosted material below.
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page: Page = .home
    /// The tab the gear folds back to — the last one that stood.
    @State private var lastTab: Tab = .home

    enum Tab: Int, CaseIterable, Identifiable {
        case home, servers, stats

        var id: Int { rawValue }

        var icon: String {
            switch self {
            case .home: return "house"
            case .servers: return "square.stack.3d.up"
            case .stats: return "chart.bar"
            }
        }

        var activeIcon: String {
            switch self {
            case .home: return "house.fill"
            case .servers: return "square.stack.3d.up.fill"
            case .stats: return "chart.bar.fill"
            }
        }

        var titleKey: LocalizedStringKey {
            switch self {
            case .home: return "tab.home"
            case .servers: return "tab.servers"
            case .stats: return "tab.stats"
            }
        }
    }

    enum Page {
        case home, servers, stats, settings
    }

    /// The bar's whole footprint with its margin — what the content keeps
    /// clear below its own bottom-anchored runs.
    private let barReservedHeight: CGFloat = 88

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, barReservedHeight)

            bar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.2), value: page)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .home:
            HomeView {
                openTab(.servers)
            }
        case .servers: ServersView()
        case .stats: StatsView()
        case .settings: SettingsView()
        }
    }

    private func openTab(_ tab: Tab) {
        withAnimation(.easeInOut(duration: 0.2)) {
            page = Page(tab: tab)
            lastTab = tab
        }
    }

    // MARK: - The two-pill bar

    private var bar: some View {
        HStack(spacing: 12) {
            tabsPill
            gearButton
        }
    }

    /// The tabs' own pill: the active tab wears its icon and label on a
    /// tonal indicator; the inactive ones keep their icons alone.
    private var tabsPill: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                tabItem(tab)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .chumpyGlassCapsule()
        .clipShape(Capsule())
        .chumpyPillEdge()
    }

    private func tabItem(_ tab: Tab) -> some View {
        let isSelected = page == Page(tab: tab)

        return Button {
            openTab(tab)
        } label: {
            Group {
                if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: tab.activeIcon)
                            .font(.system(size: 17, weight: .medium))
                        Text(tab.titleKey)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(Capsule().fill(Chumpy.secondaryContainer))
                    .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 48, height: 48)
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The round gear button — the settings door. On the settings page it
    /// wears the same tonal indicator the active tab wears.
    private var gearButton: some View {
        let onSettings = page == .settings

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                page = onSettings ? Page(tab: lastTab) : .settings
            }
        } label: {
            Image(systemName: onSettings ? "gearshape.fill" : "gearshape")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 64, height: 64)
                .background(Circle().fill(onSettings ? Chumpy.secondaryContainer : .clear))
                .foregroundStyle(onSettings ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 64, height: 64)
        .chumpyGlassCapsule()
        .clipShape(Circle())
        .chumpyPillEdge()
    }
}

extension MainShellView.Page {
    init(tab: MainShellView.Tab) {
        switch tab {
        case .home: self = .home
        case .servers: self = .servers
        case .stats: self = .stats
        }
    }

    static func == (lhs: MainShellView.Page, rhs: MainShellView.Tab) -> Bool {
        switch (lhs, rhs) {
        case (.home, .home), (.servers, .servers), (.stats, .stats): return true
        default: return false
        }
    }
}
