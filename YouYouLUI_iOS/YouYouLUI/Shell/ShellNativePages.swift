import SwiftUI
import UIKit
import ObjectiveC

/// Native page models + hosts for the SwiftUI Settings and Rules pages.
/// Route A (2026-10-20): the visible Rules/Settings pages are native; the
/// Web engine keeps running hidden under the homepage. Hosts are seated
/// per-tab by ShellWebPlacement.keepContentBelowNativeBar().
extension MainShellViewController {
    /// The shared Settings model, created once and wired to the shell.
    var settingsModel: SettingsNativeModel {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.settingsModel) as? SettingsNativeModel {
            return existing
        }
        let model = SettingsNativeModel()
        model.fontController = self.fontController
        if let font = self.fontController.font {
            model.hasCustomFont = true
            model.customFontName = "已导入自定义字体"
        }
        model.isAuthorized = isAuthorized
        model.authMessage = authorizationMessage
        model.authBusy = authorizationBusy
        model.onSubmitLicense = { [weak self] code in self?.onLicenseSubmitted?(code) }
        model.onEditAvatar = { [weak self] in self?.editHeroAvatar() }
        model.onEditName = { [weak self] in self?.editHeroName() }
        model.onAppearanceChanged = { [weak self] mode in self?.applyAppearance(mode) }
        model.onCardMaterialChanged = { [weak self] mode in self?.setCardMaterialMode(mode) }
        model.onColorsChanged = { [weak self] in self?.applyStoredPalette() }
        model.onMinimizeChanged = { [weak self] enabled in self?.setScrollMinimize(enabled) }
        model.onBottomSearchLayoutChanged = { [weak self] layout in
            guard let self else { return }
            let enabled = layout != "off"
            let separate = layout == "separate"
            if enabled != self.bottomSearchEnabled || separate != self.separateSearch {
                self.bottomSearchEnabled = enabled
                self.separateSearch = separate
                self.preferences.bottomSearchEnabled = enabled
                self.preferences.isSeparateSearch = separate
                UIView.performWithoutAnimation { self.refreshTabItems() }
            }
        }
        model.onFontChanged = { [weak self] in
            guard let self else { return }
            self.homeModel.fontName = self.fontController.font?.fontName
            self.homeModel.importedFont = self.fontController.font
            FontSchemeHandlerStore.shared.handler?.fontData = self.fontController.savedFontData
            self.applyFont(self.fontController.font)
        }
        objc_setAssociatedObject(self, &AssociatedKeys.settingsModel, model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return model
    }

    /// The shared Rules model (the shell's bottom search writes its query).
    var rulesModel: RulesNativeModel {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.rulesModel) as? RulesNativeModel {
            return existing
        }
        let model = RulesNativeModel()
        objc_setAssociatedObject(self, &AssociatedKeys.rulesModel, model, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return model
    }

    /// Returns the hosting controller for the Settings page, creating it once.
    var settingsHost: UIHostingController<SettingsNativeView> {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.settingsHost) as? UIHostingController<SettingsNativeView> {
            return existing
        }
        let controller = UIHostingController(rootView: SettingsNativeView(model: settingsModel, homeModel: homeModel))
        controller.view.backgroundColor = .clear
        objc_setAssociatedObject(self, &AssociatedKeys.settingsHost, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    /// Returns the hosting controller for the Rules page, creating it once.
    var rulesHost: UIHostingController<RulesNativeView> {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.rulesHost) as? UIHostingController<RulesNativeView> {
            return existing
        }
        let controller = UIHostingController(rootView: RulesNativeView(model: rulesModel, homeModel: homeModel))
        controller.view.backgroundColor = .clear
        objc_setAssociatedObject(self, &AssociatedKeys.rulesHost, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    /// Pushes the shell's current authorization state into the native
    /// Settings model (called from setAuthorization).
    func syncNativeSettingsAuth() {
        guard let model = objc_getAssociatedObject(self, &AssociatedKeys.settingsModel) as? SettingsNativeModel else { return }
        model.isAuthorized = isAuthorized
        model.authMessage = authorizationMessage
        model.authBusy = authorizationBusy
    }

    /// Re-renders the native hero card after name/avatar changes.
    func notifyHeroNeedsRefresh() {
        guard let model = objc_getAssociatedObject(self, &AssociatedKeys.settingsModel) as? SettingsNativeModel else { return }
        model.heroRefreshToken += 1
    }
}

/// Associated object keys for the native page hosts and models.
private enum AssociatedKeys {
    static var settingsHost = "settingsHost"
    static var rulesHost = "rulesHost"
    static var settingsModel = "settingsModel"
    static var rulesModel = "rulesModel"
}
