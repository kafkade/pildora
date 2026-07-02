import Foundation
import Security

/// Device-local storage for the vault key that unlocks the encrypted database.
///
/// Full Pildora derives the vault key from the user's master password (Argon2id
/// → MUK → per-vault key). That end-to-end unlock flow is a separate milestone;
/// for this CRUD slice the app generates a random 32-byte vault key on first
/// launch and persists it in the Keychain so the same encrypted database can be
/// reopened on every subsequent launch. The key never leaves the device and is
/// never synced.
struct VaultKeyStore {
    static let shared = VaultKeyStore()

    private let service = "com.kafkade.pildora.vaultkey"
    private let account: String

    init(account: String = "default-vault") {
        self.account = account
    }

    /// Return the stored vault key, generating and persisting one on first use.
    /// `generate` is injected so tests/bootstrap can use the crypto FFI.
    func loadOrCreateVaultKey(generate: () -> Data) throws -> Data {
        if let existing = try read() { return existing }
        let key = generate()
        try store(key)
        return key
    }

    // MARK: Keychain

    private func read() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw VaultKeyStoreError.keychain(status)
        }
    }

    private func store(_ key: Data) throws {
        var query = baseQuery()
        query[kSecValueData as String] = key
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultKeyStoreError.keychain(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum VaultKeyStoreError: Error {
    case keychain(OSStatus)
}
