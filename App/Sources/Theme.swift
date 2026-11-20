import SwiftUI
import UIKit

// MARK: - Accent color
// The accent is the app's own pick, stored as a hex string the root
// reads and hands the environment. `Chumpy.accent` is the semantic
// accent color, so every view that reads it follows the pick live.

enum Chumpy {
    /// The semantic accent — the root's `.accentColor` pick, live.
    static let accent = Color.accentColor
    /// The accent's own ink: black over a light accent, white over a
    /// dark one — the Android client's readable `onPrimary`, kept for
    /// every plate the accent itself fills.
    static var onAccent: Color {
        let hex = UserDefaults.standard.string(forKey: "accentHex") ?? ChumpyAccent.defaultHex
        return ChumpyAccent.isLight(ChumpyAccent.color(hex: hex)) ? .black : .white
    }

    // MARK: iOS system shades
    // The Android client leans on M3 tonal containers; here the same slots
    // wear the platform's own fills instead — system grays and the tint's
    // own selection fill, dark mode included for free.

    /// Chips and quiet fills: `quaternarySystemFill`.
    static let surfaceContainerLow = Color(.quaternarySystemFill)
    /// Cards and grouped rows: the grouped-list background.
    static let surfaceContainer = Color(.secondarySystemGroupedBackground)
    /// Tiles, indicators, the idle connect base: `tertiarySystemFill`.
    static let secondaryContainer = Color(.tertiarySystemFill)
    /// The selected row's own paint: the tint's selection fill.
    static let primaryContainer = Color.accentColor.opacity(0.12)
    /// The error fill.
    static let errorContainer = Color.red.opacity(0.12)

    /// The Chumpy card corner — M3 `extraLarge`, 28dp.
    static let cardRadius: CGFloat = 28
    /// The inner group corner — M3 `extraSmall`, 4dp.
    static let innerRadius: CGFloat = 4
}

/// The accent's own storage word — the hex string the root reads and
/// the Interface page's picker writes.
enum ChumpyAccent {
    /// The app's born accent, the Android client's own sky.
    static let defaultHex = "#6FACED"

    /// The stored pick as a color; an unreadable string falls back to
    /// the born accent rather than a wrong one.
    static func color(hex: String) -> Color {
        Color(hex: hex) ?? Color(hex: defaultHex)!
    }

    /// Whether the color reads as light — the word that decides the
    /// ink over the accent: black on light colors, white on dark ones.
    static func isLight(_ color: Color) -> Bool {
        let ui = UIColor(color)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.5
    }
}

extension Color {
    /// A color from a `#RRGGBB` or `RRGGBB` string; nil when the string
    /// isn't one.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6,
              let value = UInt64(text, radix: 16)
        else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The color as `#RRGGBB` — the custom accent's own word back into
    /// the store.
    var hexString: String {
        let ui = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> String {
            String(format: "%02X", Int(round(value * 255)))
        }
        return "#\(channel(red))\(channel(green))\(channel(blue))"
    }
}

// MARK: - Chumpy card
// The tonal card every screen wears: 28dp continuous corners over a
// `surfaceContainer` fill, with the hairline edge the M3 outline keeps.

struct ChumpyCardShape: Shape {
    var radius: CGFloat = Chumpy.cardRadius
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
    }
}

extension View {

