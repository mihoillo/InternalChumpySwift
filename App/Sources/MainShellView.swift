import SwiftUI

/// The app shell: full-screen content with Chumpy's two-pill floating
/// bar — the tabs' capsule and the gear's circle, compact, the way the
/// original client wears it. The deck runs the original's whole length:
/// the three tabs, then the settings' own three leaves — interface,
/// connection, about — and as the deck rides into the settings region
/// the pills trade faces: the tabs fold into the round back arrow, the
/// gear unfolds into the categories' capsule, the bar's own width
/// never changing. The swipe's corridor is the original's own: the
/// two groups never mix — a swipe past the last tab finds no next
/// page, the settings' far wall is the interface leaf, and the only
/// doors between the groups stay the bar's own pills. The gear always
/// lands on About, not wherever the settings deck last stood. The item
/// faces wear the glass indicator gliding between the equal slots —
/// under the finger with the swipe, on the shared spring with the
/// settle — and a press held half a beat swells the glass and lets the
/// finger drag it, the iOS 26 bar's own trick rebuilt for the plain
/// material years.
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page: Page = .home
    /// The tab the gear folds back to — the last one that stood.
    @State private var lastTab: Tab = .home

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
    }

    /// The deck's pages: the three tabs, then the settings deck's own
    /// three leaves — interface, connection, about — the way the
    /// original client's own deck runs on.
    enum Page: Int {
        case home = 0, servers = 1, stats = 2
        case interface = 3, connection = 4, about = 5
    }

    /// The deck's own ride: every page change slides along it — a
    /// swipe settles on it once the finger lets go, the bar's buttons
    /// scroll the deck across it, page over page.
    private let deckMotion = Animation.spring(response: 0.45, dampingFraction: 0.85)

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
        case .interface: return "interface"
        case .connection: return "connection"
        case .about: return "about"
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
        case .interface: return "settings.interface"
        case .connection: return "settings.connection"
        case .about: return "settings.about"
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
            // Home never scrolls and holds its ground clear; About wears
            // the original client's bare hero instead of a page title — no
            // header title strip there, the page's own mark speaks for it.
            if page != .home {
                if page != .about {
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
                }

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
                InterfaceView()
                    .offset(pageOffset(for: .interface, in: geo.size))
                SettingsView()
                    .offset(pageOffset(for: .connection, in: geo.size))
                AboutView()
                    .offset(pageOffset(for: .about, in: geo.size))
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

    /// The current drag's corridor: the group the drag began in, the
    /// original client's own law — the two groups never mix. Fixed at
    /// the drag's first word, so a whole swipe either walks the three
    /// tabs or the three settings leaves, never crosses between them.
    @State private var corridor: ClosedRange<CGFloat> = 0...2

    /// The swipe corridor a drag anchored at [position] belongs to:
    /// the settings' three leaves once the anchor stands in their
    /// region, the three tabs otherwise.
    private func corridor(at position: CGFloat) -> ClosedRange<CGFloat> {
        if position >= CGFloat(Page.interface.rawValue) {
            return CGFloat(Page.interface.rawValue)...CGFloat(Page.about.rawValue)
        }
        return 0...CGFloat(Tab.allCases.count - 1)
    }

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
                    corridor = corridor(at: dragAnchor)
                    startWatchdog()
                }
                lastDragEvent = .now
                // Left is forward along the spine — the finger drags
                // the deck, not the position, so the travel is the
                // translation's mirror, past the anchor's own.
                let traveled = -value.translation.width / size.width - dragAnchorTravel
                let raw = dragAnchor + traveled
                // The corridor's ends resist: past the group's first or
                // last page the deck yields less and less, and always
                // springs back — the other group has no swipe door.
                let bounded = min(max(raw, corridor.lowerBound), corridor.upperBound)
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
                // One page per swipe: the throw may point past the next
                // page, but the deck settles at most one step from where
                // the drag began — one forward or one back, never a leap,
                // and never out of the corridor.
                let stepped = min(max(raw.rounded(), dragAnchor - 1), dragAnchor + 1)
                let target = min(max(stepped, corridor.lowerBound), corridor.upperBound)
                settleDeck(to: Page(rawValue: Int(target)) ?? page)
            }
    }

    /// Sends the deck to a page on the bar's own ride: along the same
    /// horizontal spine, page over page, on the shared spring. Every
    /// ask that rides it — a tab, the gear, the back arrow, a held
    /// press's release — pokes like every other button.
    private func rideDeck(to target: Page) {
        Haptics.poke()
        settleDeck(to: target)
    }

    private func openTab(_ tab: Tab) {
        let target = Page(tab: tab)
        guard target != page else { return }
        rideDeck(to: target)
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

    /// The page the deck sits closest to — the watchdog's landing spot,
    /// inside the drag's own corridor.
    private func nearestPage() -> Page {
        let target = min(max(deckPosition.rounded(), corridor.lowerBound), corridor.upperBound)
        return Page(rawValue: Int(target)) ?? page
    }

    /// The one road every settle rides — the swipe's end, the watchdog's
    /// recovery, the bar's own ride: the deck lands on the page on the
    /// shared spring, and the gear remembers the last tab that stood.
    private func settleDeck(to target: Page) {
        withAnimation(deckMotion) {
            deckPosition = CGFloat(target.rawValue)
            page = target
        }
        if let tab = Tab(rawValue: target.rawValue) {
            lastTab = tab
        }
    }

    // MARK: - The bar

    /// The bar the Chumpy way, compact: two pills trading faces as the
    /// deck rides into the settings region and back — the tabs'
    /// capsule folding into the round back arrow, the gear's circle
    /// unfolding into the categories' capsule — the whole trade keeping
    /// the bar's own width, the pills merely swapping their weight.
    private var bar: some View {
        HStack(spacing: 12) {
            tabsPill
            settingsPill
        }
        // The held press swells the whole bar a touch — the glass
        // leaning toward the finger.
        .scaleEffect(scrubbing ? 1.04 : 1, anchor: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: scrubbing)
    }

    /// How far the deck has ridden into the settings region: 0 at the
    /// last tab, 1 at the interface page. Both pills' faces ride it.
    /// A drag is its own law: the swipe's corridor never crosses the
    /// groups' wall, so the faces never trade mid-drag — the rubber
    /// band at the corridor's end is the deck's alone, not the pills'.
    private var settingsNear: CGFloat {
        if dragging {
            return corridor.lowerBound > 0 ? 1 : 0
        }
        return min(max(deckPosition - CGFloat(Tab.allCases.count - 1), 0), 1)
    }

    /// One item slot's own width — equal slots, the glass's travel step.
    private static let slotWidth: CGFloat = 56
    /// The item face's own content width: three slots.
    private static let faceWidth: CGFloat = slotWidth * 3
    /// The pill's own full girth: the face plus its side insets.
    private static let pillWidth: CGFloat = faceWidth + 24

    /// One item of the bar's item faces: the icon pair and the page it
    /// opens.
    private struct BarItem {
        let icon: String
        let activeIcon: String
        let page: Page
    }

    /// The tabs' own face items — the three pages the tabs own.
    private var tabItems: [BarItem] {
        Tab.allCases.map {
            BarItem(icon: $0.icon, activeIcon: $0.activeIcon, page: Page(tab: $0))
        }
    }

    /// The settings deck's own leaves, the original client's categories:
    /// interface, connection, about.
    private var categoryItems: [BarItem] {
        [
            BarItem(icon: "paintpalette", activeIcon: "paintpalette.fill", page: .interface),
            BarItem(icon: "arrow.triangle.branch", activeIcon: "arrow.triangle.branch", page: .connection),
            BarItem(icon: "info.circle", activeIcon: "info.circle.fill", page: .about),
        ]
    }

    /// The tabs' pill: the item face at rest, folding into the round
    /// back arrow as the deck rides into settings — the face pinned to
    /// the leading edge, the pill shrinking under it, the arrow fading
    /// in centered in what remains.
    private var tabsPill: some View {
        ZStack(alignment: .leading) {
            itemsFace(tabItems, basePage: Page.home.rawValue)
                .opacity(1 - settingsNear)
                .allowsHitTesting(settingsNear < 0.5)
            backFace
                .opacity(settingsNear)
                .allowsHitTesting(settingsNear >= 0.5)
        }
        // Leading on purpose: the hidden face inside is the pill's full
        // 192pt width and it stretches the ZStack to match, so a centered
        // frame would shove the 64pt visible face half its width past the
        // leading edge — the gear and the back arrow standing somewhere
        // left of the pill, untappable, their hit zones lying over the
        // neighbor pill's slots. Leading pins the wide ZStack's leading
        // edge to the pill's own, and the 64pt face rides back to center.
        .frame(
            width: 64 + (Self.pillWidth - 64) * (1 - settingsNear),
            height: 64,
            alignment: .leading
        )
        .chumpyGlassCapsule()
        .clipShape(Capsule())
        .chumpyPillEdge()
    }

    /// The settings' pill: the gear's circle at rest, unfolding into the
    /// categories' capsule as the deck rides in — the gear spinning
    /// away as it goes, the way the original client's own gear unfolds.
    private var settingsPill: some View {
        ZStack(alignment: .leading) {
            gearFace
                .opacity(1 - settingsNear)
                .allowsHitTesting(settingsNear < 0.5)
            itemsFace(categoryItems, basePage: Page.interface.rawValue)
                .opacity(settingsNear)
                .allowsHitTesting(settingsNear >= 0.5)
        }
        .frame(
            width: 64 + (Self.pillWidth - 64) * settingsNear,
            height: 64,
            alignment: .leading
        )
        .chumpyGlassCapsule()
        .clipShape(Capsule())
        .chumpyPillEdge()
    }

    /// The back face — the round arrow the tabs fold into: a tap folds
    /// the deck back to the last tab that stood.
    private var backFace: some View {
        Image(systemName: "chevron.backward")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .onTapGesture {
                rideDeck(to: Page(tab: lastTab))
            }
    }

    /// The gear face — the settings door at rest, the deck's ride into
    /// the settings region starting here. Like the original client's
    /// gear, it always lands on About, not wherever the settings deck
    /// last stood.
    private var gearFace: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(
                deckPosition.rounded() >= CGFloat(Page.interface.rawValue)
                    ? Color.accentColor
                    : Color.secondary
            )
            .rotationEffect(.degrees(120 * settingsNear))
            .frame(width: 64, height: 64)
            .contentShape(Rectangle())
            .onTapGesture {
                rideDeck(to: .about)
            }
    }

    /// An item face: the glass indicator gliding between the equal
    /// slots behind the icons. The indicator rides the deck's own
    /// position — under the finger with the swipe, on the shared spring
    /// with the settle — and the tint flips as the glass crosses the
    /// halfway line.
    private func itemsFace(_ items: [BarItem], basePage: Int) -> some View {
        ZStack(alignment: .leading) {
            tabIndicator
                .frame(width: Self.slotWidth, height: scrubbing ? 56 : 48)
                .offset(x: indicatorOffset(basePage: basePage, count: items.count))
                .animation(.spring(response: 0.32, dampingFraction: 0.8), value: scrubbing)
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    itemSlot(item, basePage: basePage)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(basePage: basePage))
        }
        .frame(width: Self.faceWidth, height: 64)
        .padding(.horizontal, 12)
    }

    /// The glass's leading offset: it rides the deck between the slots,
    /// or the finger itself while the press holds — centered under the
    /// touch, clamped to the face's own ends.
    private func indicatorOffset(basePage: Int, count: Int) -> CGFloat {
        if scrubbing, let scrubX {
            return min(
                max(scrubX - Self.slotWidth / 2, 0),
                Self.faceWidth - Self.slotWidth
            )
        }
        let travel = min(
            max(deckPosition - CGFloat(basePage), 0),
            CGFloat(count - 1)
        )
        return travel * Self.slotWidth
    }

    private func itemSlot(_ item: BarItem, basePage: Int) -> some View {
        // The tint rides the live position — the deck's own, or the
        // finger's while the press holds: the icon lights as the glass
        // crosses the halfway line, and dims the same way back.
        let live: CGFloat
        if scrubbing, let scrubX {
            live = CGFloat(basePage)
                + min(max((scrubX - Self.slotWidth / 2) / Self.slotWidth, 0), 2)
        } else {
            live = deckPosition
        }
        let isSelected = live.rounded() == CGFloat(item.page.rawValue)

        return itemIcon(item, isSelected: isSelected)
            .frame(width: Self.slotWidth, height: 64)
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
    }

    /// The selection's own glass: Liquid Glass on iOS 26 — the inner
    /// capsule the system's tab bar wears inside its own — the quiet
    /// tonal fill everywhere below.
    @ViewBuilder
    private var tabIndicator: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(in: Capsule())
        } else {
            Capsule().fill(Chumpy.secondaryContainer)
        }
        #else
        Capsule().fill(Chumpy.secondaryContainer)
        #endif
    }

    /// The item's icon — with the bounce the platform gives symbols on
    /// iOS 17+, plain everywhere below.
    @ViewBuilder
    private func itemIcon(_ item: BarItem, isSelected: Bool) -> some View {
        let icon = Image(systemName: isSelected ? item.activeIcon : item.icon)
            .font(.system(size: 18, weight: .medium))
        if #available(iOS 17.0, *) {
            icon.symbolEffect(.bounce, value: isSelected)
        } else {
            icon
        }
    }

    // MARK: - The held press

    /// True while a press held on an item face has swelled the glass —
    /// the iOS 26 bar's own trick, rebuilt for the plain material
    /// years: the glass grows and rides the finger until it lets go.
    @State private var scrubbing = false
    /// The finger's own x, in the face's coordinate space, while the
    /// press holds.
    @State private var scrubX: CGFloat?
    /// The press's own clock — armed on the touch, cancelled on the
    /// release; half a beat of stillness swells the glass.
    @State private var holdTask: Task<Void, Never>?

    /// The face's own touch law: a quick release is a tap — the slot it
    /// lands on opens; a press held half a beat swells the glass and
    /// hands it to the finger — it drags between the slots, the tint
    /// flipping as it crosses each halfway — and the release settles
    /// the deck on the slot under the finger.
    private func scrubGesture(basePage: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if scrubbing {
                    scrubX = value.location.x
                } else if holdTask == nil {
                    let startX = value.location.x
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 320_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            scrubbing = true
                            scrubX = startX
                        }
                    }
                }
            }
            .onEnded { value in
                holdTask?.cancel()
                holdTask = nil
                let slot = min(
                    max(
                        Int((value.location.x - Self.slotWidth / 2) / Self.slotWidth),
                        0
                    ),
                    2
                )
                scrubbing = false
                scrubX = nil
                rideDeck(to: Page(rawValue: basePage + slot) ?? page)
            }
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
