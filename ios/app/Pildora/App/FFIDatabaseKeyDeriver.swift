import Foundation
import PildoraDataLayer

/// Adapts the Rust crypto FFI to `PildoraDataLayer`'s key-derivation seam.
///
/// Forwards to `deriveSqlcipherKey` (HKDF-SHA256 with the
/// `pildora-sqlcipher-db-key` domain label), keeping the SQLCipher key path
/// intact regardless of whether the app is currently linking SQLCipher.
struct FFIDatabaseKeyDeriver: DatabaseKeyDeriving {
    func deriveDatabaseKey(vaultKey: Data) throws -> Data {
        try deriveSqlcipherKey(vaultKey: vaultKey)
    }
}
