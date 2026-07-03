import Foundation

// MARK: - Persisted vault configuration

/// The non-secret cryptographic material persisted after onboarding completes.
///
/// None of these fields are plaintext key material — they are salts and *wrapped*
/// (encrypted) keys that are useless without either the master password or the
/// recovery key. They are safe to store outside the Keychain (e.g. in a
/// preferences file) and are what lets the app unlock the vault on later
/// launches and recover it if the password is lost.
public struct VaultConfig: Codable, Equatable, Sendable {
    /// Stable identifier of the vault this config unlocks.
    public let vaultID: String
    /// Human-readable vault name (e.g. "Me").
    public let vaultName: String
    /// Argon2id salt used to derive the master key from the password.
    public let salt: Data
    /// The vault key wrapped by the Master Encryption Key (MEK).
    public let wrappedVaultKey: Data
    /// The MEK wrapped by the recovery key — the offline recovery path.
    public let recoveryWrappedMek: Data

    public init(
        vaultID: String,
        vaultName: String,
        salt: Data,
        wrappedVaultKey: Data,
        recoveryWrappedMek: Data
    ) {
        self.vaultID = vaultID
        self.vaultName = vaultName
        self.salt = salt
        self.wrappedVaultKey = wrappedVaultKey
        self.recoveryWrappedMek = recoveryWrappedMek
    }
}

// MARK: - Vault setup result

/// The full output of creating a brand-new encrypted vault from a master
/// password. Produced by ``OnboardingCrypto/createVault(password:vaultID:vaultName:)``.
///
/// `vaultKey` is live (unwrapped) key material: the caller must store it in the
/// Keychain and must not persist it anywhere else. `recoveryKeyDisplay` is the
/// human-readable recovery key shown to the user exactly once and printed on the
/// recovery PDF; it is not persisted.
public struct VaultSetup {
    /// The non-secret material to persist (salt + wrapped keys).
    public let config: VaultConfig
    /// The live vault key. Store in the Keychain; never write elsewhere.
    public let vaultKey: Data
    /// The formatted recovery key (grouped, checksummed). Show once, then let it
    /// leave scope. Never persisted in plaintext.
    public let recoveryKeyDisplay: String

    public init(config: VaultConfig, vaultKey: Data, recoveryKeyDisplay: String) {
        self.config = config
        self.vaultKey = vaultKey
        self.recoveryKeyDisplay = recoveryKeyDisplay
    }
}

// MARK: - Crypto seam

/// The cryptographic operations onboarding needs, behind a protocol so the flow
/// (and its tests) never link the Rust FFI directly.
///
/// The production conformer lives in the app target and calls the
/// UniFFI-generated `pildora-crypto` bindings (Argon2id → master key → sub-keys,
/// vault-key generation + wrapping, and recovery-key wrapping). Tests and
/// previews use ``StubOnboardingCrypto``, a deterministic pure-Swift fake.
///
/// Implementations perform slow key derivation (Argon2id), so callers should
/// invoke `createVault` off the main actor.
public protocol OnboardingCrypto: Sendable {
    /// Derive keys from `password` and assemble a new vault: generate a random
    /// vault key, wrap it with the MEK, generate a recovery key, and wrap the MEK
    /// with it. All recovery/raw key material is zeroized internally once the
    /// display string and wrapped blobs have been produced.
    func createVault(password: String, vaultID: String, vaultName: String) throws -> VaultSetup
}

/// Errors surfaced by an ``OnboardingCrypto`` implementation.
public enum OnboardingCryptoError: Error, Equatable {
    /// A cryptographic primitive failed. `message` is a redacted, user-safe
    /// summary — it never contains key material.
    case cryptoFailure(String)
}
