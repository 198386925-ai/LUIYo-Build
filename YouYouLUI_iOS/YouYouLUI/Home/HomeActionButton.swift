import SwiftUI
import UIKit

/// Prominent action button (清空 / 导出 ZIP). UIKit owns the glass, the hit
/// target and the pressed state; semantic colours stay fixed.
struct NativeGlassActionButton: UIViewRepresentable {
    var title: String
    var asset: String
    var color: String
    var font: UIFont?
    var useBlur: Bool
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        let tint = UIColor(nativeHex: color)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *), !useBlur {
            configuration = .prominentGlass()
        } else {
            configuration = .plain()
            configuration.background.visualEffect = UIBlurEffect(style: .systemMaterial)
            configuration.background.backgroundColor = tint.withAlphaComponent(0.72)
        }
        configuration.title = title
        if let image = ToolbarAssetImages.template(named: asset) {
            configuration.image = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in
                image.withTintColor(.white, renderingMode: .alwaysOriginal)
                    .draw(in: CGRect(x: 0, y: 0, width: 18, height: 18))
            }.withRenderingMode(.alwaysOriginal)
        }
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = tint
        configuration.baseForegroundColor = .white
        let titleFont = font?.withSize(13) ?? UIFont.systemFont(ofSize: 13, weight: .semibold)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = titleFont
            result.foregroundColor = .white
            return result
        }
        button.tintColor = tint
        button.configuration = configuration
        button.accessibilityLabel = title
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(_ action: @escaping () -> Void) { self.action = action }

        @objc func tap() { action() }
    }
}
