import UIKit

extension MainShellViewController {
    /// Applies light / dark / system and persists the choice.
    func applyAppearance(_ rawMode: String) {
        let mode = ["light", "dark"].contains(rawMode) ? rawMode : "system"
        preferences.appearanceMode = mode
        let style = Self.savedAppearanceStyle
        overrideUserInterfaceStyle = style
        view.window?.overrideUserInterfaceStyle = style
        webView.overrideUserInterfaceStyle = style
        applyStoredPalette()
        setNeedsStatusBarAppearanceUpdate()
    }

    static var savedAppearanceStyle: UIUserInterfaceStyle {
        switch ThemePreferences.shared.appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return .unspecified
        }
    }

    /// Re-resolves every stored colour after an appearance change.
    func applyStoredPalette() {
        // Keep solid palette only when no custom background image is active.
        if backgroundImageView.image == nil {
            view.backgroundColor = ThemePalette.stored(.background,
                                                      lightDefault: ThemePalette.lightBackground,
                                                      darkDefault: ThemePalette.darkBackground)
        } else {
            view.backgroundColor = .clear
        }
        nativeHomeHost?.view.backgroundColor = backgroundImageView.image == nil ? view.backgroundColor : .clear
        materialLayer.tintColor = ThemePalette.cardTint
        materialLayer.interfaceStyle = traitCollection.userInterfaceStyle
        refreshHero()
        materialLayer.refreshTint()
        materialLayer.render()
    }

    /// Re-renders the settings hero card (name, version, tier, avatar, colours, font).
    func refreshHero() {
        guard let hero = settingsHero else { return }
        LUIYoRefreshSettingsHero(hero)
        LUIYoSetSettingsHeroFont(hero, fontController.font)
    }

    func setCardMaterialMode(_ rawMode: String) {
        homeModel.useBlur = rawMode == "blur"
        materialLayer.materialMode = rawMode == "blur" ? .blur : .liquid
        materialLayer.refreshEffects()
    }

    /// Applies the theme font to the tab bar, the search overlay, the hero card
    /// and every native control the material layer draws.
    func applyFont(_ font: UIFont?) {
        // Change title fonts only; retain all UIKit Liquid Glass/background settings.
        if let base = defaultTabAppearance?.copy() as? UITabBarAppearance {
            Self.applyFont(font, to: base)
            tabBar.standardAppearance = base
            if let edge = defaultScrollEdgeAppearance?.copy() as? UITabBarAppearance {
                Self.applyFont(font, to: edge)
                tabBar.scrollEdgeAppearance = edge
            }
        }
        for item in tabBar.items ?? [] {
            let attributes: [NSAttributedString.Key: Any]? = font.map { [.font: $0] }
            item.setTitleTextAttributes(attributes, for: .normal)
            item.setTitleTextAttributes(attributes, for: .selected)
        }
        updateTabLabelFonts(in: tabBar)
        activeSearchController?.themeFont = font
        // Apply theme font to the settings hero card (native view).
        if let hero = settingsHero { LUIYoSetSettingsHeroFont(hero, font) }
        materialLayer.themeFont = font
        tabBar.setNeedsLayout()
        // Defer expensive material rendering to avoid stutter during tab switch.
        DispatchQueue.main.async { [weak self] in self?.materialLayer.render() }
    }

    private static func applyFont(_ font: UIFont?, to appearance: UITabBarAppearance) {
        guard let font else { return }
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            var normal = layout.normal.titleTextAttributes
            var selected = layout.selected.titleTextAttributes
            normal[.font] = font
            selected[.font] = font
            layout.normal.titleTextAttributes = normal
            layout.selected.titleTextAttributes = selected
        }
    }

    /// Keeps tab titles at their original size when a decorative font is imported.
    func updateTabLabelFonts(in view: UIView) {
        if let label = view as? UILabel, let text = label.text,
           ["首页", "规则", "设置", "搜索", "Search"].contains(text) {
            if originalTabLabelFonts.object(forKey: label) == nil {
                let original = fontController.font == nil ? label.font! : UIFont.systemFont(ofSize: label.font.pointSize)
                originalTabLabelFonts.setObject(original, forKey: label)
            }
            if let original = originalTabLabelFonts.object(forKey: label) {
                let desired = fontController.font?.withSize(original.pointSize) ?? original
                if label.font != desired { label.font = desired }
            }
        }
        for child in view.subviews { updateTabLabelFonts(in: child) }
    }
}
