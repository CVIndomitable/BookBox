import Foundation
import Security

/// 认证服务 — JWT Token 用 Keychain 持久化，启动时自动恢复
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var token: String?
    @Published private(set) var user: AuthUser?

    private let keychainAccount = "jwt-token"
    private let userDefaultsUserKey = "authUser"

    private init() {
        self.token = readKeychain()
        if let data = UserDefaults.standard.data(forKey: userDefaultsUserKey),
           let u = try? JSONDecoder().decode(AuthUser.self, from: data) {
            self.user = u
        }
    }

    var isLoggedIn: Bool { token != nil }

    func setSession(token: String, user: AuthUser) {
        self.token = token
        self.user = user
        writeKeychain(token)
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDefaultsUserKey)
        }
    }

    func clear() {
        token = nil
        user = nil
        deleteKeychain()
        UserDefaults.standard.removeObject(forKey: userDefaultsUserKey)
    }

    // MARK: - Keychain helpers

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "BookBox",
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private func readKeychain() -> String? {
        var q = keychainQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    private func writeKeychain(_ value: String) {
        let q = keychainQuery()
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = Data(value.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func deleteKeychain() {
        SecItemDelete(keychainQuery() as CFDictionary)
    }
}

struct AuthUser: Codable, Equatable {
    let id: Int
    let username: String
    let email: String?
    let displayName: String?
}
