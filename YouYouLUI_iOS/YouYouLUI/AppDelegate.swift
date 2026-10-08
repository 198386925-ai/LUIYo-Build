import UIKit
import Security

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.overrideUserInterfaceStyle = WebViewController.savedAppearanceStyle
        window.backgroundColor = WebViewController.adaptiveBackground
        #if DEBUG && targetEnvironment(simulator)
        if let scenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"] {
            let app = WebViewController()
            app.setAuthorization(scenario != "preview-inline-auth")
            if scenario == "preview-inline-auth" {
                app.onLicenseSubmitted = { [weak app] code in
                    app?.setAuthorization(code == "UI-TEST", message: code == "UI-TEST" ? nil : "测试卡密无效")
                }
            }
            window.rootViewController = app
            window.makeKeyAndVisible()
            self.window = window
            return true
        }
        #endif
        // LUIYO_AUTH_URL is configured ONLY after the PHP backend is deployed.
        // A pre-existing build without this key retains the current app behavior.
        if let endpoint = Bundle.main.object(forInfoDictionaryKey: "LUIYO_AUTH_URL") as? String,
           let url = URL(string: endpoint),
           url.scheme == "https", url.host != nil, url.path.hasSuffix("/api.php") {
            window.rootViewController = LUIYoActivationGate(endpoint: url)
        } else {
            let standalone = WebViewController()
            standalone.setAuthorization(true)
            window.rootViewController = standalone
        }
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

/// Server-backed access gate: never permits use until the backend accepts
/// the stored token (or a newly redeemed activation code).
private final class LUIYoActivationGate: UIViewController {
    private let endpoint: URL
    private var appController: WebViewController?
    private var checkInFlight = false
    private var lastCheck: Date?
    private let timerInterval: TimeInterval = 300

    init(endpoint: URL) { self.endpoint = endpoint; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let app = WebViewController()
        app.setAuthorization(false)
        app.onLicenseSubmitted = { [weak self] code in self?.redeem(code: code) }
        addChild(app)
        app.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(app.view)
        NSLayoutConstraint.activate([
            app.view.topAnchor.constraint(equalTo: view.topAnchor),
            app.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            app.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            app.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        app.didMove(toParent: self)
        appController = app
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        foreground()
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func foreground() {
        guard !checkInFlight else { return }
        guard let token = SecretStore.get("token") else {
            invalidateAccess(message: "请输入激活码以继续使用")
            return
        }
        // Always recheck on foreground, even if previously allowed.
        check(token: token)
    }

    private func url(action: String) -> URL {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "action", value: action)]
        return c.url!
    }

    private func request(action: String, payload: [String: String]?, token: String?, completion: @escaping (Int, [String: String]?, String) -> Void) {
        var request = URLRequest(url: url(action: action), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let payload { request.httpBody = try? JSONSerialization.data(withJSONObject: payload) }
        URLSession.shared.dataTask(with: request) { data, response, error in
            let http = response as? HTTPURLResponse
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let obj = json?.compactMapValues { $0 as? String }
            let code = http?.statusCode ?? 0
            // Show only response type/shape; never expose an authorization token.
            let contentType = http?.value(forHTTPHeaderField: "Content-Type") ?? "missing"
            let diagnostic: String
            if let error { diagnostic = "网络错误：" + error.localizedDescription }
            else if obj == nil { diagnostic = "HTTP " + String(code) + "，服务器未返回 JSON（" + contentType + "）" }
            else { diagnostic = "HTTP " + String(code) + "，返回字段：" + (json?.keys.sorted().joined(separator: ",") ?? "none") }
            DispatchQueue.main.async { completion(code, obj, diagnostic) }
        }.resume()
    }

    private func redeem(code submittedCode: String) {
        let code = submittedCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, !checkInFlight else { return }
        let identifier: String
        if let saved = SecretStore.get("device-id") { identifier = saved }
        else {
            identifier = UUID().uuidString.lowercased()
            SecretStore.put(identifier, key: "device-id")
        }
        checkInFlight = true
        appController?.setAuthorization(false, message: "正在验证激活码…", busy: true)
        request(action: "activate", payload: ["code": code, "device_id": identifier], token: nil) { [weak self] httpCode, data, diagnostic in
            guard let self else { return }
            self.checkInFlight = false
            if httpCode == 200, let token = data?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                self.allowAccess()
            } else {
                self.invalidateAccess(message: httpCode == 0 ? diagnostic : "激活失败：" + (data?["error"] ?? diagnostic))
            }
        }
    }

    private func check(token: String) {
        checkInFlight = true
        // Fail closed on foreground: hide app content until the server answers.
        hideApp()
        appController?.setAuthorization(false, message: "正在验证使用权限…", busy: true)
        request(action: "check", payload: nil, token: token) { [weak self] code, body, diagnostic in
            guard let self else { return }
            self.checkInFlight = false
            if code == 200, body?["status"] == "active" {
                self.allowAccess()
            } else {
                if code == 401 { SecretStore.delete("token") }
                let detail = body?["error"] ?? diagnostic
                self.invalidateAccess(message: code == 403 ? "此账号已被封禁、停用或过期" : (code == 0 ? "暂时无法连接验证服务器，请稍后重试" : "验证失败：" + detail))
            }
        }
    }

    private func allowAccess() {
        lastCheck = Date()
        appController?.setAuthorization(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + timerInterval) { [weak self] in
            guard let self, let checked = self.lastCheck,
                  Date().timeIntervalSince(checked) >= self.timerInterval - 1 else { return }
            self.foreground()
        }
    }

    private func hideApp() {
        appController?.setAuthorization(false)
    }

    private func invalidateAccess(message: String) {
        hideApp()
        appController?.setAuthorization(false, message: message)
    }
}

private enum SecretStore {
    private static let service = "LUIYo.Auth"
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func put(_ value: String, key: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                kSecValueData as String: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }
    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
