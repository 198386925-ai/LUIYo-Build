import UIKit

/// Hex string <-> UIColor helpers shared by the theme layer, the material
/// renderer and the settings hero card.
enum ColorHex {
    /// Accepts `#RRGGBB` or `RRGGBB`; returns nil for anything else.
    static func parse(_ hex: String) -> UIColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1
        )
    }

    /// Builds a light/dark pair that follows the system appearance.
    static func dynamic(light: String, dark: String) -> UIColor {
        let light = parse(light) ?? .white
        let dark = parse(dark) ?? .black
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }
}

extension UIColor {
    convenience init(nativeHex: String) {
        let value = Int(nativeHex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        self.init(
            red: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255,
            alpha: 1
        )
    }

    var nativeHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
