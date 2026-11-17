import SwiftUI

/// The app shell: full-screen content with Chumpy's two-pill floating bar —
/// the tabs' pill on the left, the round gear button on the right. Ported
/// from the Android client's `FloatingBottomBar`: Liquid Glass on iOS 26,
/// frosted material below. The pages ride one horizontal deck — a swipe
/// deals it under the finger, the bar's buttons scroll it along the same
/// spine, page over page. The indicator slides between the tabs, the gear
/// turns on its own hinge.
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page: Page = .home
    /// The tab the gear folds back to — the last one that stood.
    @State private var lastTab: Tab = .home
    @Namespace private var tabNamespace

    /// The live page's scroll, by tag: every page keeps its own word
    /// in the reporter, so the frost knows the page's stance the moment
    /// the deck lands on it. Home reports nothing and holds its ground
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

    enum Page: Int {
        case home = 0, servers = 1, stats = 2, settings = 3
    }

    /// The deck's own ride: every page change slides along it — a
    /// swipe settles on it once the finger lets go, the bar's buttons
    /// scroll the deck across it, page over page.
    private let deckMotion = Animation.spring(response: 0.45, dampingFraction: 0.85)

    /// The bar's own spring — snappier than the page's, with a bit of
    /// bounce, so the bar reads as its own navigation object, not a part
    /// of the page beneath it.
    private let barMotion = Animation.spring(response: 0.34, dampingFraction: 0.72)

    /// How tall the frost runs from the bar's edge — exactly the bar's
    /// own zone: its height plus its lift above the home indicator, so
    /// the dissolve is the bar's, nothing more.
    private let bottomBlurHeight: CGFloat = 76

    /// How far the page must travel for a frost to commit or hold: the
    /// header frost is fully on after this much scroll, the bar frost
    /// fully off with this little left below the fold.
    private let blurCommitDistance: CGFloat = 40

    // MARK: - The scroll's word on the frost

    /// The live page's tag — the only scroll the shell heeds. The pager
    /// keeps every page alive; each one's scroll speaks for itself,
    /// tagged.
    private var activeTag: String {
        switch page {
        case .home: return "home"
        case .servers: return "servers"
        case .stats: return "stats"
        case .settings: return "settings"
        }
    }

    /// The live page's own word — remembered by tag, so the frost is
    /// at its strength the moment the deck lands on the page, not a
    /// beat after.
    private var activeMetrics: ScrollMetrics {
        scrollReporter.metricsByTag[activeTag] ?? ScrollMetrics(tag: activeTag)
    }

    /// How far the live page has traveled from its start.
    private var scrolled: CGFloat {
        activeMetrics.scrolled
    }

    /// How much content still waits below the fold — zero at the end.
    private var belowFold: CGFloat {
        activeMetrics.belowFold
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

    /// The live page's name — the header title's text.
    private var pageTitleKey: LocalizedStringKey {
        switch page {
        case .home: return "tab.home"
        case .servers: return "tab.servers"
        case .stats: return "tab.stats"
        case .settings: return "tab.settings"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            pager
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The frost at the screen's edges, run by the scroll. The
            // header strip carries the page's title through both its
            // lives — large and leading where the page's content begins,
            // folded small and centered into the strip once the page
            // scrolls, the same fold that wakes the frost. The bar frost
            // sleeps again once the page reaches its end. Both are
            // anchored at the physical frame, past the safe areas, under
            // the status bar and the home indicator alike; the plain
            // frame sizes each band, the background carries it into the
            // unsafe zones, and the outer frame pins it to its own edge.
            // Home never scrolls and holds its ground clear.
            if page != .home {
                Color.clear
                    .frame(height: chumpyHeaderHeight)
                    .overlay(
                        MorphingPageTitle(
                            titleKey: pageTitleKey,
                            fold: topStrength,
                            scrolled: scrolled
                        )
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

            bar
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .zIndex(1)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// The pages as one horizontal deck, one screen apiece, stacked in
    /// the shell's frame. A swipe deals it under the finger; the bar's
    /// buttons scroll it along the same spine, page over page — the
    /// way a wide row of screens reads. Every page stays alive: scroll
    /// positions, and each one's own word on the frost, survive the
    /// rides between them.
    private var pager: some View {
        GeometryReader { geo in
            ZStack {
                HomeView { openTab(.servers) }
                    .offset(pageOffset(for: .home, in: geo.size))
                ServersView()
                    .offset(pageOffset(for: .servers, in: geo.size))
                StatsView()
                    .offset(pageOffset(for: .stats, in: geo.size))
                SettingsView()
                    .offset(pageOffset(for: .settings, in: geo.size))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(deckDrag(in: geo.size))
        }
    }

    /// Where a page sits on the deck: the live page under the shell,
    /// the others a whole screen away along the spine.
    private func pageOffset(for page: Page, in size: CGSize) -> CGSize {
        let distance = CGFloat(page.rawValue) - deckPosition
        return CGSize(width: distance * size.width, height: 0)
    }

    // MARK: - The deck's ride

    /// The deck's spine position, in pages: 0 home, 1 servers, 2 stats,
    /// 3 settings. Animated on the ride spring, led by the finger
    /// during a swipe.
    @State private var deckPosition: CGFloat = 0

    /// The spine position the current drag started from.
    @State private var dragAnchor: CGFloat = 0

    /// The travel the finger had already walked when the drag anchored —
    /// the drag's word starts at its anchor, so a re-anchored drag (the
    /// watchdog settled under a paused finger) leads on from where the
    /// deck stands, never a jump by the whole walk.
    @State private var dragAnchorTravel: CGFloat = 0

    /// True once this drag has been read as the deck's — the scroll
    /// views own the vertical drags, and a drag only joins the deck
    /// once its own direction reads horizontal.
    @State private var dragging = false

    /// The horizontal swipe: a clearly horizontal drag is the deck's —
    /// the finger leads, the ends resist, and letting go settles on
    /// the nearest step the throw points at, at most one page from
    /// where the drag began. A swipe left deals the next page, a swipe
    /// right the one before it. A gesture stolen or cancelled mid-
    /// flight never speaks its onEnded — the watchdog settles the
    /// deck on its nearest page instead.
    private func deckDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                if !dragging {
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragging = true
                    dragAnchor = deckPosition.rounded()
                    dragAnchorTravel = -value.translation.width / size.width
                    startWatchdog()
                }
                lastDragEvent = .now
                // Left is forward along the spine — the finger drags
                // the deck, not the position, so the travel is the
                // translation's mirror, past the anchor's own.
                let traveled = -value.translation.width / size.width - dragAnchorTravel
                let available = CGFloat(Page.settings.rawValue)
                let raw = dragAnchor + traveled
                // The ends resist: past the first or the last page the
                // deck yields less and less, and always springs back.
                let bounded = min(max(raw, 0), available)
                let overshoot = raw - bounded
                deckPosition = bounded + overshoot * 0.32
            }
            .onEnded { value in
                guard dragging else { return }
                dragging = false
                watchdogTask?.cancel()
                let traveled = -value.translation.width / size.width - dragAnchorTravel
                let thrown = -value.velocity.width / size.width * 0.25
                let raw = dragAnchor + traveled + thrown
                let available = CGFloat(Page.settings.rawValue)
                // One page per swipe: the throw may point past the next
                // page, but the deck settles at most one step from where
                // the drag began — one forward or one back, never a leap.
                let stepped = min(max(raw.rounded(), dragAnchor - 1), dragAnchor + 1)
                let target = min(max(stepped, 0), available)
                settleDeck(to: Page(rawValue: Int(target)) ?? page)
            }
    }

    /// Sends the deck to a page on the bar's own ride: along the same
    /// horizontal spine, page over page, on the shared spring.
    private func rideDeck(to target: Page) {
        settleDeck(to: target)
    }

    private func openTab(_ tab: Tab) {
        guard Page(tab: tab) != page else { return }
        lastTab = tab
        rideDeck(to: Page(tab: tab))
    }

    // MARK: - The deck's settler

    /// The watchdog that walks the deck home when a gesture dies without
    /// a word. A swipe that starts horizontal can be stolen mid-flight —
    /// the page's own scroll view claims the touch on a diagonal drag,
    /// the system swallows it on a control-center swipe — and a stolen
    /// or cancelled gesture never speaks its onEnded: the deck would
    /// rest between pages with `dragging` stuck true, and the next swipe
    /// would ride a stale anchor. The watchdog listens for the silence:
    /// once the drag has gone quiet, the deck settles on its nearest
    /// page on the shared spring and the drag state resets — and a
    /// finger merely resting mid-drag is forgiven: its next word
    /// re-anchors the drag from where the deck settled and leads on.
    @State private var watchdogTask: Task<Void, Never>?

    /// When the drag last spoke — every onChanged feeds it.
    @State private var lastDragEvent = Date.distantPast

    /// Starts the watchdog on the drag's first word.
    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard dragging, !Task.isCancelled else { return }
                guard Date.now.timeIntervalSince(lastDragEvent) > 0.35 else { continue }
                dragging = false
                settleDeck(to: nearestPage())
                return
            }
        }
    }

    /// The page the deck sits closest to — the watchdog's landing spot.
    private func nearestPage() -> Page {
        let available = CGFloat(Page.settings.rawValue)
        let target = min(max(deckPosition.rounded(), 0), available)
        return Page(rawValue: Int(target)) ?? page
    }

    /// The one road every settle rides — the swipe's end, the watchdog's
    /// recovery, the bar's own ride: the deck lands on the page on the
    /// shared spring, and the bar's tabs learn the page.
    private func settleDeck(to target: Page) {
        withAnimation(deckMotion) {
            deckPosition = CGFloat(target.rawValue)
            page = target
        }
        if let tab = Tab(rawValue: target.rawValue) {
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
        // A swipe deals the deck without a button — the indicator must
        // ride the same spring anyway.
        .animation(barMotion, value: page)
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
            let target: Page = onSettings ? Page(tab: lastTab) : .settings
            rideDeck(to: target)
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

/// The page's title, one view living both its lives: large and leading
/// where the page's content begins, folded small and centered into the
/// header strip once the page scrolls. The fold (0…1) carries the whole
/// trip — the type shrinks from the large 34 to the header's 17, the
/// position slides from the content's title spot into the strip's
/// center. No fade: the title travels.
private struct MorphingPageTitle: View {
    let titleKey: LocalizedStringKey
    /// 0 — large, at rest in the content; 1 — folded into the header.
    let fold: CGFloat
    /// How far the page has traveled — the title starts at content
    /// speed and the fold gathers the rest of the way.
    let scrolled: CGFloat

    /// The title's measured width — the leading rest position needs it.
    @State private var textWidth: CGFloat = 0

    private var fontSize: CGFloat {
        chumpyLargeTitleSize - 17 * fold
    }

    var body: some View {
        GeometryReader { geo in
            Text(titleKey)
                .font(.system(size: fontSize, weight: fold > 0.5 ? .semibold : .bold))
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { text in
                        Color.clear
                            .onAppear { textWidth = text.size.width }
                            .onChange(of: text.size.width) { textWidth = $0 }
                    }
                )
                .position(x: xPosition(in: geo.size.width), y: yPosition)
        }
    }

    /// Leading at rest, centered in the strip once folded.
    private func xPosition(in width: CGFloat) -> CGFloat {
        let leading = 16 + textWidth / 2
        let centered = width / 2
        return leading + (centered - leading) * fold
    }

    /// The title's center: at rest it sits in the content's title spot —
    /// below the strip, where the pages pad their content; folded it
    /// sits in the strip's middle. The scroll carries it while it can,
    /// the fold gathers the rest.
    private var yPosition: CGFloat {
        let rest = chumpyTitleRestTop + chumpyLargeTitleSize / 2
        let folded = chumpyHeaderHeight / 2
        let traveling = rest - scrolled
        return traveling + (folded - traveling) * fold
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
