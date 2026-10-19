import Foundation
import UIKit

/// What the gate should show. The session owns the decision; the gate owns the pixels.
enum ActivationState {
    /// Nothing usable: the app stays hidden behind the given notice.
    case unauthorized(message: String?)
    /// A request is running: the app stays hidden and the activation form is busy.
    case checking(message: String?)
    case authorized
    /// Backend disabled this build. Confirming the popup quits the app.
    case versionBlocked(message: String, reason: String)
    /// Backend banned this device. Confirming the popup quits the app.
    case banned(reason: String)

    var isAuthorized: Bool {
        if case .authorized = self { return true }
        return false
    }
}

/// Server-backed access state machine: registration, presence heartbeat,
/// activation-code redemption, periodic re-check and device grants.
final class ActivationSession {
    private enum Timing {
        static let presence: TimeInterval = 30
        static let recheck: TimeInterval = 300
    }

    private enum Grant {
        static let backendKeys = ["tier", "plan", "level", "vip_level", "user_type", "membership", "svip", "userType", "vipLevel"]
    }

    private let client: ActivationClient
    private let preferences = ThemePreferences.shared

    /// Emitted on the main queue whenever access changes.
    var onState: ((ActivationState) -> Void)?
    /// Current page name, attached to presence payloads.
    var currentPage: String = "home"

    private var checkInFlight = false
    private var presenceInFlight = false
    private var registrationReady = false
    private var lastCheck: Date?
    private var presenceTimer: Timer?
    private var recheckWorkItem: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init(endpoint: URL) {
        client = ActivationClient(endpoint: endpoint)
    }

    deinit { stop() }

