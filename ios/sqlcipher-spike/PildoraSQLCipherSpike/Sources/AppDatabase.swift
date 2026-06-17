import Foundation
import GRDB

struct AppDatabase {
    let dbQueue: DatabaseQueue

    /// Opens (or creates) an encrypted database.
    ///
    /// In production the passphrase is derived from the vault key:
    ///   vaultKey → HKDF-SHA256(info: "pildora-sqlcipher-db-key") → hex string
    ///
    /// For the spike we accept any passphrase string.
    static func open(at path: String, passphrase: String?) throws -> AppDatabase {
        var config = Configuration()

        #if GRDBCIPHER
        if let passphrase {
            config.prepareDatabase { db in
                try db.usePassphrase(passphrase)
            }
        }
        #else
        if passphrase != nil {
            print("  ⚠️  GRDBCIPHER not enabled — running without encryption")
            print("     (link against SQLCipher and define GRDBCIPHER to enable)")
        }
        #endif

        config.prepareDatabase { db in
            // WAL mode for concurrent reads during UI rendering
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let dbQueue = try DatabaseQueue(path: path, configuration: config)
        let appDb = AppDatabase(dbQueue: dbQueue)
        try appDb.migrate()
        return appDb
    }

    // MARK: - Schema migrations

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        // Always reset the database in spike mode so runs are reproducible.
        // In production: migrator.eraseDatabaseOnSchemaChange = false
        migrator.eraseDatabaseOnSchemaChange = true

        migrator.registerMigration("v1-core-tables") { db in
            try db.create(table: "medication") { t in
                t.primaryKey("id", .text)
                t.column("vaultId", .text).notNull().indexed()
                t.column("name", .text).notNull()
                t.column("genericName", .text)
                t.column("dosage", .text).notNull()
                t.column("form", .text).notNull().defaults(to: "tablet")
                t.column("frequency", .text).notNull().defaults(to: "daily")
                t.column("prescriber", .text)
                t.column("pharmacy", .text)
                t.column("notes", .text)
                t.column("rxnormId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "schedule") { t in
                t.primaryKey("id", .text)
                t.column("medicationId", .text).notNull()
                    .references("medication", onDelete: .cascade)
                t.column("pattern", .text).notNull()
                t.column("timesJson", .text).notNull()
                t.column("daysJson", .text)
                t.column("intervalDays", .integer)
                t.column("startDate", .text).notNull()
                t.column("endDate", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "dose_log") { t in
                t.primaryKey("id", .text)
                t.column("medicationId", .text).notNull()
                    .references("medication", onDelete: .cascade)
                t.column("scheduleId", .text)
                    .references("schedule", onDelete: .setNull)
                t.column("scheduledAt", .datetime)
                t.column("recordedAt", .datetime).notNull()
                t.column("status", .text).notNull()
                t.column("skipReason", .text)
                t.column("notes", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "inventory") { t in
                t.primaryKey("id", .text)
                t.column("medicationId", .text).notNull().unique()
                    .references("medication", onDelete: .cascade)
                t.column("currentCount", .integer).notNull()
                t.column("refillThreshold", .integer)
                t.column("lastRefillDate", .text)
                t.column("updatedAt", .datetime).notNull()
            }

            // Index for the today-view query: dose logs by date
            try db.create(
                index: "idx_dose_log_recorded",
                on: "dose_log",
                columns: ["recordedAt"]
            )
        }

        try migrator.migrate(dbQueue)
    }

    // MARK: - Medication CRUD

    func insertMedication(_ med: inout Medication) throws {
        try dbQueue.write { db in
            try med.insert(db)
        }
    }

    func fetchMedication(id: String) throws -> Medication? {
        try dbQueue.read { db in
            try Medication.fetchOne(db, id: id)
        }
    }

    func fetchMedications(vaultId: String) throws -> [Medication] {
        try dbQueue.read { db in
            try Medication
                .filter(Medication.Columns.vaultId == vaultId)
                .order(Medication.Columns.name)
                .fetchAll(db)
        }
    }

    func updateMedication(_ med: inout Medication) throws {
        med.updatedAt = Date()
        try dbQueue.write { db in
            try med.update(db)
        }
    }

    func deleteMedication(id: String) throws -> Bool {
        try dbQueue.write { db in
            try Medication.deleteOne(db, id: id)
        }
    }

    // MARK: - Schedule CRUD

    func insertSchedule(_ schedule: inout Schedule) throws {
        try dbQueue.write { db in
            try schedule.insert(db)
        }
    }

    func fetchSchedules(medicationId: String) throws -> [Schedule] {
        try dbQueue.read { db in
            try Schedule
                .filter(Schedule.Columns.medicationId == medicationId)
                .fetchAll(db)
        }
    }

    // MARK: - DoseLog CRUD

    func insertDoseLog(_ log: inout DoseLog) throws {
        try dbQueue.write { db in
            try log.insert(db)
        }
    }

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

    func fetchTodayDoses() throws -> [DoseLog] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return try dbQueue.read { db in
            try DoseLog
                .filter(DoseLog.Columns.recordedAt >= startOfDay)
                .filter(DoseLog.Columns.recordedAt < endOfDay)
                .order(DoseLog.Columns.recordedAt)
                .fetchAll(db)
        }
    }

    // MARK: - Inventory CRUD

    func upsertInventory(_ record: inout InventoryRecord) throws {
        try dbQueue.write { db in
            try record.save(db)
        }
    }

    // MARK: - Batch operations

    func insertMedications(_ meds: inout [Medication]) throws {
        try dbQueue.write { db in
            for i in meds.indices {
                try meds[i].insert(db)
            }
        }
    }

    // MARK: - Counts

    func medicationCount() throws -> Int {
        try dbQueue.read { db in
            try Medication.fetchCount(db)
        }
    }

    func doseLogCount() throws -> Int {
        try dbQueue.read { db in
            try DoseLog.fetchCount(db)
        }
    }

    // MARK: - Database info

    func fileSize() throws -> Int64 {
        let attrs = try FileManager.default.attributesOfItem(
            atPath: dbQueue.path
        )
        return (attrs[.size] as? Int64) ?? 0
    }

    #if GRDBCIPHER
    func cipherVersion() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(db, sql: "PRAGMA cipher_version")
        }
    }
    #endif
}
