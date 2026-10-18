import UIKit

/// A material surface that lets UIKit own the optics: iOS 26+ Liquid Glass via
/// corner configuration, older systems via a rounded blur layer.
final class NativeMaterialView: UIVisualEffectView {
    /// Cached signature so the effect is only rebuilt when tint or mode change.
    var materialSignature = ""
    var shapeRadius: CGFloat = 20

    private var appliedRadius: CGFloat = -1
    private var appliedGlassMode = false

    override func layoutSubviews() {
        super.layoutSubviews()
        removeExtraLayerShadows(layer)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let radius = shapeRadius < 0 ? bounds.height / 2 : min(shapeRadius, bounds.height / 2)
        if #available(iOS 26.0, *), effect is UIGlassEffect {
            // Let UIKit generate the optical rounded edge; never crop its layers.
            clipsToBounds = false
            if abs(appliedRadius - radius) > 0.1 || !appliedGlassMode {
                cornerConfiguration = .uniformCorners(radius: .fixed(Double(radius)))
            }
            appliedGlassMode = true
        } else {
            clipsToBounds = true
            layer.cornerCurve = .continuous
            layer.cornerRadius = radius
            appliedGlassMode = false
        }
        appliedRadius = radius
    }
}
