import Foundation

// MARK: - VaultDatabaseManager

/// Manages the one-vault-one-file layout of encrypted vault databases.
///
/// Each vault is stored as its own SQLCipher file under a base directory
/// (Application Support by default). This gives every vault an independent
/// encryption boundary and makes vault deletion a file delete. The manager only
/// knows how to locate, open, and remove vault files — the vault key lives with
/// the caller and is never persisted.
public struct VaultDatabaseManager: Sendable {
    /// Directory that holds the per-vault database files.
    public let directory: URL
    private let keyDeriver: DatabaseKeyDeriving
    private let fileProtection: Bool

    /// - Parameters:
    ///   - directory: Where vault files live. Defaults to
    ///     `Application Support/PildoraVaults`.
    ///   - keyDeriver: Derives each vault's SQLCipher key from its vault key.
    ///   - fileProtection: Apply iOS Data Protection to created files.
    public init(
        directory: URL? = nil,
        keyDeriver: DatabaseKeyDeriving,
        fileProtection: Bool = true
    ) throws {
        self.directory = try directory ?? Self.defaultDirectory()
        self.keyDeriver = keyDeriver
        self.fileProtection = fileProtection
    }

    /// Filesystem URL for a vault's database file.
    public func databaseURL(vaultId: String) -> URL {
        directory.appendingPathComponent("vault-\(vaultId).db", isDirectory: false)
    }

    /// True when a database file already exists for the vault.
    public func databaseExists(vaultId: String) -> Bool {
        FileManager.default.fileExists(atPath: databaseURL(vaultId: vaultId).path)
    }

    /// Open (creating if needed) the encrypted database for a vault.
    public func open(vaultId: String, vaultKey: Data) throws -> AppDatabase {
        try ensureDirectoryExists()
        return try AppDatabase.open(
            at: databaseURL(vaultId: vaultId).path,
            vaultKey: vaultKey,
            keyDeriver: keyDeriver,
            fileProtection: fileProtection
        )
    }

    /// Permanently delete a vault by removing its database file (and WAL/SHM
    /// sidecars). Returns `true` if a file was removed.
    @discardableResult
    public func deleteDatabase(vaultId: String) throws -> Bool {
        let base = databaseURL(vaultId: vaultId)
        let fm = FileManager.default
        var removed = false
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: base.path + suffix)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
                removed = true
            }
        }
        return removed
    }

    private func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private static func defaultDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("PildoraVaults", isDirectory: true)
    }
}