    /// The Chumpy card: 28dp continuous corners over the native frosted
    /// material — the blur the platform gives — with a hairline stroke.
    func chumpyCard(radius: CGFloat = Chumpy.cardRadius) -> some View {
        background(.regularMaterial, in: ChumpyCardShape(radius: radius))
            .overlay(
                ChumpyCardShape(radius: radius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
    }

    /// A filled group container piece with per-corner trims — the grouped
    /// server rows' outer 28dp / inner 4dp law.
    func chumpyGroupFill(top: Bool, bottom: Bool) -> some View {
        background(
            UnevenCornerShape(
                topLeft: top ? Chumpy.cardRadius : Chumpy.innerRadius,
                topRight: top ? Chumpy.cardRadius : Chumpy.innerRadius,
                bottomLeft: bottom ? Chumpy.cardRadius : Chumpy.innerRadius,
                bottomRight: bottom ? Chumpy.cardRadius : Chumpy.innerRadius
            )
            .fill(Chumpy.surfaceContainer)
        )
    }
}

/// Rounded rect with per-corner radii wearing the platform's own
/// continuous-corner curve — the exact one the subscription card's
/// shape draws, not a lookalike: on iOS 16+ the path IS the
/// platform's per-corner continuous shape (`UnevenRoundedRectangle`,
/// the same corner machinery `Path(roundedRect:style:.continuous)`
/// runs), so a single-row group's corners are pixel-identical to the
/// card's and the two can never drift apart. iOS 15 keeps the
/// construction Figma reverse-engineered from the iOS squircle: a
/// circular arc at each corner's heart with Bézier shoulders easing
/// the curvature in from the straight edges (smoothing 0.6, the
/// value that matches the platform shape).
struct UnevenCornerShape: Shape {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomLeft: CGFloat
    var bottomRight: CGFloat

    /// Zero is the plain rounded rect; 0.6 is the iOS squircle.
    private static let smoothing: CGFloat = 0.6

    func path(in rect: CGRect) -> Path {
        let half = min(rect.width, rect.height) / 2
        let tl = min(topLeft, half)
        let tr = min(topRight, half)
        let bl = min(bottomLeft, half)
        let br = min(bottomRight, half)

        // The platform's own per-corner continuous curve. Every device
        // this app runs on (iOS 26) takes this branch; the fallback
        // below only covers iOS 15.
        if #available(iOS 16.0, *) {
            return UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: tl,
                    bottomLeading: bl,
                    bottomTrailing: br,
                    topTrailing: tr
                ),
                style: .continuous
            ).path(in: rect)
        }

        // The whole footprint a corner consumes of an edge: its radius
        // plus the smoothing's reach along the straight.
        var pTL = tl * (1 + Self.smoothing)
        var pTR = tr * (1 + Self.smoothing)
        var pBL = bl * (1 + Self.smoothing)
        var pBR = br * (1 + Self.smoothing)
        // Every edge is shared by two corners; when both footprints
        // together outrun the edge, both ease their smoothing off until
        // they exactly meet in the middle — the capsule law.
        share(&pTL, &pTR, rect.width)
        share(&pTR, &pBR, rect.height)
        share(&pBL, &pBR, rect.width)
        share(&pTL, &pBL, rect.height)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + pTL, y: rect.minY))
        corner(&path, apex: CGPoint(x: rect.maxX, y: rect.minY),
               e1: CGPoint(x: 1, y: 0), e2: CGPoint(x: 0, y: 1),
               radius: tr, footprint: pTR)
        corner(&path, apex: CGPoint(x: rect.maxX, y: rect.maxY),
               e1: CGPoint(x: 0, y: 1), e2: CGPoint(x: -1, y: 0),
               radius: br, footprint: pBR)
        corner(&path, apex: CGPoint(x: rect.minX, y: rect.maxY),
               e1: CGPoint(x: -1, y: 0), e2: CGPoint(x: 0, y: -1),
               radius: bl, footprint: pBL)
        corner(&path, apex: CGPoint(x: rect.minX, y: rect.minY),
               e1: CGPoint(x: 0, y: -1), e2: CGPoint(x: 1, y: 0),
               radius: tl, footprint: pTL)
        path.closeSubpath()
        return path
    }

    /// Two corners share one edge; when their footprints together
    /// outrun it, both shrink proportionally to exactly meet.
    private func share(_ a: inout CGFloat, _ b: inout CGFloat, _ length: CGFloat) {
        let total = a + b
        guard total > length, total > 0 else { return }
        a = a * length / total
        b = b * length / total
    }

    /// One corner: the straight edge ends at the footprint short of the
    /// apex, a Bézier shoulder eases into the corner's own arc, and a
    /// second shoulder eases back out to the other edge.
    private func corner(
        _ path: inout Path,
        apex: CGPoint,
        e1: CGPoint,
        e2: CGPoint,
        radius: CGFloat,
        footprint: CGFloat
    ) {
        guard radius > 0 else {
            path.addLine(to: apex)
            return
        }
        let s = max(0, min(Self.smoothing, footprint / radius - 1))
        let r = radius
        let p = r * (1 + s)                    // the edge the corner eats
        let arc = 90 * (1 - s) * .pi / 180     // the arc that remains
        let tilt = 45 * s * .pi / 180           // the shoulders' tilt
        let chord = sin(arc / 2) * r * CGFloat(2).squareRoot() // the arc's span per edge
        let handle = r * tan(tilt / 2)         // the arc joint's handle
        let c = handle * cos(tilt)             // its share along the incoming edge
        let d = handle * sin(tilt)             // its share along the outgoing edge
        let b = (p - chord - c - d) / 3         // the easing, split two to one
        let a = 2 * b

        // The corner in its own frame: the origin where the straight
        // ends, u along the incoming edge, v along the outgoing one.
        let start = CGPoint(x: apex.x - p * e1.x, y: apex.y - p * e1.y)
        func spot(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: start.x + u * e1.x + v * e2.x,
                    y: start.y + u * e1.y + v * e2.y)
        }
        let arcStart = spot(a + b + c, d)
        let arcEnd = spot(a + b + c + chord, d + chord)

        path.addLine(to: start)
        if s > 0.01 {
            path.addCurve(
                to: arcStart,
                control1: spot(a, 0),
                control2: spot(a + b, 0)
            )
        }
        let center = CGPoint(x: apex.x - r * e1.x + r * e2.x,
                             y: apex.y - r * e1.y + r * e2.y)
        let theta = atan2(arcStart.y - center.y, arcStart.x - center.x)
        path.addArc(
            center: center,
            radius: r,
            startAngle: .radians(theta),
            endAngle: .radians(theta + arc),
            clockwise: false
        )
        if s > 0.01 {
            path.addCurve(
                to: spot(a + b + c + chord + d, d + chord + a + b + c),
                control1: spot(a + b + c + chord + d, d + chord + c),
                control2: spot(a + b + c + chord + d, d + chord + b + c)
            )
        }
    }
}

