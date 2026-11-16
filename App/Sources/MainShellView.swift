import SwiftUI

/// The app shell: full-screen content with Chumpy's two-pill floating bar —
/// the tabs' pill on the left, the round gear button on the right. Ported
/// from the Android client's `FloatingBottomBar`: Liquid Glass on iOS 26,
/// frosted material below. The indicator slides between the tabs, the
/// pages crossfade, the gear turns on its own hinge.
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page: Page = .home
    /// The tab the gear folds back to — the last one that stood.
    @State private var lastTab: Tab = .home
    @Namespace private var tabNamespace

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

    /// The one motion every page change rides: a soft spring.
    private let pageMotion = Animation.spring(response: 0.38, dampingFraction: 0.86)

    /// The bar's own spring — snappier than the page's, so the bar reads
    /// as its own navigation object, not a part of the page beneath it.
    private let barMotion = Animation.spring(response: 0.32, dampingFraction: 0.75)

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The frosted backdrop under the bar: no hard edge, no empty
            // zone — the pages flow under it and dissolve into the blur
            // via a clear-to-solid gradient mask.
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 150)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)

            bar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            switch page {
            case .home:
                HomeView {
                    openTab(.servers)
                }
                .transition(pageTransition)
            case .servers:
                ServersView()
                    .transition(pageTransition)
            case .stats:
                StatsView()
                    .transition(pageTransition)
            case .settings:
                SettingsView()
                    .transition(pageTransition)
            }
        }
    }

    /// The pages trade places behind a plain crossfade — the shell itself
    /// never moves, never scales.
    private var pageTransition: AnyTransition {
        .opacity
    }

    private func openTab(_ tab: Tab) {
        withAnimation(pageMotion) {
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
    /// tonal indicator that slides between the slots; the inactive ones
    /// keep their icons alone.
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
        .animation(barMotion, value: page)
    }

    private func tabItem(_ tab: Tab) -> some View {
        let isSelected = page == Page(tab: tab)

        // One live layout, no branch swap: the label unfolds out of the
        // icon — its width and opacity ride the spring, so the pill reads
        // as one object gliding between slots.
        return Button {
            openTab(tab)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                    .font(.system(size: 17, weight: .medium))
                Text(tab.titleKey)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: isSelected ? nil : 0)
                    .opacity(isSelected ? 1 : 0)
                    .padding(.leading, isSelected ? 5 : 0)
            }
            .padding(.horizontal, isSelected ? 16 : 14)
            .frame(minWidth: 44, minHeight: 48)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Chumpy.secondaryContainer)
                        .matchedGeometryEffect(id: "tab-indicator", in: tabNamespace)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    /// The round gear button — the settings door. It turns a quarter on its
    /// own hinge as the settings page opens, and wears the same tonal
    /// indicator the active tab wears.
    private var gearButton: some View {
        let onSettings = page == .settings

        return Button {
            withAnimation(pageMotion) {
                page = onSettings ? Page(tab: lastTab) : .settings
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 64, height: 64)
                .background(Circle().fill(onSettings ? Chumpy.secondaryContainer : .clear))
                .foregroundStyle(onSettings ? Color.accentColor : Color.secondary)
                .rotationEffect(.degrees(onSettings ? 90 : 0))
        }
        .buttonStyle(.plain)
        .frame(width: 64, height: 64)
        .chumpyGlassCapsule()
        .clipShape(Circle())
        .chumpyPillEdge()
        .animation(barMotion, value: page)
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
}
