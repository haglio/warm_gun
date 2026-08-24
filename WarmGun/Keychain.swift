import Foundation
import Security

/// The one secret the app holds: the pCloud auth token. The password that
/// earned it is used for a single login request and never stored.
enum Keychain {
    private static let service = "com.cmloegcmluin.warmgun"
    private static let account = "pcloud-auth"
    /// The password he is mid-way through logging in with. Kept ONLY between a
    /// failed attempt and the one that succeeds — retyping it on every round of
    /// a multi-step challenge is what wore the owner out — and deleted the moment
    /// a token is earned, which restores the design's "the password is never
    /// stored" the instant it stops being needed.
    private static let pendingAccount = "pcloud-password-pending"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static var pendingQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: pendingAccount]
    }

    static func pendingPassword() -> String? {
        var q = pendingQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func storePending(password: String) {
        let data = Data(password.utf8)
        var add = pendingQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(add as CFDictionary, nil) == errSecDuplicateItem {
            SecItemUpdate(pendingQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    static func forgetPending() {
        SecItemDelete(pendingQuery as CFDictionary)
    }

    static func token() -> String? {
        #if targetEnvironment(simulator)
        // The Simulator runs against tools/fake_pcloud.py, which accepts any
        // token — letting a launch environment stand in for the Keychain is
        // what makes the whole app drivable headlessly in verification. Device
        // builds compile this out.
        if let injected = ProcessInfo.processInfo.environment["WARMGUN_TOKEN"] { return injected }
        #endif
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func store(token: String) {
        let data = Data(token.utf8)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    static func forget() {
        SecItemDelete(query as CFDictionary)
    }
}
