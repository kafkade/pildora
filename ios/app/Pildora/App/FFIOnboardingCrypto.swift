import Foundation
import PildoraOnboarding
import PildoraSecureMemory

/// Production ``OnboardingCrypto`` backed by the Rust `pildora-crypto` FFI.
///
/// Runs the real key hierarchy: Argon2id derives the master key from the
/// password; HKDF splits it into the auth key + Master Encryption Key (MEK); a
/// random vault key is generated and wrapped by the MEK; a random recovery key
/// is generated and used to wrap the MEK for offline recovery.
///
/// Sensitive intermediate material (master key, MEK, recovery key) is held in
/// ``SecureBytes`` so it is zeroized from memory as soon as the wrapped blobs and
/// the display string have been produced — satisfying the issue's requirement
/// that recovery key material be wiped after the PDF is generated (issue #40).
struct FFIOnboardingCrypto: OnboardingCrypto {

    func createVault(password: String, vaultID: String, vaultName: String) throws -> VaultSetup {
        do {
            let salt = generateSalt()

            // Master key (Argon2id) → sub-keys, wiped once the MEK is extracted.
            var masterKey = SecureBytes(try deriveMasterKey(password: Data(password.utf8), salt: salt))
            let subKeys = try masterKey.withUnsafeBytes { raw -> SubKeys in
                try deriveSubKeys(masterKey: Data(raw))
            }
            masterKey.zeroize()

            // Hold the MEK securely for the two wrap operations below.
            var mek = SecureBytes(subKeys.mek)
            defer { mek.zeroize() }

            // Vault key: generated, wrapped by the MEK, then returned live for the
            // Keychain. It is the only key that must survive this call.
            let vaultKey = generateVaultKey()
            let wrappedVaultKey = try mek.withUnsafeBytes { mekRaw in
                try wrapVaultKey(vaultKey: vaultKey, mek: Data(mekRaw))
            }

            // Recovery key: wrap the MEK under it, format it for display, then wipe.
            var recoveryKey = SecureBytes(generateRecoveryKey())
            defer { recoveryKey.zeroize() }
            let recoveryWrappedMek = try recoveryKey.withUnsafeBytes { rkRaw -> Data in
                try mek.withUnsafeBytes { mekRaw in
                    try wrapMekForRecovery(mek: Data(mekRaw), recoveryKey: Data(rkRaw))
                }
            }
            let recoveryDisplay = try recoveryKey.withUnsafeBytes { rkRaw in
                try recoveryKeyDisplayString(recoveryKey: Data(rkRaw))
            }

            let config = VaultConfig(
                vaultID: vaultID,
                vaultName: vaultName,
                salt: salt,
                wrappedVaultKey: wrappedVaultKey,
                recoveryWrappedMek: recoveryWrappedMek
            )
            return VaultSetup(config: config, vaultKey: vaultKey, recoveryKeyDisplay: recoveryDisplay)
        } catch {
            // Never surface raw crypto error detail (it may reference key sizes /
            // internals); map to the flow's redacted error type.
            throw OnboardingCryptoError.cryptoFailure("vault setup failed")
        }
    }
}
