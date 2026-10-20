import SwiftUI
import UIKit

// MARK: - Environment

private struct NativeUseBlurKey: EnvironmentKey { static let defaultValue = false }
private struct NativeHomeThemeKey: EnvironmentKey { static let defaultValue = NativeHomeTheme() }

extension EnvironmentValues {
    var nativeUseBlur: Bool {
        get { self[NativeUseBlurKey.self] }
        set { self[NativeUseBlurKey.self] = newValue }
    }

    var nativeHomeTheme: NativeHomeTheme {
        get { self[NativeHomeThemeKey.self] }
        set { self[NativeHomeThemeKey.self] = newValue }
    }
}

/// Keeps SF Symbols at a stable size when a decorative text font is imported.
struct NativeAlignedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.icon.font(.system(size: 18)).frame(width: 20, height: 20)
            configuration.title
        }
    }
}

/// Transparent container — the surfaces inside provide their own material.
struct NativeGlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

// MARK: - Surfaces

struct NativeCardSurface: ViewModifier {
    @Environment(\.nativeUseBlur) private var useBlur
    @Environment(\.nativeHomeTheme) private var theme

    func body(content: Content) -> some View {
        content.background(
            NativeMaterialSurface(useBlur: useBlur, tint: UIColor(nativeHex: theme.card), opacity: 1, radius: 20)
        )
    }
}

/// Native iOS 26+ Liquid Glass for the inline search field — no custom drawing.
struct NativeSearchGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.modifier(NativeCardSurface()).clipShape(Capsule())
        }
    }
}

struct NativeMaterialSurface: UIViewRepresentable {
    var useBlur: Bool
    var tint: UIColor
    var opacity: Double
    var radius: CGFloat

    func makeUIView(context: Context) -> NativeMaterialView {
        let view = NativeMaterialView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: NativeMaterialView, context: Context) {
        view.shapeRadius = radius
        var blur = useBlur
        if #available(iOS 26.0, *) {} else { blur = true }
        let signature = "\(blur)|\(tint.nativeHex)"
        if signature != view.materialSignature {
            view.materialSignature = signature
            if #available(iOS 26.0, *), !blur {
                let glass = UIGlassEffect(style: .regular)
                if tint.nativeHex.uppercased() != "#FFFFFF" { glass.tintColor = tint.withAlphaComponent(0.12) }
                glass.isInteractive = true
                view.effect = glass
            } else {
                view.effect = UIBlurEffect(style: .systemMaterial)
            }
            view.contentView.backgroundColor = blur ? tint.withAlphaComponent(0.24) : .clear
        }
        view.alpha = CGFloat(opacity)
        view.setNeedsLayout()
    }
}

// MARK: - Action styling

/// UIKit renders the material; only its native tint and background opacity change.
struct NativeActionStyle: ViewModifier {
    @Environment(\.nativeUseBlur) private var useBlur
    @Environment(\.nativeHomeTheme) private var theme

    func body(content: Content) -> some View {
        let color = UIColor(nativeHex: theme.button)
        let text = theme.customButton ? Color.primary : Color.blue
        return content.buttonStyle(
            NativeHomeActionButtonStyle(useBlur: useBlur, tint: color, text: text, opacity: theme.toolbarOpacity)
        )
    }
}

struct NativeHomeActionButtonStyle: ButtonStyle {
    var useBlur: Bool
    var tint: UIColor
    var text: Color
    var opacity: Double

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(NativeMaterialSurface(useBlur: useBlur, tint: tint, opacity: opacity, radius: -1))
            .contentShape(Capsule())
    }
}

// MARK: - Static page-card surface (pre-migration material-layer recipe)

/// A UIVisualEffectView configured exactly like the shell's CardMaterialLayer
/// surfaces: iOS 26 UIGlassEffect in its STATIC form (never interactive —
/// interactive glass adds a specular highlight meant for buttons), shaped by
/// cornerConfiguration; UIBlurEffect + 24% tint on older systems / blur mode.
final class StaticGlassSurfaceView: UIVisualEffectView {
    var glassRadius: CGFloat = 22
    private var appliedSignature = ""

    func configure(useBlur: Bool, tint: UIColor) {
        var blur = useBlur
        if #available(iOS 26.0, *) {} else { blur = true }
        let signature = "\(blur)|\(tint.nativeHex)|\(glassRadius)"
        guard signature != appliedSignature else { return }
        appliedSignature = signature
        if #available(iOS 26.0, *), !blur {
            let glass = UIGlassEffect(style: .regular)
            let hex = tint.nativeHex.uppercased()
            if !["#FFFFFF", "#1C1C1E"].contains(hex) { glass.tintColor = tint.withAlphaComponent(0.12) }
            effect = glass
            contentView.backgroundColor = .clear
        } else {
            effect = UIBlurEffect(style: .systemMaterial)
            contentView.backgroundColor = tint.withAlphaComponent(0.24)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        layer.cornerRadius = min(glassRadius, min(bounds.width, bounds.height) / 2)
        if #available(iOS 26.0, *), effect is UIGlassEffect {
            cornerConfiguration = .uniformCorners(radius: .fixed(Double(layer.cornerRadius)))
            clipsToBounds = false
        } else {
            clipsToBounds = true
        }
    }
}

struct StaticGlassSurface: UIViewRepresentable {
    var useBlur: Bool
    var tint: UIColor
    var radius: CGFloat

    func makeUIView(context: Context) -> StaticGlassSurfaceView {
        let view = StaticGlassSurfaceView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: StaticGlassSurfaceView, context: Context) {
        view.glassRadius = radius
        view.configure(useBlur: useBlur, tint: tint)
    }
}

/// Card surface for full-width page cards (rules / settings), matching the
/// surfaces the Web UI floated over: static native glass, theme card tint.
struct NativePageCardSurface: ViewModifier {
    var radius: CGFloat = 22
    @Environment(\.nativeUseBlur) private var useBlur
    @Environment(\.nativeHomeTheme) private var theme

    func body(content: Content) -> some View {
        content.background(
            StaticGlassSurface(useBlur: useBlur, tint: UIColor(nativeHex: theme.card), radius: radius)
        )
    }
}
