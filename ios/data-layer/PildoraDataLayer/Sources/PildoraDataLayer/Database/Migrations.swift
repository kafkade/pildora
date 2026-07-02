import Foundation
import GRDB

// MARK: - Migrations

/// Owns the versioned schema for a vault database.
///
/// New schema changes are added as additional `registerMigration` blocks with a
/// new identifier — never by editing an existing migration. `DatabaseMigrator`
/// records which migrations have run, so each one applies exactly once and
/// existing user databases upgrade in place. `eraseDatabaseOnSchemaChange` is
/// deliberately left off (the default) in production so data is preserved.
enum SchemaMigrations {
    /// The current schema version identifier (latest registered migration).
    static let currentVersion = "v2"

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerV1(&migrator)
        registerV2(&migrator)
        return migrator
    }

    // MARK: v1 — core encrypted data model

    private static func registerV1(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1-core-tables") { db in
            try db.create(table: "vault") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("icon", .text)
                t.column("color", .text)
                t.column("profileType", .text).notNull().defaults(to: "personal")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "medication") { t in
                t.primaryKey("id", .text)
                t.column("vaultId", .text).notNull()
                    .indexed()
                    .references("vault", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("genericName", .text)
                t.column("dosage", .text).notNull()
                t.column("form", .text).notNull().defaults(to: "tablet")
                t.column("category", .text).notNull().defaults(to: "prescription")
                t.column("frequency", .text).notNull().defaults(to: "Once daily")
                t.column("prescriber", .text)
                t.column("pharmacy", .text)
                t.column("notes", .text)
                t.column("rxnormId", .text)
                t.column("drugReferenceId", .text)
                t.column("startDate", .datetime)
                t.column("endDate", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "schedule") { t in
                t.primaryKey("id", .text)
                t.column("medicationId", .text).notNull()
                    .indexed()
                    .references("medication", onDelete: .cascade)
                t.column("vaultId", .text).notNull().indexed()
                    .references("vault", onDelete: .cascade)
                t.column("pattern", .text).notNull().defaults(to: "daily")
                t.column("timesJson", .text).notNull().defaults(to: "[]")
                t.column("daysJson", .text)
                t.column("intervalDays", .integer)
                t.column("startDate", .datetime).notNull()
                t.column("endDate", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "dose_log") { t in
                t.primaryKey("id", .text)
                t.column("medicationId", .text).notNull()
                    .references("medication", onDelete: .cascade)
                t.column("scheduleId", .text)
                    .references("schedule", onDelete: .setNull)
                t.column("vaultId", .text).notNull().indexed()
                    .references("vault", onDelete: .cascade)
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
                t.column("vaultId", .text).notNull().indexed()
                    .references("vault", onDelete: .cascade)
                t.column("currentCount", .integer).notNull()
                t.column("refillThreshold", .integer)
                t.column("lastRefillDate", .datetime)
                t.column("updatedAt", .datetime).notNull()
            }

            // Composite index for the common "this medication's recent doses" and
            // today-view queries (medication + time range).
            try db.create(
                index: "idx_dose_log_medication_recorded",
                on: "dose_log",
                columns: ["medicationId", "recordedAt"]
            )
        }
    }

    // MARK: v2 — per-medication refill-reminder toggle

    /// Adds the `refillReminderEnabled` flag to `inventory` so the medication
    /// list can persist whether a local refill reminder is scheduled for each
    /// medication (previously an in-memory-only concern). Existing rows default
    /// to enabled to preserve prior behavior.
    private static func registerV2(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2-inventory-refill-reminder") { db in
            try db.alter(table: "inventory") { t in
                t.add(column: "refillReminderEnabled", .boolean)
                    .notNull()
                    .defaults(to: true)
            }
        }
    }
}
