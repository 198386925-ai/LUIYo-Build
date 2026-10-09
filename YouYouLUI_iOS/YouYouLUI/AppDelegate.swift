import UIKit
import Security
import Darwin

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
    private var presenceTimer: Timer?
    private var presenceInFlight = false
    private var registrationReady = false
    private var registrationFailure = ""
    private var currentPage = "home"
    private var verifiedUDID = false
    private var udidEnrollmentPending = false
    private var udidStatusInFlight = false
    private var udidPollTimer: Timer?
    private var deviceIdentifier: String {
        if let saved = SecretStore.get("device-id") { return saved }
        let value = UUID().uuidString.lowercased()
        SecretStore.put(value, key: "device-id")
        return value
    }
    private var registrationSecret: String {
        if let saved = SecretStore.get("registration-secret") { return saved }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        SecretStore.put(value, key: "registration-secret")
        return value
    }

    init(endpoint: URL) { self.endpoint = endpoint; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let app = WebViewController()
        app.setAuthorization(false)
        app.onLicenseSubmitted = { [weak self] code in self?.redeem(code: code) }
        app.onUDIDRequested = { [weak self] in self?.beginUDIDEnrollment() }
        app.onPageChanged = { [weak self] page in self?.currentPage = page }
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
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard UIApplication.shared.applicationState == .active else { return }
            self?.sendPresence()
        }
        udidPollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            guard let self, self.udidEnrollmentPending, UIApplication.shared.applicationState == .active else { return }
            self.refreshUDIDStatus()
        }
        foreground()
    }
    deinit { presenceTimer?.invalidate(); udidPollTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    @objc private func foreground() {
        sendPresence()
        refreshUDIDStatus()
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

    private func beginUDIDEnrollment() {
        udidEnrollmentPending = true
        guard registrationSecret.count == 64 else {
            appController?.setUDIDState("设备登记信息初始化失败，请重新打开 APP", verified: false)
            return
        }
        guard registrationReady else {
            appController?.setUDIDState(registrationFailure.isEmpty ? "正在登记设备，请稍候…" : "设备登记失败：" + registrationFailure, verified: false)
            sendPresence()
            return
        }
        appController?.setUDIDState("正在创建设备识别请求…", verified: false)
        request(action: "udid-start", payload: [:], token: registrationSecret) { [weak self] code, body, diagnostic in
            guard let self else { return }
            guard code == 200, let address = body?["profile_url"], let url = URL(string: address),
                  url.scheme == "https", url.host == self.endpoint.host,
                  url.path.hasSuffix("/profile.php") else {
                self.appController?.setUDIDState(code == 404 ? "服务器尚未部署 UDID 接口，请先更新后台授权服务" : "无法开始设备识别：" + (body?["error"] ?? diagnostic), verified: false)
                return
            }
            self.appController?.setUDIDState("请在 Safari 下载并安装设备识别描述文件，完成后返回 APP", verified: false)
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                if !opened { self?.appController?.setUDIDState("Safari 打开失败，请检查系统浏览器设置", verified: false) }
            }
        }
    }

    private func refreshUDIDStatus() {
        guard registrationReady, registrationSecret.count == 64, !udidStatusInFlight else { return }
        udidStatusInFlight = true
        request(action: "device-status", payload: [:], token: registrationSecret) { [weak self] code, body, _ in
            guard let self else { return }
            self.udidStatusInFlight = false
            guard code == 200 else { if code == 401 { self.registrationReady = false }; return }
            let verified = body?["udid_status"] == "verified"
            self.verifiedUDID = verified
            if verified {
                self.udidEnrollmentPending = false
                self.appController?.setUDIDState("真实 UDID 已验证，可以输入卡密激活", verified: true)
            } else if self.udidEnrollmentPending {
                self.appController?.setUDIDState("等待系统完成设备识别；请返回 Safari/设置安装描述文件", verified: false)
            } else {
                self.appController?.setUDIDState("请先获取并验证真实设备 UDID", verified: false)
            }
        }
    }

    private func redeem(code submittedCode: String) {
        let code = submittedCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, !checkInFlight else { return }
        guard verifiedUDID else {
            appController?.setAuthorization(false, message: "首次激活前必须先获取并验证 UDID")
            beginUDIDEnrollment()
            return
        }
        let identifier = deviceIdentifier
        checkInFlight = true
        appController?.setAuthorization(false, message: "正在验证激活码…", busy: true)
        request(action: "activate", payload: ["code": code, "device_id": identifier, "registration_secret": registrationSecret], token: nil) { [weak self] httpCode, data, diagnostic in
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
        sendPresence()
        DispatchQueue.main.asyncAfter(deadline: .now() + timerInterval) { [weak self] in
            guard let self, let checked = self.lastCheck,
                  Date().timeIntervalSince(checked) >= self.timerInterval - 1 else { return }
            self.foreground()
        }
    }

    // ProvisionedDevices is an allowed-device list, never a hardware getter.
    // Only a unique entry is reported, explicitly as an unverified signing hint.
    private lazy var signingUDID: String? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url), data.count <= 1_048_576,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any],
              let identifiers = plist["ProvisionedDevices"] as? [String] else { return nil }
        let unique = Set(identifiers.map { $0.uppercased() })
        guard unique.count == 1, let value = unique.first,
              value.range(of: "^(?:[A-F0-9]{40}|[A-F0-9]{8}-[A-F0-9]{16})$", options: .regularExpression) != nil else { return nil }
        return value
    }()

    private func presencePayload(foreground: Bool = true) -> [String: String] {
        var system = utsname()
        uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        let model = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return ["page": currentPage, "foreground": foreground ? "yes" : "no", "model": model,
                "os_version": UIDevice.current.systemVersion, "app_version": version + " (" + build + ")", "signing_udid": signingUDID ?? ""]
    }

    @objc private func background() {
        guard registrationReady else { return }
        request(action: "heartbeat", payload: presencePayload(foreground: false), token: registrationSecret) { _, _, _ in }
    }

    private func sendPresence() {
        guard !presenceInFlight, UIApplication.shared.applicationState != .background else { return }
        let secret = registrationSecret
        guard secret.count == 64 else { return }
        presenceInFlight = true
        if !registrationReady {
            var payload = presencePayload()
            payload["device_id"] = deviceIdentifier
            payload["registration_secret"] = secret
            request(action: "register", payload: payload, token: nil) { [weak self] status, body, diagnostic in
                guard let self else { return }
                self.presenceInFlight = false
                self.registrationReady = status == 200
                self.registrationFailure = self.registrationReady ? "" : (status == 404 ? "服务器尚未部署设备登记接口" : (body?["error"] ?? diagnostic))
                if self.registrationReady { self.refreshUDIDStatus(); if self.udidEnrollmentPending { self.beginUDIDEnrollment() } }
                else if self.udidEnrollmentPending { self.appController?.setUDIDState("设备登记失败：" + self.registrationFailure, verified: false) }
            }
        } else {
            request(action: "heartbeat", payload: presencePayload(), token: secret) { [weak self] status, _, _ in
                guard let self else { return }
                self.presenceInFlight = false
                if status == 401 { self.registrationReady = false }
            }
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

