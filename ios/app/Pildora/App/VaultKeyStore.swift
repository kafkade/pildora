import Foundation
import Security

/// Device-local storage for the vault key that unlocks the encrypted database.
///
/// The vault key is produced during onboarding (Argon2id → MUK → per-vault key)
/// and stored here so the encrypted database can be reopened on later launches.
/// The key never leaves the device unless the user opts into iCloud Keychain
/// backup. On first-run onboarding the app calls ``save(_:biometricProtected:synchronizable:)``;
/// a diagnostics/dev path may still use ``loadOrCreateVaultKey(generate:)``.
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

    /// The stored vault key, or `nil` if none has been saved yet.
    ///
    /// - Note: When the key was saved with `biometricProtected: true`, reading it
    ///   triggers the system biometric prompt.
    func load() throws -> Data? {
        try read()
    }

    /// Whether a vault key is currently stored (without unlocking it).
    func hasKey() -> Bool {
        var query = baseQuery()
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Persist a vault key produced during onboarding.
    ///
    /// - Parameters:
    ///   - key: The 32-byte vault key.
    ///   - biometricProtected: When `true`, the item is gated behind Face ID /
    ///     Touch ID (`biometryCurrentSet`) and is device-only. When `false`, it
    ///     is accessible after first unlock without a prompt.
    ///   - synchronizable: When `true` (and not biometric-protected), the item is
    ///     backed up via iCloud Keychain so it can restore on a new device.
    ///     Biometric protection takes precedence: a biometric-gated key is always
    ///     device-only and cannot be synchronized.
    func save(_ key: Data, biometricProtected: Bool, synchronizable: Bool) throws {
        // Replace any existing item so re-running onboarding is idempotent.
        SecItemDelete(baseQuery() as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = key

        if biometricProtected {
            var acError: Unmanaged<CFError>?
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                .biometryCurrentSet,
                &acError
            ) else {
                if let err = acError?.takeRetainedValue() {
                    throw VaultKeyStoreError.accessControl(err)
                }
                throw VaultKeyStoreError.keychain(errSecParam)
            }
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = synchronizable
                ? kSecAttrAccessibleAfterFirstUnlock
                : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            if synchronizable {
                query[kSecAttrSynchronizable as String] = kCFBooleanTrue
            }
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultKeyStoreError.keychain(status)
        }
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
    case accessControl(CFError)
}
