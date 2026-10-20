import SwiftUI
import Combine

/// Observable state for the native Settings page.
/// Wraps ThemePreferences (UserDefaults-backed) so the UI stays in sync.
final class SettingsNativeModel: ObservableObject {
    private let prefs = ThemePreferences.shared
    /// Font controller for custom font import. Set by the hosting shell.
    var fontController: ThemeFontController?

    // MARK: - Authorization (pushed by the shell's setAuthorization)
    @Published var isAuthorized: Bool = false
    @Published var authMessage: String = "未激活 · 仅可浏览"
    @Published var authBusy: Bool = false
    /// Bumped when the native hero card should re-render (name/avatar change).
    @Published var heroRefreshToken: Int = 0
    /// Set by hero buttons: which fold to scroll to after expanding.
    @Published var pendingScroll: String?
    var onSubmitLicense: ((String) -> Void)?
    var onEditAvatar: (() -> Void)?
    var onEditName: (() -> Void)?
    var onAppearanceChanged: ((String) -> Void)?
    var onCardMaterialChanged: ((String) -> Void)?
    var onColorsChanged: (() -> Void)?
    var onMinimizeChanged: ((Bool) -> Void)?
    var onBottomSearchLayoutChanged: ((String) -> Void)?
    var onFontChanged: (() -> Void)?

    // MARK: - Appearance
    @Published var appearanceMode: String {
        didSet { prefs.appearanceMode = appearanceMode; onAppearanceChanged?(appearanceMode) }
    }

    // MARK: - Card material
    /// "liquid" or "blur"
    @Published var cardMaterial: String {
        didSet { prefs.cardMaterialMode = cardMaterial; onCardMaterialChanged?(cardMaterial) }
    }

    // MARK: - Colors (hex strings)
    @Published var backgroundColorHex: String = "#F4F2EE"
    @Published var cardColorHex: String = "#FFFFFF"
    @Published var buttonColorHex: String = "#FFFFFF"

    // MARK: - Bottom search
    @Published var bottomSearchLayout: String {
        didSet { prefs.bottomSearchLayout = bottomSearchLayout; onBottomSearchLayoutChanged?(bottomSearchLayout) }
    }

    // MARK: - Minimize bottom bar (TRUE NATIVE Toggle)
    @Published var minimizeBottomBar: Bool {
        didSet { prefs.minimizeBottomBar = minimizeBottomBar; onMinimizeChanged?(minimizeBottomBar) }
    }

    // MARK: - Custom font
    @Published var customFontName: String = "使用默认字体"
    @Published var hasCustomFont: Bool = false

    // MARK: - Section expansion
    @Published var themeExpanded: Bool = true
    @Published var guideExpanded: Bool = false
    @Published var changelogExpanded: Bool = false

    init() {
        self.appearanceMode = prefs.appearanceMode
        self.cardMaterial = prefs.cardMaterialMode
        self.bottomSearchLayout = prefs.bottomSearchLayout
        self.minimizeBottomBar = prefs.minimizeBottomBar
        // Load saved colors for current appearance
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        if let hex = prefs.colorHex(.background, appearance: appearance) {
            self.backgroundColorHex = hex
        }
        if let hex = prefs.colorHex(.heroCardColor, appearance: appearance) {
            self.cardColorHex = hex
        }
        if let hex = prefs.colorHex(.buttonColor, appearance: appearance) {
            self.buttonColorHex = hex
        }
    }

    // MARK: - Color helpers
    func color(for hex: String) -> Color {
        Color(hex: hex) ?? .white
    }

    func resetBackgroundColor() {
        let def = "#F4F2EE"
        backgroundColorHex = def
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(def, kind: .background, appearance: appearance)
        onColorsChanged?()
    }

    func resetCardColor() {
        let def = "#FFFFFF"
        cardColorHex = def
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(def, kind: .heroCardColor, appearance: appearance)
        onColorsChanged?()
    }

    func resetButtonColor() {
        let def = "#FFFFFF"
        buttonColorHex = def
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(def, kind: .buttonColor, appearance: appearance)
    }

    func updateBackgroundColor(_ hex: String) {
        backgroundColorHex = hex
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(hex, kind: .background, appearance: appearance)
        onColorsChanged?()
    }

    func updateCardColor(_ hex: String) {
        cardColorHex = hex
        let appearance = prefs.appearanceMode == "dark" ? "dark" : "light"
        prefs.setColorHex(hex, kind: .heroCardColor, appearance: appearance)
        onColorsChanged?()
    }
}

// MARK: - Color hex helper
extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return nil }
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