// MARK: - InfoChip
// Ported from the Android client's `InfoChip`: a compact tonal pill of a
// value — icon, optional leading slot, `labelLarge` value text; the few
// chips that answer a tap wear a plain button instead of a padded Surface.

struct InfoChip: View {
    let value: String
    var icon: String?
    var container: Color = Chumpy.surfaceContainerLow
    var content: Color = .primary
    /// The animated value swap (e.g. "…" → the real ping) without animating
    /// the chip itself appearing.
    var animateValue = false
    var action: (() -> Void)?
    var leading: AnyView? = nil

    var body: some View {
        chipContent()
            .padding(.leading, 10)
            .padding(.trailing, 12)
            // One law for every chip's height — the icon'd and the bare
            // ones all stand the same size in a row.
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(container)
            )
            // No border, on any chip: the original's only ring is the
            // focus one (keyboard/controller focus), so a tap alone never
            // earns an outline — the tappable chips used to wear a
            // hairline here and stood out from their plain siblings.
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .modifier(ChipTap(action: action))
    }

    @ViewBuilder
    private func chipContent() -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(content)
            }
            if let leading {
                leading
                Spacer().frame(width: 5)
            }
            if animateValue {
                // The value crossfades on change — the ping chip's "…" swap.
                ZStack {
                    Text(value)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(content)
                        .id(value)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.18), value: value)
            } else {
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(content)
                    .lineLimit(1)
            }
        }
    }
}

/// The tap the tappable chips answer — a plain button so the chip keeps its
/// own height instead of growing to the platform's touch target.
private struct ChipTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            Button(action: {
                Haptics.poke()
                action()
            }) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - FlowStack
// The chips flow in a wrapping row — Compose's FlowRow over the same
// 4dp gaps. On iOS 16+ the Layout protocol walks the row properly; the
// iOS 15 baseline keeps a plain row (the handful of chips still fits).

