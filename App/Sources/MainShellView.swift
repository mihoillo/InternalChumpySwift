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

    /// The bar's own spring — snappier than the page's, with a bit of
    /// bounce, so the bar reads as its own navigation object, not a part
    /// of the page beneath it.
    private let barMotion = Animation.spring(response: 0.34, dampingFraction: 0.72)

    /// How tall the fading blurs run from each screen edge.
    private let bottomBlurHeight: CGFloat = 160
    private let topBlurHeight: CGFloat = 140

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The frosted backdrop under the bar: no hard edge, no empty
            // zone — the pages flow under it and dissolve into a real
            // blur that gains strength towards the screen's bottom.
            EdgeBlur(edge: .bottom)
                .frame(height: bottomBlurHeight)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)

            // The mirror up top — the scrolling pages wear the same
            // dissolve under their navigation bars. Home never scrolls
            // and holds the greeting right there, so it stays clear.
            if page != .home {
                EdgeBlur(edge: .top)
                    .frame(height: topBlurHeight)
                    .allowsHitTesting(false)
                    .ignoresSafeArea(edges: .top)
                    .transition(.opacity)
            }

            bar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .zIndex(1)
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
        withAnimation(barMotion) {
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
    /// keep their icons alone. Everything on the bar's own spring.
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

        // One live layout, no branch swap: the label unrolls out of the
        // icon — its measured width and opacity ride the bar's spring,
        // and the indicator glides between slots underneath.
        return Button {
            openTab(tab)
        } label: {
            HStack(spacing: 0) {
                tabIcon(tab, isSelected: isSelected)
                TabLabel(titleKey: tab.titleKey, isSelected: isSelected)
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
        .buttonStyle(BarPressStyle())
    }

    /// The tab's icon — with the bounce the platform gives symbols on
    /// iOS 17+, plain everywhere below.
    @ViewBuilder
    private func tabIcon(_ tab: Tab, isSelected: Bool) -> some View {
        let icon = Image(systemName: isSelected ? tab.activeIcon : tab.icon)
            .font(.system(size: 17, weight: .medium))
        if #available(iOS 17.0, *) {
            icon.symbolEffect(.bounce, value: isSelected)
        } else {
            icon
        }
    }

    /// The round gear button — the settings door. It turns a quarter on its
    /// own hinge as the settings page opens, and wears the same tonal
    /// indicator the active tab wears.
    private var gearButton: some View {
        let onSettings = page == .settings

        return Button {
            withAnimation(barMotion) {
                page = onSettings ? Page(tab: lastTab) : .settings
            }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 64, height: 64)
                .background(Circle().fill(onSettings ? Chumpy.secondaryContainer : .clear))
                .foregroundStyle(onSettings ? Color.accentColor : Color.secondary)
                .rotationEffect(.degrees(onSettings ? 90 : 0))
                .animation(barMotion, value: onSettings)
        }
        .buttonStyle(BarPressStyle())
        .frame(width: 64, height: 64)
        .chumpyGlassCapsule()
        .clipShape(Circle())
        .chumpyPillEdge()
    }
}

/// The bar's label: measured once, then unrolled on the spring — the
/// frame width animates between the fold and the real text width, so the
/// word slides out of the icon instead of popping in.
private struct TabLabel: View {
    let titleKey: LocalizedStringKey
    let isSelected: Bool

    /// The label's natural width, read once on first layout.
    @State private var textWidth: CGFloat?

    var body: some View {
        Text(titleKey)
            .font(.system(size: 14, weight: .medium))
            .fixedSize()
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { textWidth = geo.size.width }
                }
            }
            .frame(width: isSelected ? (textWidth ?? 0) : 0, alignment: .leading)
            .clipped()
            .padding(.leading, isSelected ? 5 : 0)
            .opacity(isSelected ? 1 : 0)
    }
}

/// The bar's press feedback: the whole pill gives a living squish instead
/// of the platform's flat flash.
private struct BarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
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
