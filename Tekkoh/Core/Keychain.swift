import CryptoKit
import Foundation
import Security

/// The journal key and username, in the Keychain. The key syncs through
/// iCloud Keychain to the person's own devices (end-to-end encrypted by
/// Apple), and is readable after the first unlock so location visits can be
/// recorded in the background.
enum Keychain {
    private static let service = "com.artifact.tekkoh"

    struct Identity: Codable, Equatable {
        var handle: String
        var key: Data
    }

    static func save(_ id: Identity) throws {
        let data = try JSONEncoder().encode(id)
        delete()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "journal",
            kSecAttrSynchronizable as String: kCFBooleanTrue!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func load() -> Identity? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "journal",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(Identity.self, from: d)
    }

    static func delete() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "journal",
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(q as CFDictionary)
    }
}

extension Keychain.Identity {
    var journalKey: SymmetricKey { SymmetricKey(data: key) }
}
