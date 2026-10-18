import UIKit

/// Drops decorative CALayer shadows without touching UIKit's own effect
/// sublayers, so Liquid Glass / blur keeps rendering its optics.
func removeExtraLayerShadows(_ layer: CALayer) {
    if layer.shadowOpacity != 0 { layer.shadowOpacity = 0 }
    if layer.shadowRadius != 0 { layer.shadowRadius = 0 }
    if layer.shadowPath != nil { layer.shadowPath = nil }
}
