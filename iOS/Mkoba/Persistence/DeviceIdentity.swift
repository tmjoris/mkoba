import Foundation
import MkobaCore
import Security

/// A stable per-install identifier kept in the Keychain so it survives reinstalls that
/// restore from backup but is never shared between devices (unlike iCloud key-value store).
enum DeviceIdentity {
    private static let service = "ke.mkoba.device"
    private static let account = "device-id"

    static func current() -> DeviceID {
        if let existing = read() { return DeviceID(existing) }
        let fresh = "ios-" + UUID().uuidString.lowercased().prefix(12)
        write(String(fresh))
        return DeviceID(String(fresh))
    }

    private static func read() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: Data(value.utf8),
            // Not synced to iCloud Keychain, available after first unlock for background sync.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
