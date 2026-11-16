import SwiftUI
import UIKit

// MARK: - Edge blur
// A backdrop that blurs for real, its radius ramping along the axis: fully
// clear at the fade end, frosted at the screen edge, sliding smoothly in
// between — the same progressive blur the system's own chrome wears. The
// pages scroll under it and dissolve into the frost, and the bar floats on
// top as its own navigation object.
//
// No public API draws this. A gradient mask on a Material — SwiftUI's or a
// plain CAGradientLayer on the effect view — only fades the finished
// composite over sharp content: the blur dies under the mask and a plain
// translucent gradient is what remains. So the frost rides the platform's
// own private recipe instead: a UIVisualEffectView stays in the tree purely
// as the live backdrop sampler, and the filters its internal backdrop layer
// carries are swapped for CAFilter's "variableBlur", fed a hand-drawn
// gradient mask — the blur radius at every point follows the mask, and
// content really blurs progressively. If the private filter can't be
// reached on some system, the view degrades to the masked material (the
// translucent gradient) rather than to nothing.

struct EdgeBlur: UIViewRepresentable {
    /// The screen edge the blur hugs — and where it is at full strength.
    enum Edge {
        case top
        case bottom
    }

    let edge: Edge

    func makeUIView(context: Context) -> ProgressiveBlurView {
        ProgressiveBlurView(edge: edge)
    }

    func updateUIView(_ view: ProgressiveBlurView, context: Context) {}
}

// MARK: - The blur view

/// The blur itself: full radius at the strong edge, tapering to nothing at
/// the fade end. The UIVisualEffectView inside is kept only as the live
/// backdrop sampler — once in a window, the filter set on its internal
/// backdrop layer is replaced with the system's variable-blur filter,
/// pinned to a gradient mask that ramps the radius point by point.
final class ProgressiveBlurView: UIView {
    private let edge: EdgeBlur.Edge

    /// The blur radius at the strong edge, in points: deep enough to frost
    /// the rows passing under, shallow enough that the fade stays about the
    /// dissolve and not the fuzz.
    private let fullRadius: CGFloat = 12

