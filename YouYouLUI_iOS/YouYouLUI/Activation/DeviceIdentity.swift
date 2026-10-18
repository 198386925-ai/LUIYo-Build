import Darwin
import Security
import UIKit

/// Stable device-level secrets used by the activation backend.
/// Stored in the keychain so a reinstall keeps the same install record.
enum DeviceIdentity {
    private enum Key {
        static let identifier = "device-id"
        static let registrationSecret = "registration-secret"
        static let token = "token"
    }

    /// `identifierForVendor` survives reinstalls; a random UUID would make the
    /// backend treat every reinstall as a brand-new device.
    static var identifier: String {
        if let saved = KeychainStore.get(Key.identifier) { return saved }
        let value = UIDevice.current.identifierForVendor?.uuidString.lowercased()
            ?? UUID().uuidString.lowercased()
        KeychainStore.put(value, key: Key.identifier)
        return value
    }

    /// Random per-install secret used to authenticate presence/claim calls.
    static var registrationSecret: String {
        if let saved = KeychainStore.get(Key.registrationSecret) { return saved }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return "" }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        KeychainStore.put(value, key: Key.registrationSecret)
        return value
    }

    static var token: String? {
        get { KeychainStore.get(Key.token) }
        set {
            if let value = newValue { KeychainStore.put(value, key: Key.token) }
            else { KeychainStore.delete(Key.token) }
        }
    }

    /// e.g. `iPhone17,1`.
    static var machineIdentifier: String {
        var system = utsname()
        uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}
