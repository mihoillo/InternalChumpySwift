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

    /// The live page's scroll, reported by the page's own spy inside the
    /// real UIScrollView. Home reports nothing and holds its ground
    /// clear.
    @ObservedObject private var scrollReporter = ScrollReporter.shared

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

    /// How tall the frost runs from the bar's edge — the bar's own
    /// height plus its lift, so the dissolve starts with the bar and not
    /// far above it.
    private let bottomBlurHeight: CGFloat = 88

    /// How far the page must travel for a frost to commit or hold: the
    /// header frost is fully on after this much scroll, the bar frost
    /// fully off with this little left below the fold.
    private let blurCommitDistance: CGFloat = 40

    // MARK: - The scroll's word on the frost

    /// How far the page has traveled from its start.
    private var scrolled: CGFloat {
        scrollReporter.metrics.scrolled
    }

    /// How much content still waits below the fold — zero at the end.
    private var belowFold: CGFloat {
        scrollReporter.metrics.belowFold
    }

    /// The header frost's strength: off at the start, committed once the
    /// page has traveled the commit distance.
    private var topStrength: CGFloat {
        min(1, scrolled / blurCommitDistance)
    }

    /// The bar frost's strength: committed while content waits below the
    /// fold, off at the list's end.
    private var bottomStrength: CGFloat {
        min(1, belowFold / blurCommitDistance)
    }

    /// The live page's name — the header's small centered title.
    private var pageTitleKey: LocalizedStringKey {
        switch page {
        case .home: return "tab.home"
        case .servers: return "tab.servers"
        case .stats: return "tab.stats"
        case .settings: return "tab.settings"
        }
    }

    /// TEMPORARY — the scroll's pulse, on screen while the frost is
    /// being tuned: it tells a dead reporter from a deaf blur in one
    /// glance. Goes away once the frost is settled.
    private var debugLine: String {
        String(
            format: "s %.0f  b %.0f  T %.2f  B %.2f",
            scrolled, belowFold, topStrength, bottomStrength
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The frost at the screen's edges, run by the scroll. The
            // pages carry their own large title in the content; the header
            // strip up here is its folded state — the small centered
            // title over the header frost, both waking together as the
            // page leaves its start. The bar frost sleeps again once the
            // page reaches its end. Both are anchored at the physical
            // frame, past the safe areas, under the status bar and the
            // home indicator alike; the plain frame sizes each band, the
            // background carries it into the unsafe zones, and the outer
            // frame pins it to its own edge. Home never scrolls and holds
            // its ground clear.
            if page != .home {
                Color.clear
                    .frame(height: chumpyHeaderHeight)
                    .overlay(
                        Text(pageTitleKey)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                            .opacity(topStrength)
                    )
                    .background(EdgeBlur(edge: .top, strength: topStrength).ignoresSafeArea(edges: .top))
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)

                Color.clear
                    .frame(height: bottomBlurHeight)
                    .background(EdgeBlur(edge: .bottom, strength: bottomStrength).ignoresSafeArea(edges: .bottom))
                    .allowsHitTesting(false)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .transition(.opacity)
            }

            // TEMPORARY — the scroll's pulse, see debugLine. Tiny,
            // dead to touches, gone in the commit after the frost is
            // settled.
            Text(debugLine)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 4)
                .padding(.top, 2)
                .allowsHitTesting(false)

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
            scrollReporter.metrics = ScrollMetrics()
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
                scrollReporter.metrics = ScrollMetrics()
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
