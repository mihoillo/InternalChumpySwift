import SwiftUI
import UIKit

// MARK: - Accent color
// The actual tint color lives in Assets.xcassets (AccentColor).
// `Chumpy.accent` makes it easy to reference in code.

enum Chumpy {
    static let accent = Color("AccentColor")

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

    /// The Chumpy tonal card: 28dp continuous corners, `surfaceContainer`
    /// tone, a hairline stroke.
    func chumpyCard(radius: CGFloat = Chumpy.cardRadius) -> some View {
        background(
            ChumpyCardShape().fill(Chumpy.surfaceContainer)
        )
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

/// Rounded rect with per-corner radii, continuous where the platform allows.
struct UnevenCornerShape: Shape {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomLeft: CGFloat
    var bottomRight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minDimension = min(rect.width, rect.height)
        let tl = min(topLeft, minDimension / 2)
        let tr = min(topRight, minDimension / 2)
        let bl = min(bottomLeft, minDimension / 2)
        let br = min(bottomRight, minDimension / 2)

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
            radius: tr,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(
            center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
            radius: br,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
            radius: bl,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(
            center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
            radius: tl,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
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
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(container)
            )
            .overlay {
                if action != nil {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                }
            }
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
            Button(action: action) { content }
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
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
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

/// The scroll's word on the frost: whose scroll is speaking, how far
/// the page has traveled, and how much content still waits below the
/// fold. The tag tells the pages apart — the pager keeps every page
/// alive, and the shell heeds only the one it stands on.
struct ScrollMetrics: Equatable {
    var tag: String
    var scrolled: CGFloat = 0
    var belowFold: CGFloat = 0
}

/// The live page's scroll, reported to the shell. The pages'
/// EdgeScrollViews write here — the system's own geometry word on
/// iOS 18+, a KVO spy on the real UIScrollView below. A singleton:
/// the app has one shell, one live page at a time.
final class ScrollReporter: ObservableObject {
    static let shared = ScrollReporter()

    @Published var metrics = ScrollMetrics(tag: "")
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
    @ObservedObject private var reporter = ScrollReporter.shared

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
            reporter.metrics = metrics
        }
    }

    /// The UIKit spy, for the systems that predate the official word.
    private var legacyScrollView: some View {
        ScrollView {
            content()
                .background(ScrollOffsetSpy(reporter: reporter, pageTag: tag))
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
        reporter.metrics = ScrollMetrics(
            tag: pageTag,
            scrolled: scrolled,
            belowFold: max(0, scroll.contentSize.height - scrolled - scroll.bounds.height)
        )
    }
}

