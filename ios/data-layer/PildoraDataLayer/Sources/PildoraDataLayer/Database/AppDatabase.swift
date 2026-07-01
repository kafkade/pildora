import Foundation
import GRDB

// MARK: - AppDatabase

/// The encrypted, vault-scoped persistence layer for a single vault.
///
/// An `AppDatabase` wraps one GRDB `DatabaseQueue` backed by one SQLCipher
/// database file. The file is encrypted with a key derived from the vault key
/// (see `DatabaseKeyDeriving`); combined with `VaultDatabaseManager`'s
/// one-vault-one-file layout, this makes the vault a hard encryption boundary —
/// no cross-vault data can leak, and deleting a vault is deleting a file.
///
/// ## Encryption
/// Encryption is active when the package is compiled against a SQLCipher-backed
/// GRDB with the `GRDBCIPHER` condition defined (the Xcode app target). Under
/// plain `swift test` the same code runs on unencrypted SQLite, so the data
/// model, migrations, and CRUD are fully exercised while the on-disk cipher is
/// validated in the app.
public struct AppDatabase: Sendable {
    /// The underlying GRDB queue. Exposed for advanced/read-only composition;
    /// prefer the typed CRUD methods below.
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Opening

    /// Open (creating if needed) the encrypted database for a vault.
    ///
    /// - Parameters:
    ///   - path: Filesystem path to the vault's `.db` file.
    ///   - vaultKey: The 32-byte vault key from `pildora-crypto`.
    ///   - keyDeriver: Derives the SQLCipher key from the vault key.
    ///   - fileProtection: Whether to apply iOS Data Protection to the file
    ///     (no-op on macOS). Defaults to `true`.
    public static func open(
        at path: String,
        vaultKey: Data,
        keyDeriver: DatabaseKeyDeriving,
        fileProtection: Bool = true
    ) throws -> AppDatabase {
        guard vaultKey.count == DataLayerConstants.vaultKeyLength else {
            throw DataLayerError.invalidVaultKeyLength(vaultKey.count)
        }

        // Derive the passphrase up front. This validates the deriver and, under
        // SQLCipher, is the key that encrypts every page.
        let passphrase = try keyDeriver.databasePassphrase(vaultKey: vaultKey)

        var config = Configuration()
        config.prepareDatabase { db in
            #if GRDBCIPHER
            try db.usePassphrase(passphrase)
            #endif
            // WAL enables concurrent reads during UI rendering; enforce FKs so
            // cascade rules actually run.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        // Silence the unused-variable warning when GRDBCIPHER is not defined.
        _ = passphrase

        let dbQueue = try DatabaseQueue(path: path, configuration: config)

        if fileProtection {
            applyFileProtection(to: path)
        }

        let appDb = AppDatabase(dbQueue: dbQueue)
        try appDb.migrate()
        return appDb
    }

    /// Apply the migration set. Safe to call repeatedly; each migration runs once.
    public func migrate() throws {
        try SchemaMigrations.makeMigrator().migrate(dbQueue)
    }

    /// The `PRAGMA cipher_version`, when built against SQLCipher; otherwise nil.
    public func cipherVersion() throws -> String? {
        #if GRDBCIPHER
        return try dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA cipher_version")
        }
        #else
        return nil
        #endif
    }

    private static func applyFileProtection(to path: String) {
        #if os(iOS)
        // Layer OS-level Data Protection on top of SQLCipher: the file is also
        // unreadable until first unlock after boot.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: path
        )
        #endif
    }
}

// MARK: - Vault CRUD

public extension AppDatabase {
    func insertVault(_ vault: Vault) throws {
        try dbQueue.write { db in try vault.insert(db) }
    }

    func fetchVault(id: String) throws -> Vault? {
        try dbQueue.read { db in try Vault.fetchOne(db, id: id) }
    }

    func fetchAllVaults() throws -> [Vault] {
        try dbQueue.read { db in
            try Vault.order(Vault.Columns.name).fetchAll(db)
        }
    }

    @discardableResult
    func updateVault(_ vault: Vault) throws -> Vault {
        var updated = vault
        updated.updatedAt = Date()
        try dbQueue.write { db in try updated.update(db) }
        return updated
    }

    @discardableResult
    func deleteVault(id: String) throws -> Bool {
        try dbQueue.write { db in try Vault.deleteOne(db, id: id) }
    }
}

// MARK: - Medication CRUD

public extension AppDatabase {
    func insertMedication(_ medication: Medication) throws {
        try dbQueue.write { db in try medication.insert(db) }
    }

    func insertMedications(_ medications: [Medication]) throws {
        try dbQueue.write { db in
            for medication in medications { try medication.insert(db) }
        }
    }

    func fetchMedication(id: String) throws -> Medication? {
        try dbQueue.read { db in try Medication.fetchOne(db, id: id) }
    }