    /// The backdrop sampler. Its own material paint is stripped once the
    /// variable blur takes over — `.regular`, the one recipe every working
    /// variable blur is built on.
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))

    /// The mask ramp, sized to the band and handed to the blur filter.
    private var rampImage: CGImage?

    /// The effect view's backdrop, held weakly — UIKit rebuilds its
    /// internals at will, and a stale reference must not survive.
    private weak var backdropView: UIView?

    /// The filter currently installed, weakly: if UIKit puts its own set
    /// back on the backdrop layer, ours releases — and the identity check
    /// below sees the swap and reinstalls.
    private weak var installedFilter: NSObject?

    /// Set when the filter must be (re)built: first layout, a new window,
    /// a new ramp, or UIKit having taken the layer back.
    private var needsRebuild = true

    /// The band length the current ramp was built for.
    private var rampLength: Int = 0

    /// The degraded paint, mounted only on systems where the private
    /// filter can't be built: the whole material faded by a gradient mask —
    /// translucent, not blurring, but present.
    private let fallbackMask = CAGradientLayer()

    init(edge: EdgeBlur.Edge) {
        self.edge = edge
        super.init(frame: .zero)

        isUserInteractionEnabled = false
        addSubview(blurView)

        // A lighting change reinstalls Apple's filters on the backdrop —
        // a layout pass must follow to put ours back.
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: ProgressiveBlurView, _: UITraitCollection) in
                self.setNeedsLayout()
            }
        }

        // Reduce Transparency asks for exactly the effect this view is.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reduceTransparencyChanged),
            name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Only needed below iOS 17; declared deprecated to match the superclass
    // and silence the deprecation warning.
    @available(iOS, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #unavailable(iOS 17.0) {
            setNeedsLayout()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        needsRebuild = true
        setNeedsLayout()
    }

    @objc private func reduceTransparencyChanged() {
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        blurView.frame = bounds
        // With Reduce Transparency on, hiding the effect is more honest
        // than a blur the user explicitly asked the system to take away.
        blurView.isHidden = UIAccessibility.isReduceTransparencyEnabled

        guard window != nil, bounds.width > 0, bounds.height > 0 else { return }

        // The fallback mask, if it ever mounts, tracks the band by hand.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fallbackMask.frame = blurView.bounds
        CATransaction.commit()

        let length = Int(bounds.height.rounded(.up))
        if length != rampLength {
            rampLength = length
            rampImage = Self.makeRamp(length: length, edge: edge)
            needsRebuild = true
        }
        installBlurFilter()
    }

    // MARK: - The filter

    /// Puts the variable-blur filter on the effect view's backdrop layer —
    /// or, where it can't be built, the masked-material fallback.
    private func installBlurFilter() {
        // The backdrop is cached weakly and re-looked-up whenever UIKit has
        // rebuilt the internals.
        if backdropView?.superview !== blurView {
            backdropView = Self.internalSubview(of: blurView, called: "backdrop")
        }

        guard needsRebuild || !oursIsInstalled else {
            fadeMaterialPaint(ours: true)
            return
        }
        guard let backdropView, let rampImage else { return }

        guard let filter = Self.makeVariableBlurFilter(mask: rampImage, radius: fullRadius) else {
            mountFallbackMask()
            fadeMaterialPaint(ours: false)
            return
        }

        blurView.layer.mask = nil
        backdropView.layer.filters = [filter]
        // The backdrop's capture resolution. At the default the pass-through
        // end of the ramp shows a coarse, misaligned copy of the content
        // under it — the doubling ghost. The screen's native scale keeps
        // the capture pixel-exact, and the capture reaches the band's whole
        // height, home-indicator strip included.
        backdropView.layer.setValue(window?.screen.scale ?? 1.0, forKey: "scale")
        installedFilter = filter
        needsRebuild = false
        fadeMaterialPaint(ours: true)
    }

    /// Whether the filter on the backdrop layer is still ours — UIKit puts
    /// its own set back on lighting changes and the like.
    private var oursIsInstalled: Bool {
        (backdropView?.layer.filters?.first as? NSObject) === installedFilter
    }

    /// While the variable blur is ours, the material's own paint — tint,
    /// vibrancy, whatever else the system layers on — is a haze over clean
    /// frost: every subview but the backdrop is faded out, and brought
    /// back whenever ours is off.
    private func fadeMaterialPaint(ours: Bool) {
        for subview in blurView.subviews where subview !== backdropView {
            subview.alpha = ours ? 0 : 1
        }
    }

    /// The degraded paint. Retried only when a new window or a trait change
    /// asks for a layout anyway.
    private func mountFallbackMask() {
        needsRebuild = false
        guard blurView.layer.mask == nil else { return }

        // White at the strong edge, clear at the fade end — the mask keeps
        // what survives of the composite.
        fallbackMask.colors = [UIColor.clear.cgColor, UIColor.white.cgColor]
        switch edge {
        case .top:
            fallbackMask.startPoint = CGPoint(x: 0.5, y: 1)
            fallbackMask.endPoint = CGPoint(x: 0.5, y: 0)
        case .bottom:
            fallbackMask.startPoint = CGPoint(x: 0.5, y: 0)
            fallbackMask.endPoint = CGPoint(x: 0.5, y: 1)
        }
        blurView.layer.mask = fallbackMask
    }

    // MARK: - The system's filters

    /// The system's filter factory, discovered once from a throwaway effect
    /// view. A nil discovery leaves it unset, and the next pass retries.
    private static var filterFactory: ((String) -> NSObject?)?

    /// Builds CAFilter's "variableBlur" — the filter the platform's own
    /// progressive blurs are made of. CAFilter is not public, but a live
    /// backdrop hands out its class, and the class builds new filters by
    /// name.
    private static func makeVariableBlurFilter(mask: CGImage, radius: CGFloat) -> NSObject? {
        if filterFactory == nil {
            discoverFilterFactory()
        }
        guard let filter = filterFactory?("variableBlur") else { return nil }

        // The ramp drives the radius point by point; the edges are
        // normalized so the band's borders don't darken.
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    private static func discoverFilterFactory() {
        // A throwaway effect view carries the filters already, window or
        // not — its backdrop layer is enough to learn the class.
        let probe = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        guard let backdrop = internalSubview(of: probe, called: "backdrop"),
              let filter = backdrop.layer.filters?.first as? NSObject else { return }

        let filterClass = type(of: filter)
        let build = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: build) else { return }

        filterFactory = { name in
            (filterClass as AnyObject).perform(build, with: name)?.takeUnretainedValue() as? NSObject
        }
    }

    /// The internal subview whose class name contains the given string —
    /// the names change between systems, the search survives the renames.
    private static func internalSubview(of view: UIView, called name: String) -> UIView? {
        let lowercased = name.lowercased()
        return view.subviews.first {
            NSStringFromClass(type(of: $0)).lowercased().contains(lowercased)
        }
    }

    // MARK: - The ramp

    /// A one-pixel-wide strip, one pixel per band point: black at alpha 0
    /// where the blur must vanish, at alpha 255 where it is full. The
    /// variable-blur filter reads it per pixel as the blur amount. Row 0
    /// renders at the band's top.
    private static func makeRamp(length: Int, edge: EdgeBlur.Edge) -> CGImage? {
        guard length > 1 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: 1,
            height: length,
            bitsPerComponent: 8,
            bytesPerRow: 2,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let buffer = context.data else { return nil }

        let pixels = buffer.assumingMemoryBound(to: UInt8.self)
        for row in 0..<length {
            let position = CGFloat(row) / CGFloat(length - 1)
            // A straight ramp: the radius slides evenly along the band, and
            // the dissolve carries the smoothness.
            let amount = edge == .top ? 1 - position : position
            pixels[row * 2] = 0
            pixels[row * 2 + 1] = UInt8(max(0, min(255, amount * 255)))
        }
        return context.makeImage()
    }
}
