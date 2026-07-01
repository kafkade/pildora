import Foundation

// MARK: - DatabaseKeyDeriving

/// Derives the 32-byte SQLCipher database key from a vault key.
///
/// This is the seam that keeps `PildoraDataLayer` decoupled from the Rust
/// crypto FFI static library, so the package builds and runs under
/// command-line `swift test` with no native linkage. In the shipping app, a
/// conforming adapter forwards to the `pildora-crypto-ffi`
/// `deriveSqlcipherKey(vaultKey:)` function (HKDF-SHA256 with the
/// `pildora-sqlcipher-db-key` domain label). Tests inject a deterministic
/// double.
///
/// Example app-side adapter:
/// ```swift
/// import pildora_crypto_ffi
///
/// struct FFIDatabaseKeyDeriver: DatabaseKeyDeriving {
///     func deriveDatabaseKey(vaultKey: Data) throws -> Data {
///         try deriveSqlcipherKey(vaultKey: vaultKey)
///     }
/// }
/// ```
public protocol DatabaseKeyDeriving: Sendable {
    /// Derive a 32-byte database key from a 32-byte vault key.
    ///
    /// Implementations MUST be deterministic and domain-separated: the returned
    /// key must differ from the input vault key and from any other derived key.
    func deriveDatabaseKey(vaultKey: Data) throws -> Data
}

public extension DatabaseKeyDeriving {
    /// The SQLCipher passphrase for a vault: the derived key, lowercase-hex encoded.
    ///
    /// SQLCipher accepts a passphrase string and runs its own KDF over it, so a
    /// hex-encoded high-entropy key is a safe, portable passphrase.
    func databasePassphrase(vaultKey: Data) throws -> String {
        let key = try deriveDatabaseKey(vaultKey: vaultKey)
        guard key.count == DataLayerConstants.databaseKeyLength else {
            throw DataLayerError.invalidDerivedKeyLength(key.count)
        }
        return key.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Constants

public enum DataLayerConstants {
    /// Required length of both the vault key and the derived database key.
    public static let vaultKeyLength = 32
    public static let databaseKeyLength = 32
}

// MARK: - Errors

/// Errors surfaced by the encrypted data layer.
public enum DataLayerError: Error, Equatable, Sendable {
    /// The supplied vault key was not exactly 32 bytes.
    case invalidVaultKeyLength(Int)
    /// A `DatabaseKeyDeriving` implementation returned a key of the wrong length.
    case invalidDerivedKeyLength(Int)
}