struct FlowStack<Content: View>: View {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4
    @ViewBuilder var content: () -> Content

    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = 4,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            FlowLayout(alignment: alignment, spacing: spacing) {
                content()
            }
        } else {
            HStack(alignment: .center, spacing: spacing) {
                content()
            }
        }
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    /// The greedy row walk: measured children break to a new line at the
    /// offered width, every line kept whole (`fixedSize` semantics — a chip
    /// never shrinks, the flow wraps instead).
    private func arrange(proposal: ProposedViewSize, subviews: Subviews)
        -> (size: CGSize, positions: [CGPoint])
    {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        // The current row's span, for the centered flow's own even margins.
        var rowStart = 0
        var rowWidth: CGFloat = 0

        func closeRow(until index: Int) {
            guard alignment == .center, rowWidth < maxWidth else { return }
            let inset = (maxWidth - rowWidth) / 2
            for i in rowStart..<index {
                positions[i].x += inset
            }
        }

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                closeRow(until: index)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
                rowStart = index
                rowWidth = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowWidth = x - spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, rowWidth)
        }
        closeRow(until: positions.count)
        // A centered row's inset pushes its chips past the natural
        // width, and SwiftUI would center the already-centered content
        // a second time — the rows would land shifted toward the far
        // edge. The size owns the whole offered width instead, so the
        // insets are the only centering there is.
        if alignment == .center, maxWidth.isFinite {
            width = max(width, maxWidth)
        }
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}

// MARK: - Glass background
// Liquid Glass (iOS 26+) where the platform has it, the frosted material
// (iOS 15+) everywhere else — the baseline look stays native either way.

extension View {

    /// Glass background: Liquid Glass on iOS 26, `.regularMaterial` below.
    /// The `#if compiler` gate keeps the code compiling on pre-Xcode-26
    /// toolchains, where the symbol does not exist yet.
    @ViewBuilder
    func chumpyGlassCard(cornerRadius: CGFloat = 20) -> some View {
        #if compiler(>=6.2)
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
        #else
        background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        #endif
    }

    /// Glass capsule (floating pill bar, chips): Liquid Glass on iOS 26,
    /// `.ultraThinMaterial` below.
    @ViewBuilder
    func chumpyGlassCapsule() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(in: Capsule())
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
        #else
        background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    /// The pill's own edge treatment: Liquid Glass carries its own, the
    /// material capsule needs the hairline stroke and the shadow.
    @ViewBuilder
    func chumpyPillEdge() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self
        } else {
            edgeStrokeAndShadow
        }
        #else
        edgeStrokeAndShadow
        #endif
    }

    private var edgeStrokeAndShadow: some View {
        overlay(
            Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
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

// MARK: - Edge scroll

/// The collapsing header's strip height — the folded title's home. The
/// pages pad their scroll content down by it, so the shell's title has
/// its large resting spot below the strip and the content scrolls
/// under it.
let chumpyHeaderHeight: CGFloat = 44

/// Where the large title rests: just below the strip.
let chumpyTitleRestTop: CGFloat = chumpyHeaderHeight + 8

/// The large title's resting size — the big end of the morph.
let chumpyLargeTitleSize: CGFloat = 34

/// Where the page's scroll content begins: below the strip, past the
/// resting title and its breathing room. The title is a live object in
/// the shell — the content must start under it, not behind it.
let chumpyContentTopPadding: CGFloat = chumpyTitleRestTop + chumpyLargeTitleSize + 12

/// The scroll's word on the frost: whose scroll is speaking, how far
/// the page has traveled, and how much content still waits below the
/// fold. The tag tells the pages apart — the pager keeps every page
/// alive, and the shell heeds only the one it stands on.
struct ScrollMetrics: Equatable {
    var tag: String
    var scrolled: CGFloat = 0
    var belowFold: CGFloat = 0
}

/// The pages' scroll, reported to the shell: every page keeps its own
/// word here, by tag — the system's own geometry word on iOS 18+, a
/// KVO spy on the real UIScrollView below. The shell heeds only the
/// page it stands on, but each one's word outlives the rides between
/// pages, so the frost is at its strength the moment a page arrives,
/// not a beat after.
final class ScrollReporter: ObservableObject {
    static let shared = ScrollReporter()

    /// Every page's word, by its tag.
    @Published private(set) var metricsByTag: [String: ScrollMetrics] = [:]

    func report(_ metrics: ScrollMetrics) {
        guard metricsByTag[metrics.tag] != metrics else { return }
        metricsByTag[metrics.tag] = metrics
    }
}

/// A ScrollView that reports its travel to the shell's reporter. On
/// iOS 18+ the system's own onScrollGeometryChange speaks it — the
/// first-class API, the same word the system's chrome hears. Below
/// that, a spy view inside the content hooks the real UIScrollView and
/// watches its offset — the one source that never lies about the
/// scroll.
struct EdgeScrollView<Content: View>: View {
    /// The page this scroll speaks for — the shell heeds only the
    /// page it stands on.
    let tag: String
    /// The pull-to-refresh ask, when the page has one — the system's
    /// own spinner under the finger's pull.
    var onRefresh: (() async -> Void)? = nil
    /// A plain hold on the shared reporter — the scroll only writes
    /// its word; it never re-renders on the shell's reads.
    private let reporter = ScrollReporter.shared

    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            modernScrollView
        } else {
            legacyScrollView
        }
        #else
        legacyScrollView
        #endif
    }

    /// The system's own word on the scroll, where the system speaks it.
    @available(iOS 18.0, *)
    private var modernScrollView: some View {
        attachRefresh(
            ScrollView {
                content()
            }
            .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
                // A scroll view at rest can sit at a negative offset — its
                // top inset. The inset folds back in, so "scrolled" reads as
                // points traveled from the start, zero-based.
                let scrolled = max(0, geo.contentOffset.y + geo.contentInsets.top)
                return ScrollMetrics(
                    tag: tag,
                    scrolled: scrolled,
                    belowFold: max(0, geo.contentSize.height - scrolled - geo.containerSize.height)
                )
            } action: { _, metrics in
                reporter.report(metrics)
            }
        )
    }

    /// The UIKit spy, for the systems that predate the official word.
    private var legacyScrollView: some View {
        attachRefresh(
            ScrollView {
                content()
                    .background(ScrollOffsetSpy(reporter: reporter, pageTag: tag))
            }
        )
    }

    /// Pull-to-refresh, where the system gives a plain ScrollView one
    /// (iOS 16+); the 15 baseline keeps its plain scroll.
    @ViewBuilder
    private func attachRefresh(_ view: some View) -> some View {
        if #available(iOS 16.0, *), let onRefresh {
            view.refreshable { await onRefresh() }
        } else {
            view
        }
    }
}

