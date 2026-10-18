import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = MainShellViewController.savedAppearanceStyle
        window.backgroundColor = ThemePalette.adaptiveBackground
        #if DEBUG && targetEnvironment(simulator)
        if let scenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] {
            // Snapshot/debug runs skip the activation backend entirely.
            let shell = MainShellViewController()
            shell.setAuthorization(scenario != "preview-inline-auth")
            if scenario == "preview-inline-auth" {
                shell.onLicenseSubmitted = { [weak shell] code in
                    shell?.setAuthorization(code == "UI-TEST",
                                            message: code == "UI-TEST" ? nil : "测试卡密无效")
                }
            }
            window.rootViewController = shell
            window.makeKeyAndVisible()
            self.window = window
            return true
        }
        #endif
        window.rootViewController = AppRoot.makeRootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