    /// All medications in a vault, ordered by name.
    func fetchMedications(vaultId: String) throws -> [Medication] {
        try dbQueue.read { db in
            try Medication
                .filter(Medication.Columns.vaultId == vaultId)
                .order(Medication.Columns.name)
                .fetchAll(db)
        }
    }

    @discardableResult
    func updateMedication(_ medication: Medication) throws -> Medication {
        var updated = medication
        updated.updatedAt = Date()
        try dbQueue.write { db in try updated.update(db) }
        return updated
    }

    @discardableResult
    func deleteMedication(id: String) throws -> Bool {
        try dbQueue.write { db in try Medication.deleteOne(db, id: id) }
    }

    func medicationCount(vaultId: String) throws -> Int {
        try dbQueue.read { db in
            try Medication.filter(Medication.Columns.vaultId == vaultId).fetchCount(db)
        }
    }
}

// MARK: - Schedule CRUD

public extension AppDatabase {
    func insertSchedule(_ schedule: Schedule) throws {
        try dbQueue.write { db in try schedule.insert(db) }
    }

    func fetchSchedules(medicationId: String) throws -> [Schedule] {
        try dbQueue.read { db in
            try Schedule
                .filter(Schedule.Columns.medicationId == medicationId)
                .order(Schedule.Columns.startDate)
                .fetchAll(db)
        }
    }

    func fetchSchedules(vaultId: String) throws -> [Schedule] {
        try dbQueue.read { db in
            try Schedule.filter(Schedule.Columns.vaultId == vaultId).fetchAll(db)
        }
    }

    @discardableResult
    func updateSchedule(_ schedule: Schedule) throws -> Schedule {
        var updated = schedule
        updated.updatedAt = Date()
        try dbQueue.write { db in try updated.update(db) }
        return updated
    }

    @discardableResult
    func deleteSchedule(id: String) throws -> Bool {
        try dbQueue.write { db in try Schedule.deleteOne(db, id: id) }
    }
}

// MARK: - DoseLog CRUD

public extension AppDatabase {
    func insertDoseLog(_ doseLog: DoseLog) throws {
        try dbQueue.write { db in try doseLog.insert(db) }
    }

    func insertDoseLogs(_ doseLogs: [DoseLog]) throws {
        try dbQueue.write { db in
            for doseLog in doseLogs { try doseLog.insert(db) }
        }
    }

    func fetchDoseLog(id: String) throws -> DoseLog? {
        try dbQueue.read { db in try DoseLog.fetchOne(db, id: id) }
    }

    /// Dose logs for a medication within an inclusive date range, oldest first.
    func fetchDoseLogs(
        medicationId: String,
        from startDate: Date,
        to endDate: Date
    ) throws -> [DoseLog] {
        try dbQueue.read { db in
            try DoseLog
                .filter(DoseLog.Columns.medicationId == medicationId)
                .filter(DoseLog.Columns.recordedAt >= startDate)
                .filter(DoseLog.Columns.recordedAt <= endDate)
                .order(DoseLog.Columns.recordedAt)
                .fetchAll(db)
        }
    }

    /// All dose logs recorded within a day (vault-scoped), oldest first.
    func fetchDoseLogs(vaultId: String, on day: Date, calendar: Calendar = .current) throws -> [DoseLog] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try dbQueue.read { db in
            try DoseLog
                .filter(DoseLog.Columns.vaultId == vaultId)
                .filter(DoseLog.Columns.recordedAt >= start)
                .filter(DoseLog.Columns.recordedAt < end)
                .order(DoseLog.Columns.recordedAt)
                .fetchAll(db)
        }
    }

    @discardableResult
    func deleteDoseLog(id: String) throws -> Bool {
        try dbQueue.write { db in try DoseLog.deleteOne(db, id: id) }
    }

    func doseLogCount(vaultId: String) throws -> Int {
        try dbQueue.read { db in
            try DoseLog.filter(DoseLog.Columns.vaultId == vaultId).fetchCount(db)
        }
    }
}

// MARK: - Inventory CRUD

public extension AppDatabase {
    /// Insert or update the inventory record for a medication.
    func upsertInventory(_ record: InventoryRecord) throws {
        var updated = record
        updated.updatedAt = Date()
        try dbQueue.write { db in try updated.save(db) }
    }

    func fetchInventory(medicationId: String) throws -> InventoryRecord? {
        try dbQueue.read { db in
            try InventoryRecord
                .filter(InventoryRecord.Columns.medicationId == medicationId)
                .fetchOne(db)
        }
    }

    func fetchInventory(vaultId: String) throws -> [InventoryRecord] {
        try dbQueue.read { db in
            try InventoryRecord.filter(InventoryRecord.Columns.vaultId == vaultId).fetchAll(db)
        }
    }

    @discardableResult
    func deleteInventory(id: String) throws -> Bool {
        try dbQueue.write { db in try InventoryRecord.deleteOne(db, id: id) }
    }
}