/// The spy's door into UIKit: a plain view inside the scroll content
/// that walks up to the UIScrollView hosting it and watches the offset
/// and the content size. GeometryReaders went blind inside SwiftUI's
/// scroll views — the UIScrollView never does.
private struct ScrollOffsetSpy: UIViewRepresentable {
    let reporter: ScrollReporter
    /// Named `pageTag` — a UIView already owns a `tag` of its own.
    let pageTag: String

    func makeUIView(context: Context) -> ScrollOffsetSpyView {
        ScrollOffsetSpyView(reporter: reporter, pageTag: pageTag)
    }

    func updateUIView(_ view: ScrollOffsetSpyView, context: Context) {}
}

private final class ScrollOffsetSpyView: UIView {
    private let reporter: ScrollReporter
    /// Named `pageTag` — a UIView already owns a `tag` of its own.
    private let pageTag: String
    private var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []

    init(reporter: ScrollReporter, pageTag: String) {
        self.reporter = reporter
        self.pageTag = pageTag
        super.init(frame: .zero)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            attachIfNeeded()
        } else {
            observations.removeAll()
            scrollView = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachIfNeeded()
    }

    /// The host chain up from the content leads to the UIScrollView —
    /// retried on every layout until it's there.
    private func attachIfNeeded() {
        guard scrollView == nil, window != nil else { return }
        var candidate: UIView? = superview
        while let view = candidate {
            if let scroll = view as? UIScrollView {
                scrollView = scroll
                observe(scroll)
                return
            }
            candidate = view.superview
        }
    }

    private func observe(_ scroll: UIScrollView) {
        // `.initial` speaks the resting position the moment the page
        // appears; `.new` carries every frame of travel afterwards.
        observations = [
            scroll.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scroll, _ in
                self?.report(scroll)
            },
            scroll.observe(\.contentSize, options: [.initial, .new]) { [weak self] scroll, _ in
                self?.report(scroll)
            },
        ]
    }

    private func report(_ scroll: UIScrollView) {
        // A scroll view at rest can sit at a negative offset — its
        // adjusted top inset. The inset folds back in, so "scrolled"
        // reads as points traveled from the start, zero-based.
        let scrolled = max(0, scroll.contentOffset.y + scroll.adjustedContentInset.top)
        reporter.report(
            ScrollMetrics(
                tag: pageTag,
                scrolled: scrolled,
                belowFold: max(0, scroll.contentSize.height - scrolled - scroll.bounds.height)
            )
        )
    }
}

