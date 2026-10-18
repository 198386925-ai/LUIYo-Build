import UIKit

/// Resolves stored preferences into the dynamic colours the native shells paint.
enum ThemePalette {
    static let lightBackground = "#F2F2F7"
    static let darkBackground = "#121214"
    static let lightCard = "#FFFFFF"
    static let darkCard = "#1C1C1E"

    /// Background used by every page before any custom colour is applied.
    static let adaptiveBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 18.0 / 255.0, green: 18.0 / 255.0, blue: 20.0 / 255.0, alpha: 1)
            : UIColor(red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0, alpha: 1)
    }

    /// A stored light/dark pair, falling back to the supplied defaults.
    static func stored(_ kind: ThemeColorKind, lightDefault: String, darkDefault: String) -> UIColor {
        let defaults = ThemePreferences.shared
        let light = ColorHex.parse(defaults.colorHex(kind, appearance: "light") ?? lightDefault) ?? .white
        let dark = ColorHex.parse(defaults.colorHex(kind, appearance: "dark") ?? darkDefault) ?? .black
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    /// Fill applied to card materials when the platform paints the surface itself.
    static let cardTint = UIColor { $0.userInterfaceStyle == .dark ? UIColor(nativeHex: darkCard) : .white }

    /// Per-appearance stored hex, or nil when the user never customised it.
    static func storedCardHex(isDark: Bool) -> String {
        ThemePreferences.shared.colorHex(.heroCardColor, appearance: isDark ? "dark" : "light")
            ?? (isDark ? darkCard : lightCard)
    }
}
