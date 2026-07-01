import CryptoKit
import Foundation
@testable import PildoraDataLayer

// MARK: - HKDFTestKeyDeriver

/// Test-side database-key deriver that reproduces, in pure Swift via CryptoKit,
/// the exact derivation the shipping app gets from the Rust FFI
/// (`deriveSqlcipherKey`): HKDF-SHA256 with a 32-byte zero salt and the
/// `pildora-sqlcipher-db-key` domain label.
///
/// Because it is byte-for-byte compatible with the Rust implementation (locked
/// by `KeyDerivingTests` against the shared known-answer vector), it lets the
/// package exercise the real derivation contract under `swift test` without
/// linking the FFI static library.
struct HKDFTestKeyDeriver: DatabaseKeyDeriving {
    static let info = Data("pildora-sqlcipher-db-key".utf8)

    func deriveDatabaseKey(vaultKey: Data) throws -> Data {
        guard vaultKey.count == DataLayerConstants.vaultKeyLength else {
            throw DataLayerError.invalidVaultKeyLength(vaultKey.count)
        }
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: vaultKey),
            salt: Data(repeating: 0, count: 32),
            info: Self.info,
            outputByteCount: 32
        )
        return key.withUnsafeBytes { Data($0) }
    }
}

// MARK: - Test fixtures

enum TestFixtures {
    /// A fixed, non-secret vault key for deterministic tests.
    static func vaultKey(byte: UInt8 = 0x01) -> Data {
        Data(repeating: byte, count: DataLayerConstants.vaultKeyLength)
    }

    /// Open a fresh AppDatabase backed by a unique temporary file. The returned
    /// URL should be passed to `remove(at:)` in `tearDown`.
    static func makeDatabase() throws -> (db: AppDatabase, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pildora-tests-\(UUID().uuidString).db")
        let db = try AppDatabase.open(
            at: url.path,
            vaultKey: vaultKey(),
            keyDeriver: HKDFTestKeyDeriver(),
            // Data Protection is a no-op off-device; keep it off for temp files.
            fileProtection: false
        )
        return (db, url)
    }

    static func remove(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: url.path + suffix)
        }
    }

    /// Insert a vault and return it, so FK-constrained rows can reference it.
    @discardableResult
    static func seedVault(_ db: AppDatabase, id: String = "vault-1", name: String = "Personal") throws -> Vault {
        let vault = Vault(id: id, name: name)
        try db.insertVault(vault)
        return vault
    }
}
