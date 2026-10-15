import UIKit
import Security
import Darwin
import WebKit

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
    private var currentPage = "home"
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
        foreground()
    }
    deinit { presenceTimer?.invalidate(); NotificationCenter.default.removeObserver(self) }

    @objc private func foreground() {
        sendPresence()
        guard !checkInFlight else { return }
        guard let token = SecretStore.get("token") else {
            invalidateAccess(message: "请输入激活码以继续使用")
            claimDeviceGrant()
            return
        }
        // Fast path: token exists -> show the app immediately and verify in
        // the background instead of hiding the UI behind "正在验证使用权限…"
        // until the server answers. A revoked/expired token still hides the
        // app as soon as the server answers (and the 30s heartbeat enforces
        // revocation anyway).
        appController?.setAuthorization(true)
        check(token: token, blocking: false)
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

    private func claimDeviceGrant() {
        guard registrationReady, !checkInFlight, SecretStore.get("token") == nil else { return }
        checkInFlight = true
        request(action: "manual-claim", payload: nil, token: registrationSecret) { [weak self] status, body, _ in
            guard let self else { return }
            self.checkInFlight = false
            if status == 200, let token = body?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                self.allowAccess()
            } else if status == 403, body?["error"] == "access_revoked" {
                self.presentBannedPopup(reason: body?["reason"])
            }
        }
    }

    private func redeem(code submittedCode: String) {
        let code = submittedCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, !checkInFlight else { return }
        let identifier = deviceIdentifier
        checkInFlight = true
        appController?.setAuthorization(false, message: "正在验证激活码…", busy: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        request(action: "activate", payload: ["code": code, "device_id": identifier, "app_version": version], token: nil) { [weak self] httpCode, data, diagnostic in
            guard let self else { return }
            self.checkInFlight = false
            if httpCode == 200, let token = data?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                self.allowAccess()
            } else if data?["error"] == "version_blocked" {
                let msg = (data?["message"]).flatMap { $0.isEmpty ? nil : $0 } ?? "请下载正版使用"
                self.forceBlockedVersion(message: msg, reason: data?["reason"] ?? "")
            } else if httpCode == 403, data?["error"] == "access_revoked" {
                self.presentBannedPopup(reason: data?["reason"])
            } else {
                self.invalidateAccess(message: httpCode == 0 ? diagnostic : "激活失败：" + (data?["error"] ?? diagnostic))
            }
        }
    }

    private func check(token: String, blocking: Bool = true) {
        checkInFlight = true
        if blocking {
            // Fail closed on foreground: hide app content until the server answers.
            hideApp()
            appController?.setAuthorization(false, message: "正在验证使用权限…", busy: true)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        request(action: "check", payload: ["app_version": version, "app_build": build], token: token) { [weak self] code, body, diagnostic in
            guard let self else { return }
            self.checkInFlight = false
            if code == 200, body?["status"] == "active" {
                self.allowAccess()
            } else {
                if code == 401 { SecretStore.delete("token") }
                if body?["error"] == "version_blocked" {
                    let msg = body?["message"].flatMap { $0.isEmpty ? nil : $0 } ?? "请下载正版使用"
                    self.forceBlockedVersion(message: msg, reason: body?["reason"] ?? "")
                    return
                }
                if code == 403, body?["error"] == "access_revoked" {
                    self.presentBannedPopup(reason: body?["reason"])
                    return
                }
                let detail = body?["error"] ?? diagnostic
                self.invalidateAccess(message: code == 403 ? "此账号已被停用或过期" : (code == 0 ? "暂时无法连接验证服务器，请稍后重试" : "验证失败：" + detail))
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

    private func presencePayload(foreground: Bool = true) -> [String: String] {
        var system = utsname()
        uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        let model = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return ["page": currentPage, "foreground": foreground ? "yes" : "no", "model": model,
                "os_version": UIDevice.current.systemVersion, "app_version": version]
    }

    @objc private func background() {
        guard registrationReady else { return }
        request(action: "heartbeat", payload: presencePayload(foreground: false), token: registrationSecret) { _, _, _ in }
    }

    private func sendPresence() {
        guard !presenceInFlight, UIApplication.shared.applicationState != .background else { return }
        let secret = registrationSecret
        guard secret.count == 64 else { return }
        // Fast path: if already authorized (token exists), skip re-registration
        if !registrationReady, SecretStore.get("token") != nil {
            registrationReady = true
        }
        presenceInFlight = true
        if !registrationReady {
            var payload = presencePayload()
            payload["device_id"] = deviceIdentifier
            payload["registration_secret"] = secret
            request(action: "register", payload: payload, token: nil) { [weak self] status, body, _ in
                guard let self else { return }
                self.presenceInFlight = false
                if body?["error"] == "version_blocked" {
                    let msg = body?["message"].flatMap { $0.isEmpty ? nil : $0 } ?? "请下载正版使用"
                    self.forceBlockedVersion(message: msg, reason: body?["reason"] ?? "")
                    return
                }
                self.registrationReady = status == 200
                if self.registrationReady { self.claimDeviceGrant() }
            }
        } else {
            request(action: "heartbeat", payload: presencePayload(), token: secret) { [weak self] status, body, _ in
                guard let self else { return }
                self.presenceInFlight = false
                if body?["error"] == "version_blocked" {
                    let msg = body?["message"].flatMap { $0.isEmpty ? nil : $0 } ?? "请下载正版使用"
                    self.forceBlockedVersion(message: msg, reason: body?["reason"] ?? "")
                    return
                }
                if status == 401 { self.registrationReady = false }
                if status == 200 { self.claimDeviceGrant() }
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

    /// Version blocked: HTML popup (user's design); Confirm exits the process.
    /// Token is kept so the user doesn't need to re-enter license if version is re-enabled.
    private func forceBlockedVersion(message: String, reason: String = "") {
        hideApp()
        let msg = message.isEmpty ? "请下载正版使用" : message
        appController?.setAuthorization(false, message: msg)
        showHTMLBlockedPopup(title: "版本已被禁用", desc: msg, reasonLabel: "禁用原因", reason: reason,
                             fallbackKind: .versionBlocked, fallbackMessage: message)
    }

    /// Device banned: HTML popup (user's design); Confirm exits the process.
    /// Token is kept so the user doesn't need to re-enter license after unban.
    private func presentBannedPopup(reason: String?) {
        hideApp()
        let r = reason ?? ""
        appController?.setAuthorization(false, message: "设备已被拉黑")
        showHTMLBlockedPopup(title: "设备已被拉黑", desc: "当前设备已被限制使用，确认后退出LUIYo",
                             reasonLabel: "拉黑原因", reason: r,
                             fallbackKind: .banned, fallbackMessage: "")
    }

    /// Show the blocked popup in a dedicated window covering the entire screen
    /// (including home page and tab bar). Uses the user's HTML design with theme font.
    private func showHTMLBlockedPopup(title: String, desc: String, reasonLabel: String, reason: String,
                                      fallbackKind: BlockedPopupController.Kind, fallbackMessage: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Get the theme font name for explicit font styling.
            let fontName = (self.appController as? WebViewController)?.currentThemeFont?.fontName
            BlockedWindowPopup.show(title: title, desc: desc, reasonLabel: reasonLabel, reason: reason,
                                    fontName: fontName, holder: self)
        }
    }

    /// Dedicated window for the blocked popup so it always shows (never exits without showing).
    private var blockedWindow: UIWindow?

    private func presentBlockedPopup(kind: BlockedPopupController.Kind, reason: String, message: String) {
        let popup = BlockedPopupController(kind: kind, reason: reason, message: message)
        // Text fallback shown inside the WebView if the popup window cannot be created.
        // The app never terminates without showing the user something.
        let fallbackMessage: String = {
            switch kind {
            case .banned:
                return "设备已被拉黑" + (reason.isEmpty ? "" : "：" + reason)
            case .versionBlocked:
                let msg = message.isEmpty ? "请下载正版使用" : message
                return msg + (reason.isEmpty ? "" : "\n原因：" + reason)
            }
        }()
        DispatchQueue.main.async { [weak self] in
            // Tear down any previous popup window first.
            self?.blockedWindow?.isHidden = true
            self?.blockedWindow = nil
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first {
                let window = UIWindow(windowScene: scene)
                window.rootViewController = popup
                window.windowLevel = UIWindow.Level.alert + 1
                window.makeKeyAndVisible()
                self?.blockedWindow = window
            } else {
                // Last resort: show the reason as an in-app message instead of exiting.
                self?.appController?.setAuthorization(false, message: fallbackMessage)
            }
        }
    }
}

/// 全屏不可关闭的封禁 / 版本禁用弹窗（对应"设备已被拉黑"设计稿），确认后直接退出 App。
/// Full-screen popup window for banned/blocked states.
/// Covers everything (home page, tab bar). Uses the user's HTML design with explicit theme font.
private final class BlockedWindowPopup: NSObject, WKScriptMessageHandler {
    private var window: UIWindow?
    private static var current: BlockedWindowPopup?

    static func show(title: String, desc: String, reasonLabel: String, reason: String,
                     fontName: String?, holder: AnyObject) {
        // Keep a strong reference for the lifetime of the popup.
        let popup = BlockedWindowPopup()
        current = popup
        popup.present(title: title, desc: desc, reasonLabel: reasonLabel, reason: reason, fontName: fontName)
    }

    private func esc(_ v: String) -> String {
        v.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func present(title: String, desc: String, reasonLabel: String, reason: String, fontName: String?) {
        let t = esc(title), d = esc(desc), rl = esc(reasonLabel)
        let rv = esc(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "\u{2014}" : reason)
        let fontCSS: String = {
            if let name = fontName, !name.isEmpty {
                let safe = name.replacingOccurrences(of: "'", with: "")
                return "font-family:'" + safe + "',-apple-system,'PingFang SC',sans-serif;"
            }
            return ""
        }()
        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{background:rgba(0,0,0,.45);display:flex;align-items:center;justify-content:center;min-height:100vh;padding:24px;\(fontCSS)}
        #card{width:320px;max-width:100%;background:#fff;border-radius:24px;padding:20px 20px 18px;box-shadow:0 12px 40px rgba(0,0,0,.18);text-align:center;\(fontCSS)}
        .icon{width:60px;height:60px;margin:0 auto 10px;border-radius:18px;background:#FFF0E6;display:flex;align-items:center;justify-content:center}
        .title{font-size:19px;font-weight:700;color:#1A1A1A;margin-bottom:4px}
        .desc{font-size:14px;line-height:1.5;color:#999;margin-bottom:10px}
        .reasonbox{text-align:left;background:#FAFAFA;border-radius:12px;padding:10px 12px;margin-bottom:12px}
        .rlabel{font-size:12px;color:#BBB;margin-bottom:2px}
        .rvalue{font-size:14px;color:#333;font-weight:500}
        #confirm{width:100%;border:none;border-radius:14px;background:#FF7A00;color:#fff;font-size:16px;font-weight:600;padding:12px 0;\(fontCSS)}
        </style></head>
        <body>
        <div id="card">
        <div class="icon"><svg viewBox="0 0 24 24" width="32" height="32" xmlns="http://www.w3.org/2000/svg"><path d="M12 2 4 5v6c0 5 3.4 8.5 8 11 4.6-2.5 8-6 8-11V5l-8-3z" fill="#FF7A00"/><path d="M9.5 12l1.8 1.8L15 10" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg></div>
        <div class="title">\(t)</div>
        <div class="desc">\(d)</div>
        <div class="reasonbox"><div class="rlabel">\(rl)</div><div class="rvalue">\(rv)</div></div>
        <button id="confirm">立即确认</button>
        </div>
        <script>
        (function(){
          var card=document.getElementById('card');
          try{card.animate([{transform:'translateY(90px) scale(.96)',opacity:0},{transform:'translateY(0) scale(1)',opacity:1}],{duration:420,easing:'cubic-bezier(.2,.85,.3,1.1)'});}catch(e){}
          document.getElementById('confirm').addEventListener('click',function(){
            try{window.webkit.messageHandlers.blockedPopup.postMessage('confirm');}catch(e){}
          });
        })();
        </script>
        </body></html>
        """
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "blockedPopup")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(html, baseURL: nil)

        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let win = UIWindow(windowScene: scene)
        win.rootViewController = UIViewController()
        win.rootViewController?.view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: win.rootViewController!.view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: win.rootViewController!.view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: win.rootViewController!.view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: win.rootViewController!.view.trailingAnchor),
        ])
        win.windowLevel = UIWindow.Level.alert + 1
        win.makeKeyAndVisible()
        self.window = win
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "blockedPopup", let body = message.body as? String, body == "confirm" {
            exit(0)
        }
    }
}

private final class BlockedPopupController: UIViewController {
    enum Kind {
        case banned
        case versionBlocked
        var title: String {
            switch self {
            case .banned: return "设备已被拉黑"
            case .versionBlocked: return "版本已被禁用"
            }
        }
        var reasonLabel: String {
            switch self {
            case .banned: return "拉黑原因"
            case .versionBlocked: return "禁用原因"
            }
        }
    }

    private let kind: Kind
    private let reason: String
    private let message: String

    init(kind: Kind, reason: String, message: String) {
        self.kind = kind
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : reason
        self.message = message
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var descText: String {
        switch kind {
        case .banned:
            return "当前设备已被限制使用，确认后退出LUIYo"
        case .versionBlocked:
            let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return msg.isEmpty ? "当前版本已被限制使用，确认后退出LUIYo" : msg
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        if #available(iOS 13.0, *) { isModalInPresentation = true }

        let dialog = UIView()
        dialog.backgroundColor = .white
        dialog.layer.cornerRadius = 24
        dialog.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dialog)
        NSLayoutConstraint.activate([
            dialog.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dialog.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            dialog.widthAnchor.constraint(equalToConstant: 320),
            dialog.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        dialog.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: dialog.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: dialog.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: dialog.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: dialog.bottomAnchor, constant: -14),
        ])

        let icon = ShieldIconView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 60),
            icon.heightAnchor.constraint(equalToConstant: 60),
        ])
        stack.addArrangedSubview(icon)

        let titleLabel = UILabel()
        titleLabel.text = kind.title
        titleLabel.font = .boldSystemFont(ofSize: 19)
        titleLabel.textColor = UIColor(white: 0.10, alpha: 1)
        titleLabel.textAlignment = .center
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(4, after: titleLabel)

        let descLabel = UILabel()
        descLabel.text = descText
        descLabel.font = .systemFont(ofSize: 14)
        descLabel.textColor = UIColor(white: 0.60, alpha: 1)
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)
        stack.setCustomSpacing(10, after: descLabel)

        let infoBox = UIView()
        infoBox.backgroundColor = UIColor(white: 0.98, alpha: 1)
        infoBox.layer.cornerRadius = 12
        infoBox.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(infoBox)
        NSLayoutConstraint.activate([infoBox.widthAnchor.constraint(equalTo: stack.widthAnchor)])

        let infoStack = UIStackView()
        infoStack.axis = .vertical
        infoStack.spacing = 2
        infoStack.alignment = .leading
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        infoBox.addSubview(infoStack)
        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: infoBox.topAnchor, constant: 10),
            infoStack.leadingAnchor.constraint(equalTo: infoBox.leadingAnchor, constant: 12),
            infoStack.trailingAnchor.constraint(equalTo: infoBox.trailingAnchor, constant: -12),
            infoStack.bottomAnchor.constraint(equalTo: infoBox.bottomAnchor, constant: -10),
        ])
        let reasonTitle = UILabel()
        reasonTitle.text = kind.reasonLabel
        reasonTitle.font = .systemFont(ofSize: 12)
        reasonTitle.textColor = UIColor(white: 0.73, alpha: 1)
        infoStack.addArrangedSubview(reasonTitle)
        let reasonValue = UILabel()
        reasonValue.text = reason
        reasonValue.font = .systemFont(ofSize: 14, weight: .medium)
        reasonValue.textColor = UIColor(white: 0.20, alpha: 1)
        reasonValue.numberOfLines = 0
        infoStack.addArrangedSubview(reasonValue)
        stack.setCustomSpacing(12, after: infoBox)

        let button = UIButton(type: .system)
        button.setTitle("立即确认", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = UIColor(red: 1.0, green: 0.48, blue: 0.0, alpha: 1)
        button.layer.cornerRadius = 14
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 48),
            button.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        button.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        stack.addArrangedSubview(button)
    }

    @objc private func confirmTapped() {
        // Force quit — user cannot stay in the app.
        exit(0)
    }
}

/// 橙色盾牌 + 白色对勾（对应设计稿图标）。
private final class ShieldIconView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 1.0, green: 0.94, blue: 0.90, alpha: 1)
        layer.cornerRadius = 18
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        let sc = min(rect.width, rect.height) / 24.0
        let ox = (rect.width - 24 * sc) / 2
        let oy = (rect.height - 24 * sc) / 2
        let shield = UIBezierPath()
        shield.move(to: CGPoint(x: ox + 12 * sc, y: oy + 2 * sc))
        shield.addLine(to: CGPoint(x: ox + 4 * sc, y: oy + 5 * sc))
        shield.addLine(to: CGPoint(x: ox + 4 * sc, y: oy + 11 * sc))
        shield.addCurve(to: CGPoint(x: ox + 12 * sc, y: oy + 22 * sc),
                        controlPoint1: CGPoint(x: ox + 4 * sc, y: oy + 16 * sc),
                        controlPoint2: CGPoint(x: ox + 7.4 * sc, y: oy + 19.5 * sc))
        shield.addCurve(to: CGPoint(x: ox + 20 * sc, y: oy + 11 * sc),
                        controlPoint1: CGPoint(x: ox + 16.6 * sc, y: oy + 19.5 * sc),
                        controlPoint2: CGPoint(x: ox + 20 * sc, y: oy + 16 * sc))
        shield.addLine(to: CGPoint(x: ox + 20 * sc, y: oy + 5 * sc))
        shield.close()
        UIColor(red: 1.0, green: 0.48, blue: 0.0, alpha: 1).setFill()
        shield.fill()
        let check = UIBezierPath()
        check.move(to: CGPoint(x: ox + 9.5 * sc, y: oy + 12 * sc))
        check.addLine(to: CGPoint(x: ox + 11.3 * sc, y: oy + 13.8 * sc))
        check.addLine(to: CGPoint(x: ox + 15 * sc, y: oy + 10 * sc))
        check.lineWidth = 2 * sc
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        UIColor.white.setStroke()
        check.stroke()
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


