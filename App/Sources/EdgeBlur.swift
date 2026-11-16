import SwiftUI
import UIKit

// MARK: - Edge blur
// A backdrop that blurs for real, fading along its axis: fully clear at one
// end, fully blurred at the other, with a smooth gradient between. The
// pages scroll under it and dissolve into the blur — and the bar floats on
// top as its own navigation object.
//
// SwiftUI's own `.mask` on a Material flattens it into a plain translucent
// gradient (no real blur under the fade), so the mask has to sit on the
// UIKit layer, where the composited backdrop clips correctly.

struct EdgeBlur: UIViewRepresentable {
    /// The screen edge the blur hugs — and where it is at full strength.
    enum Edge {
        case top
        case bottom
    }

    let edge: Edge

    func makeUIView(context: Context) -> FadeBlurView {
        FadeBlurView(edge: edge)
    }

    func updateUIView(_ view: FadeBlurView, context: Context) {}
}

/// A system blur view masked by a gradient layer: clear at the fade edge,
/// opaque at the strong edge, so the backdrop dissolves in and out.
final class FadeBlurView: UIVisualEffectView {
    private let gradient = CAGradientLayer()
    private let edge: EdgeBlur.Edge

    init(edge: EdgeBlur.Edge) {
        self.edge = edge
        super.init(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        isUserInteractionEnabled = false

        gradient.colors = [UIColor.clear.cgColor, UIColor.white.cgColor]
        switch edge {
        case .top:
            // Opaque at the very top, dissolving down.
            gradient.startPoint = CGPoint(x: 0.5, y: 1)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
        case .bottom:
            // Opaque at the very bottom, dissolving up.
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
        layer.mask = gradient
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}
