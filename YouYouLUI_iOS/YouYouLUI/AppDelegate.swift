import UIKit
import Security
import Darwin
import SwiftUI

// Preview-only: all glass is rendered by iOS 26 SwiftUI system APIs.
// This view is compiled only for Debug simulator builds.
#if DEBUG && targetEnvironment(simulator)
@available(iOS 26.0, *)
private struct LUIYoNativeGlassHomePreview: View {
    @State private var category = 0
    @State private var query = ""
    @State private var showColors = false
    @State private var selectedColor = Color.blue
    private let titles = ["插件入口", "顶栏美化设置", "改金额", "改文字", "头像遮罩", "背景 Diy"]

    var body: some View {
        TabView {
            Tab("首页", systemImage: "house.fill") { home }
            Tab("规则", systemImage: "list.bullet.rectangle") {
                NavigationStack { Text("图标命名规则").navigationTitle("规则") }
            }
            Tab("设置", systemImage: "gearshape.fill") {
                NavigationStack { Text("主题与偏好设置").navigationTitle("设置") }
            }
            Tab(role: .search) {
                NavigationStack { Text("搜索图标").navigationTitle("搜索") }
            }
        }
        .searchable(text: $query, prompt: "搜索图标")
        .tint(.blue)
        .onAppear(perform: saveRuntimeEvidence)
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("LUIYo").font(.largeTitle.bold())
                    Text("LiquidUI / 微信图标管理").font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label("已授权", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.medium)).foregroundStyle(.green)
                        Text("已上传 0 项").font(.caption).foregroundStyle(.secondary)
                    }
                }
                tools
                Picker("图标分类", selection: $category) {
                    Text("LiquidUI").tag(0)
                    Text("原版微信").tag(1)
                }
                .pickerStyle(.segmented)
                Text(category == 0 ? "LiquidUI 图标" : "原版微信图标").font(.headline)
                GlassEffectContainer(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(titles, id: \.self) { title in
                            Button {} label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus").font(.title3).foregroundStyle(.secondary)
                                        .frame(width: 30, height: 42)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                                        Text("点击上传").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14).frame(maxWidth: .infinity, minHeight: 78)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
                            .accessibilityLabel("上传" + title)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .background {
            // A wallpaper backdrop only. Glass, edges and highlights are system-rendered.
            LinearGradient(colors: [Color(uiColor: .systemGroupedBackground), Color.blue.opacity(0.07), Color(uiColor: .systemGroupedBackground)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    private var tools: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {} label: {
                        Label("关键词批量导入", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.buttonStyle(.glass).controlSize(.large)
                    Button {} label: {
                        Label("补全图片", systemImage: "photo")
                            .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    }.buttonStyle(.glass).controlSize(.large)
                }
                Button {} label: {
                    Label("双分类补全", systemImage: "square.3.layers.3d")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }.buttonStyle(.glass).controlSize(.large)
                DisclosureGroup(isExpanded: $showColors) {
                    ColorPicker("选中颜色", selection: $selectedColor).font(.subheadline)
                } label: {
                    Label("自定义修改颜色", systemImage: "paintpalette")
                        .font(.subheadline).foregroundStyle(.primary)
                }.padding(.horizontal, 8)
                HStack(spacing: 12) {
                    Button {} label: {
                        Label("清空", systemImage: "trash").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).tint(.blue).controlSize(.large)
                    Button {} label: {
                        Label("导出 ZIP", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.glassProminent).tint(.green).controlSize(.large)
                }.font(.subheadline.weight(.semibold))
            }
        }
    }

    private func saveRuntimeEvidence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            var glassClasses: [String] = []
            func visit(_ view: UIView) {
                let name = String(describing: type(of: view))
                if name.localizedCaseInsensitiveContains("glass") { glassClasses.append(name) }
                if let surface = view as? UIVisualEffectView, let effect = surface.effect {
                    glassClasses.append(String(describing: type(of: effect)))
                }
                view.subviews.forEach(visit)
            }
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                scene.windows.forEach(visit)
            }
            let evidence: [String: Any] = [
                "osVersion": UIDevice.current.systemVersion,
                "rendering": "native SwiftUI on iOS simulator",
                "apis": ["glassEffect(.regular.interactive())", "buttonStyle(.glass)", "buttonStyle(.glassProminent)", "Picker(.segmented)", "TabView with search role"],
                "runtimeGlassClasses": Array(Set(glassClasses)).sorted(),
                "previewOnly": true
            ]
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: dir.appendingPathComponent("native-glass-evidence.json"))
            }
            try? Data("ready".utf8).write(to: dir.appendingPathComponent("native-glass-ready.txt"))
        }
    }
}
#endif

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
        if let scenario = ProcessInfo.processInfo.environment["LUI_SNAPSHOT"],
           scenario.hasPrefix("preview-native-glass-home"), #available(iOS 26.0, *) {
            window.overrideUserInterfaceStyle = scenario.hasSuffix("dark") ? .dark : .light
            window.rootViewController = UIHostingController(rootView: LUIYoNativeGlassHomePreview())
            window.makeKeyAndVisible()
            self.window = window
            return true
        }
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

    private func claimDeviceGrant() {
        guard registrationReady, !checkInFlight, SecretStore.get("token") == nil else { return }
        checkInFlight = true
        request(action: "manual-claim", payload: nil, token: registrationSecret) { [weak self] status, body, _ in
            guard let self else { return }
            self.checkInFlight = false
            if status == 200, let token = body?["token"], token.count == 64 {
                SecretStore.put(token, key: "token")
                self.allowAccess()
            }
        }
    }

    private func redeem(code submittedCode: String) {
        let code = submittedCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, !checkInFlight else { return }
        let identifier = deviceIdentifier
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
        presenceInFlight = true
        if !registrationReady {
            var payload = presencePayload()
            payload["device_id"] = deviceIdentifier
            payload["registration_secret"] = secret
            request(action: "register", payload: payload, token: nil) { [weak self] status, _, _ in
                guard let self else { return }
                self.presenceInFlight = false
                self.registrationReady = status == 200
                if self.registrationReady { self.claimDeviceGrant() }
            }
        } else {
            request(action: "heartbeat", payload: presencePayload(), token: secret) { [weak self] status, _, _ in
                guard let self else { return }
                self.presenceInFlight = false
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


