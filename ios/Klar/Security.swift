import Foundation
import Security
import LocalAuthentication

struct KeychainVault {
    private static let service = "at.klar.app"
    static func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
                                    kSecAttrService as String:service, kSecAttrAccount as String:key]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,
                                    kSecAttrService as String:service, kSecAttrAccount as String:key,
                                    kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func remove(_ key: String) {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,
                       kSecAttrService as String:service,kSecAttrAccount as String:key] as CFDictionary)
    }
}

@MainActor
final class UnlockGate: ObservableObject {
    @Published var unlocked = false
    @Published var error: String?
    func authenticate() async {
        let context = LAContext()
        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            // If no device credential is set, app must remain locked while app lock is enabled.
            error = "Richte zuerst einen iPhone-Code oder Face ID ein."
            return
        }
        do {
            unlocked = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                       localizedReason: "Klar. enthält persönliche Finanzdaten")
            error = nil
        } catch {
            self.error = "Entsperren fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
