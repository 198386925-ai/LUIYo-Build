import UIKit

/// Chooses the root controller: gated behind the backend when configured,
/// otherwise the standalone (always authorized) app.
enum AppRoot {
    static func makeRootViewController() -> UIViewController {
        guard let endpoint = AppConfiguration.authorizationEndpoint else {
            let standalone = MainShellViewController()
            standalone.setAuthorization(true)
            return standalone
        }
        return ActivationGateViewController(endpoint: endpoint)
    }
}
