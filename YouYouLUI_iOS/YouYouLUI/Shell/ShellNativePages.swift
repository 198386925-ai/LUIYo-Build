import SwiftUI
import UIKit
import ObjectiveC

/// Native page hosts for the rewritten Settings and Rules.
/// Follows the same pattern as nativeHomeHost: UIHostingControllers whose
/// views are shown/hidden based on the active page. No WebView involved.
extension MainShellViewController {
    /// Returns the hosting controller for the Settings page, creating it once.
    var settingsHost: UIHostingController<SettingsNativeView> {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.settingsHost) as? UIHostingController<SettingsNativeView> {
            return existing
        }
        // Create model and inject the font controller
        let model = SettingsNativeModel()
        model.fontController = self.fontController
        // Sync initial font state
        if let font = self.fontController.font {
            model.hasCustomFont = true
            // Font name is not persisted, use generic label
            model.customFontName = "已导入自定义字体"
        }
        let settingsView = SettingsNativeView(model: model)
        let controller = UIHostingController(rootView: settingsView)
        controller.view.backgroundColor = .clear
        objc_setAssociatedObject(self, &AssociatedKeys.settingsHost, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    /// Returns the hosting controller for the Rules page, creating it once.
    var rulesHost: UIHostingController<RulesNativeView> {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.rulesHost) as? UIHostingController<RulesNativeView> {
            return existing
        }
        let controller = UIHostingController(rootView: RulesNativeView())
        controller.view.backgroundColor = .clear
        objc_setAssociatedObject(self, &AssociatedKeys.rulesHost, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return controller
    }

    /// Seats the native Settings and Rules views in the tab controller's view.
    /// Called from keepContentBelowNativeBar() or selectPage().
    func updateNativePageVisibility() {
        guard isViewLoaded else { return }

        // Ensure hosts are added as children
        for host in [settingsHost as UIViewController, rulesHost as UIViewController] {
            if host.parent == nil {
                addChild(host)
                view.addSubview(host.view)
                host.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                    host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
                ])
                host.didMove(toParent: self)
            }
        }

        // Show/hide based on active page
        // Home is handled by nativeHomeHost in ShellWebPlacement
        settingsHost.view.isHidden = (activePage != .settings)
        rulesHost.view.isHidden = (activePage != .rules)
        settingsHost.view.accessibilityElementsHidden = (activePage != .settings)
        rulesHost.view.accessibilityElementsHidden = (activePage != .rules)

        // Bring the active native page to front
        if activePage == .settings {
            view.bringSubviewToFront(settingsHost.view)
        } else if activePage == .rules {
            view.bringSubviewToFront(rulesHost.view)
        }
    }
}

/// Associated object keys for the native page hosts.
private enum AssociatedKeys {
    static var settingsHost = "settingsHost"
    static var rulesHost = "rulesHost"
}