    func start() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.enterBackground()
        })
        presenceTimer = Timer.scheduledTimer(withTimeInterval: Timing.presence, repeats: true) { [weak self] _ in
            guard UIApplication.shared.applicationState == .active else { return }
            self?.sendPresence()
        }
        refresh()
    }

    func stop() {
        presenceTimer?.invalidate()
        presenceTimer = nil
        recheckWorkItem?.cancel()
        recheckWorkItem = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    func enterBackground() {
        guard registrationReady else { return }
        client.send(.heartbeat, payload: presencePayload(foreground: false), token: DeviceIdentity.registrationSecret) { _ in }
    }

    /// Foreground verification. A stored token opens the app immediately and is
    /// re-validated in the background; revocation still hides the app as soon as
    /// the server answers.
    func refresh() {
        sendPresence()
        guard !checkInFlight else { return }
        guard let token = DeviceIdentity.token else {
            emit(.unauthorized(message: "请输入激活码以继续使用"))
            claimDeviceGrant()
            return
        }
        emit(.authorized)
        check(token: token, blocking: false)
    }

    /// Redeems an activation code typed into the settings page.
    func redeem(code submitted: String) {
        let code = submitted.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty, !checkInFlight else { return }
        checkInFlight = true
        emit(.checking(message: "正在验证激活码…"))
        client.send(.activate,
                    payload: ["code": code, "device_id": DeviceIdentity.identifier, "app_version": AppConfiguration.marketingVersion]) { [weak self] response in
            guard let self else { return }
            self.checkInFlight = false
            if let token = response.body?["token"], response.status == 200, token.count == 64 {
                DeviceIdentity.token = token
                self.allowAccess()
            } else if response.error == "version_blocked" {
                self.blockVersion(response)
            } else if response.status == 403, response.error == "access_revoked" {
                self.emit(.banned(reason: response.body?["reason"] ?? ""))
            } else {
                let detail = response.status == 0 ? response.diagnostic : "激活失败：" + (response.error ?? response.diagnostic)
                self.emit(.unauthorized(message: detail))
            }
        }
    }

    // MARK: - Verification

    private func check(token: String, blocking: Bool) {
        checkInFlight = true
        if blocking {
            // Fail closed: hide app content until the server answers.
            emit(.unauthorized(message: nil))
            emit(.checking(message: "正在验证使用权限…"))
        }
        client.send(.check,
                    payload: ["app_version": AppConfiguration.marketingVersion, "app_build": AppConfiguration.buildNumber],
                    token: token) { [weak self] response in
            guard let self else { return }
            self.checkInFlight = false
            if response.status == 200, response.body?["status"] == "active" {
                if let body = response.body { self.syncBackendProfile(body) }
                self.allowAccess()
                return
            }
            if response.status == 401 {
                DeviceIdentity.token = nil
                // 清除过期的设备码缓存，下次同步会从后台重新获取
                preferences.deviceCode = nil
            }
            if response.error == "version_blocked" { self.blockVersion(response); return }
            if response.status == 403, response.error == "access_revoked" {
                self.emit(.banned(reason: response.body?["reason"] ?? ""))
                return
            }
            let detail = response.error ?? response.diagnostic
            let message: String
            switch response.status {
            case 0: message = "暂时无法连接验证服务器，请稍后重试"
            case 403: message = "此账号已被停用或过期"
            default: message = "验证失败：" + detail
            }
            self.emit(.unauthorized(message: message))
        }
    }

    private func allowAccess() {
        lastCheck = Date()
        emit(.authorized)
        sendPresence()
        recheckWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let checked = self.lastCheck,
                  Date().timeIntervalSince(checked) >= Timing.recheck - 1 else { return }
            self.refresh()
        }
        recheckWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.recheck, execute: work)
    }

    // MARK: - Presence

    private func presencePayload(foreground: Bool = true) -> [String: String] {
        ["page": currentPage,
         "foreground": foreground ? "yes" : "no",
         "model": DeviceIdentity.machineIdentifier,
         "os_version": UIDevice.current.systemVersion,
         "app_version": AppConfiguration.marketingVersion]
    }

    private func sendPresence() {
        guard !presenceInFlight, UIApplication.shared.applicationState != .background else { return }
        let secret = DeviceIdentity.registrationSecret
        guard secret.count == 64 else { return }
        // Fast path: an existing token implies a previous registration.
        if !registrationReady, DeviceIdentity.token != nil { registrationReady = true }
        presenceInFlight = true
        if !registrationReady {
            var payload = presencePayload()
            payload["device_id"] = DeviceIdentity.identifier
            payload["registration_secret"] = secret
            client.send(.register, payload: payload) { [weak self] response in
                guard let self else { return }
                self.presenceInFlight = false
                if response.error == "version_blocked" { self.blockVersion(response); return }
                self.registrationReady = response.status == 200
                if self.registrationReady { self.claimDeviceGrant() }
            }
        } else {
            client.send(.heartbeat, payload: presencePayload(), token: secret) { [weak self] response in
                guard let self else { return }
                self.presenceInFlight = false
                if response.error == "version_blocked" { self.blockVersion(response); return }
                if response.status == 401 { self.registrationReady = false }
                if response.status == 200 { self.claimDeviceGrant() }
            }
        }
    }

    /// Picks up a device-code grant assigned from the admin console.
    private func claimDeviceGrant() {
        guard registrationReady, !checkInFlight, DeviceIdentity.token == nil else { return }
        checkInFlight = true
        client.send(.manualClaim, token: DeviceIdentity.registrationSecret) { [weak self] response in
            guard let self else { return }
            self.checkInFlight = false
            if response.status == 200, let token = response.body?["token"], token.count == 64 {
                DeviceIdentity.token = token
                self.allowAccess()
            } else if response.status == 403, response.error == "access_revoked" {
                self.emit(.banned(reason: response.body?["reason"] ?? ""))
            }
        }
    }

    // MARK: - Backend profile

    /// Mirrors the device code and membership level into UserDefaults so the
    /// native settings hero card can render them.
    private func syncBackendProfile(_ body: [String: String]) {
        for (_, value) in body where value.hasPrefix("D-") && value.count >= 8 {
            preferences.deviceCode = value
            break
        }
        for key in Grant.backendKeys {
            guard let raw = body[key], !raw.isEmpty else { continue }
            let lowercased = raw.lowercased()
            let tier = lowercased.contains("svip") ? "svip" : (lowercased.contains("vip") ? "vip" : "free")
            preferences.authTier = tier
            break
        }
    }

    private func blockVersion(_ response: ActivationResponse) {
        let message = response.body?["message"].flatMap { $0.isEmpty ? nil : $0 } ?? "请下载正版使用"
        emit(.versionBlocked(message: message, reason: response.body?["reason"] ?? ""))
    }

    private func emit(_ state: ActivationState) {
        // 未授权时清除会员等级显示，只有授权才显示 SVIP
        if !state.isAuthorized {
            preferences.authTier = "free"
            NotificationCenter.default.post(name: NSNotification.Name("LUIYoTierUpdated"), object: nil)
        }
        DispatchQueue.main.async { [weak self] in self?.onState?(state) }
    }
}
