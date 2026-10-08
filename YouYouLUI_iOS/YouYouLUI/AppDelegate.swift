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
    private let status = UILabel()
    private let codeField = UITextField()
    private let activateButton = UIButton(type: .system)
    private let ambientGradient = CAGradientLayer()
    private var appController: WebViewController?
    private weak var activationScroll: UIScrollView?
    private let closeActivationButton = UIButton(type: .system)
    private var checkInFlight = false
    private var lastCheck: Date?
    private let timerInterval: TimeInterval = 300

    init(endpoint: URL) {
        self.endpoint = endpoint
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        ambientGradient.colors = [
            UIColor(red: 0.92, green: 0.95, blue: 1.00, alpha: 1).cgColor,
            UIColor(red: 0.97, green: 0.93, blue: 1.00, alpha: 1).cgColor,
            UIColor(red: 0.94, green: 0.97, blue: 1.00, alpha: 1).cgColor
        ]
        ambientGradient.locations = [0.0, 0.54, 1.0]
        ambientGradient.startPoint = CGPoint(x: 0, y: 0)
        ambientGradient.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(ambientGradient, at: 0)

        let scroll = UIScrollView()
        scroll.backgroundColor = UIColor(red: 0.95, green: 0.94, blue: 1.0, alpha: 1)
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let emblem = UIImageView(image: UIImage(systemName: "key.fill"))
        emblem.tintColor = UIColor(red: 0.38, green: 0.41, blue: 0.93, alpha: 1)
        emblem.contentMode = .scaleAspectFit
        emblem.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emblem.heightAnchor.constraint(equalToConstant: 58),
            emblem.widthAnchor.constraint(equalToConstant: 58)
        ])

        let title = UILabel()
        title.text = "激活 LUIYo"
        title.font = .systemFont(ofSize: 32, weight: .bold)
        title.textColor = .label
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true

        let subtitle = UILabel()
        subtitle.text = "输入您的专属激活码，即可解锁完整体验"
        subtitle.font = .systemFont(ofSize: 15, weight: .regular)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center

        let heading = UIStackView(arrangedSubviews: [emblem, title, subtitle])
        heading.axis = .vertical
        heading.alignment = .center
        heading.spacing = 12
        heading.setCustomSpacing(20, after: emblem)

        let fieldLabel = UILabel()
        fieldLabel.text = "激活码"
        fieldLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        fieldLabel.textColor = .secondaryLabel

        codeField.placeholder = "LUI-XXXXX-XXXXX-XXXXX-XXXXX"
        codeField.autocapitalizationType = .allCharacters
        codeField.autocorrectionType = .no
        codeField.textContentType = .oneTimeCode
        codeField.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        codeField.textColor = .label
        codeField.backgroundColor = UIColor.white.withAlphaComponent(0.80)
        codeField.borderStyle = .none
        codeField.layer.cornerRadius = 15
        codeField.layer.borderWidth = 1
        codeField.layer.borderColor = UIColor.separator.withAlphaComponent(0.35).cgColor
        codeField.clearButtonMode = .whileEditing
        codeField.returnKeyType = .done
        codeField.translatesAutoresizingMaskIntoConstraints = false
        let inset = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        codeField.leftView = inset
        codeField.leftViewMode = .always
        NSLayoutConstraint.activate([codeField.heightAnchor.constraint(equalToConstant: 58)])
        codeField.addTarget(self, action: #selector(redeem), for: .editingDidEndOnExit)

        status.text = "正在检查使用权限…"
        status.font = .systemFont(ofSize: 13)
        status.textAlignment = .center
        status.textColor = .secondaryLabel
        status.numberOfLines = 0

        var buttonStyle = UIButton.Configuration.filled()
        buttonStyle.title = "激活并进入"
        buttonStyle.image = UIImage(systemName: "arrow.right")
        buttonStyle.imagePlacement = .trailing
        buttonStyle.imagePadding = 10
        buttonStyle.cornerStyle = .large
        buttonStyle.baseBackgroundColor = UIColor(red: 0.40, green: 0.43, blue: 0.95, alpha: 1)
        buttonStyle.baseForegroundColor = .white
        activateButton.configuration = buttonStyle
        activateButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        activateButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([activateButton.heightAnchor.constraint(equalToConstant: 56)])
        activateButton.addTarget(self, action: #selector(redeem), for: .touchUpInside)

        let hint = UILabel()
        hint.text = "没有激活码？请联系管理员获取"
        hint.textAlignment = .center
        hint.textColor = .tertiaryLabel
        hint.font = .systemFont(ofSize: 12)
        hint.numberOfLines = 0

        let form = UIStackView(arrangedSubviews: [fieldLabel, codeField, status, activateButton, hint])
        form.axis = .vertical
        form.spacing = 14
        form.isLayoutMarginsRelativeArrangement = true
        form.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 27, leading: 22, bottom: 27, trailing: 22)
        form.backgroundColor = UIColor.white.withAlphaComponent(0.72)
        form.layer.cornerRadius = 28
        form.layer.borderWidth = 1
        form.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        form.setCustomSpacing(8, after: fieldLabel)
        form.setCustomSpacing(24, after: status)

        let content = UIStackView(arrangedSubviews: [heading, form])
        content.axis = .vertical
        content.spacing = 38
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 26),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -26),
            content.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: 40),
            content.bottomAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            content.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -52),
            scroll.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        activationScroll = scroll
        scroll.isHidden = true
        closeActivationButton.setTitle("关闭", for: .normal)
        closeActivationButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        closeActivationButton.translatesAutoresizingMaskIntoConstraints = false
        closeActivationButton.isHidden = true
        closeActivationButton.addTarget(self, action: #selector(closeActivation), for: .touchUpInside)
        view.addSubview(closeActivationButton)
        NSLayoutConstraint.activate([
            closeActivationButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -23),
            closeActivationButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeActivationButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        ensureAppVisible()
        refreshVisibility()
        NotificationCenter.default.addObserver(self, selector: #selector(foreground), name: UIApplication.willEnterForegroundNotification, object: nil)
        foreground()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        ambientGradient.frame = view.bounds
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func refreshVisibility() {
        status.isHidden = false
        codeField.isHidden = false
        activateButton.isHidden = false
    }

    @objc private func closeActivation() {
        codeField.resignFirstResponder()
        activationScroll?.isHidden = true
        closeActivationButton.isHidden = true
    }

    private func openActivation() {
        codeField.text = ""
        status.text = "输入激活码以开启完整功能"
        activationScroll?.isHidden = false
        if let scroll = activationScroll { view.bringSubviewToFront(scroll) }
        view.bringSubviewToFront(closeActivationButton)
        closeActivationButton.isHidden = false
    }

    private func ensureAppVisible() {
        guard appController == nil else { return }
        let app = WebViewController()
        app.setAuthorization(false)
        app.onActivationRequested = { [weak self] in self?.openActivation() }
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
        view.bringSubviewToFront(closeActivationButton)
    }

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

    @objc private func redeem() {
        let code = (codeField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, !checkInFlight else { return }
        let identifier: String
        if let saved = SecretStore.get("device-id") { identifier = saved }
        else {
            identifier = UUID().uuidString.lowercased()
            SecretStore.put(identifier, key: "device-id")
        }
        checkInFlight = true
        activateButton.isEnabled = false
        status.text = "正在验证激活码…"
        request(action: "activate", payload: ["code": code, "device_id": identifier], token: nil) { [weak self] httpCode, data, diagnostic in
            guard let self else { return }
            self.checkInFlight = false
            self.activateButton.isEnabled = true
            if httpCode == 200, let token = data?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                self.codeField.text = ""
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
        status.text = "正在验证使用权限…"
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
        ensureAppVisible()
        appController?.setAuthorization(true)
        closeActivation()
        refreshVisibility()
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
        status.text = message
        refreshVisibility()
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
