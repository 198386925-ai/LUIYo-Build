import Foundation

/// Colour slot persisted per appearance. The raw strings are part of the
/// contract: the bundled HTML and the ObjC hero cell read them directly.
enum ThemeColorKind: String {
    case background
    case buttonColor
    case heroCardColor
}

/// Every `UserDefaults` key the app owns. Never inline a literal elsewhere.
enum PreferenceKey {
    static let appearanceMode = "youyou.appearanceMode"
    static let bottomSearchEnabled = "youyou.bottomSearchEnabled"
    static let bottomSearchLayout = "youyou.bottomSearchLayout"
    static let minimizeBottomBar = "youyou.minimizeBottomBar"
    static let heroName = "youyou.hero.name"
    static let deviceCode = "youyou.device.code"
    static let authTier = "youyou.auth.tier"
    static let nativeIconColors = "luiyo.nativeIconColors"

    static func color(_ kind: ThemeColorKind, appearance: String) -> String {
        "youyou." + kind.rawValue + "." + appearance
    }

    /// Keys the CI layout report samples verbatim. Kept separate from the
    /// write keys on purpose — they are diagnostics only.
    static func diagnosticsColor(_ slot: String, appearance: String) -> String {
        "youyou." + slot + "." + appearance
    }
}

extension Notification.Name {
    static let luiyoDeviceCodeUpdated = Notification.Name("LUIYoDeviceCodeUpdated")
    static let luiyoTierUpdated = Notification.Name("LUIYoTierUpdated")
}

/// Typed access to persisted preferences. Also broadcasts backend-driven
/// device-code / tier changes so the settings hero card can refresh.
final class ThemePreferences {
    static let shared = ThemePreferences()

    private let defaults = UserDefaults.standard

    func registerDefaults() {
        defaults.register(defaults: [
            PreferenceKey.bottomSearchEnabled: true,
            PreferenceKey.bottomSearchLayout: "separate"
        ])
    }

    var appearanceMode: String {
        get { defaults.string(forKey: PreferenceKey.appearanceMode) ?? "system" }
        set { defaults.set(newValue, forKey: PreferenceKey.appearanceMode) }
    }

    var bottomSearchEnabled: Bool {
        get { defaults.bool(forKey: PreferenceKey.bottomSearchEnabled) }
        set { defaults.set(newValue, forKey: PreferenceKey.bottomSearchEnabled) }
    }

    var bottomSearchLayout: String {
        get { defaults.string(forKey: PreferenceKey.bottomSearchLayout) ?? "separate" }
        set { defaults.set(newValue, forKey: PreferenceKey.bottomSearchLayout) }
    }

    var isSeparateSearch: Bool {
        get { bottomSearchLayout == "separate" }
        set { bottomSearchLayout = newValue ? "separate" : "merged" }
    }

    var minimizeBottomBar: Bool {
        get { defaults.bool(forKey: PreferenceKey.minimizeBottomBar) }
        set { defaults.set(newValue, forKey: PreferenceKey.minimizeBottomBar) }
    }

    var heroName: String {
        get { defaults.string(forKey: PreferenceKey.heroName) ?? "LUIYo" }
        set { defaults.set(newValue, forKey: PreferenceKey.heroName) }
    }

    /// Device code assigned by the backend; rendered by the hero cell.
    var deviceCode: String? {
        get { defaults.string(forKey: PreferenceKey.deviceCode) }
        set {
            guard newValue != deviceCode, let value = newValue else { return }
            defaults.set(value, forKey: PreferenceKey.deviceCode)
            NotificationCenter.default.post(name: .luiyoDeviceCodeUpdated, object: value)
        }
    }

    /// Membership level: `free`, `vip` or `svip` (lowercase — the hero cell expects that).
    var authTier: String? {
        get { defaults.string(forKey: PreferenceKey.authTier) }
        set {
            guard newValue != authTier, let value = newValue else { return }
            defaults.set(value, forKey: PreferenceKey.authTier)
            NotificationCenter.default.post(name: .luiyoTierUpdated, object: value)
        }
    }

    var nativeIconColors: [String: Any] {
        get { defaults.dictionary(forKey: PreferenceKey.nativeIconColors) ?? [:] }
        set { defaults.set(newValue, forKey: PreferenceKey.nativeIconColors) }
    }

    func colorHex(_ kind: ThemeColorKind, appearance: String) -> String? {
        defaults.string(forKey: PreferenceKey.color(kind, appearance: appearance))
    }

    func setColorHex(_ hex: String, kind: ThemeColorKind, appearance: String) {
        defaults.set(hex, forKey: PreferenceKey.color(kind, appearance: appearance))
    }
}
