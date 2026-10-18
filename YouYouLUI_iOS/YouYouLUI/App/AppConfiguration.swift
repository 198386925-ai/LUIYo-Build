import Foundation

/// Compile-time configuration read from the bundle.
enum AppConfiguration {
    /// `LUIYO_AUTH_URL` is configured only after the PHP backend is deployed.
    /// A build without this key keeps the standalone (always authorized) behaviour.
    static var authorizationEndpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "LUIYO_AUTH_URL") as? String,
              let url = URL(string: raw),
              url.scheme == "https", url.host != nil, url.path.hasSuffix("/api.php") else { return nil }
        return url
    }

    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
    }
}
