import GRDB
import XCTest
@testable import PildoraDataLayer

/// Verifies the versioned migration framework: the v1 schema is created, is
/// applied exactly once, and is idempotent across reopens.
final class MigrationTests: XCTestCase {
    private var url: URL!
    private var db: AppDatabase!

    override func setUpWithError() throws {
        (db, url) = try TestFixtures.makeDatabase()
    }

    override func tearDownWithError() throws {
        db = nil
        TestFixtures.remove(at: url)
    }

    func testV1CreatesAllTables() throws {
        let expected = ["vault", "medication", "schedule", "dose_log", "inventory"]
        let tables = try db.dbQueue.read { database -> Set<String> in
            let names = try String.fetchAll(
                database,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
            return Set(names)
        }
        for table in expected {
            XCTAssertTrue(tables.contains(table), "missing table \(table)")
        }
    }

    func testMigrationIsRecordedAndIdempotent() throws {
        let applied = try db.dbQueue.read { try SchemaMigrations.makeMigrator().appliedMigrations($0) }
        XCTAssertEqual(applied, ["v1-core-tables", "v2-inventory-refill-reminder"])

        // Re-running migrations must be a safe no-op.
        XCTAssertNoThrow(try db.migrate())
        let appliedAgain = try db.dbQueue.read { try SchemaMigrations.makeMigrator().appliedMigrations($0) }
        XCTAssertEqual(appliedAgain, ["v1-core-tables", "v2-inventory-refill-reminder"])
    }

    func testV2AddsRefillReminderColumnDefaultingEnabled() throws {
        try TestFixtures.seedVault(db, id: "vault-1")
        let med = Medication(id: "med-1", vaultId: "vault-1", name: "Metformin", dosage: "500 mg")
        try db.insertMedication(med)

        // A record inserted without specifying the flag persists the column and
        // round-trips as enabled (the migration default).
        let record = InventoryRecord(
            medicationId: "med-1",
            vaultId: "vault-1",
            currentCount: 30,
            refillThreshold: 5
        )
        try db.upsertInventory(record)

        let fetched = try db.fetchInventory(medicationId: "med-1")
        XCTAssertEqual(fetched?.refillReminderEnabled, true)

        // The flag persists when explicitly disabled.
        var disabled = try XCTUnwrap(fetched)
        disabled.refillReminderEnabled = false
        try db.upsertInventory(disabled)
        XCTAssertEqual(try db.fetchInventory(medicationId: "med-1")?.refillReminderEnabled, false)
    }

    func testReopeningPreservesDataAndSchema() throws {
        try TestFixtures.seedVault(db, id: "vault-keep")
        db = nil // close the queue

        // Reopen the same file: migrations already applied, data intact.
        let reopened = try AppDatabase.open(
            at: url.path,
            vaultKey: TestFixtures.vaultKey(),
            keyDeriver: HKDFTestKeyDeriver(),
            fileProtection: false
        )
        defer { /* url cleaned in tearDown */ }
        db = reopened
        XCTAssertNotNil(try reopened.fetchVault(id: "vault-keep"))
    }

    func testForeignKeysAreEnforced() throws {
        // Inserting a medication for a nonexistent vault must fail the FK check.
        let orphan = Medication(vaultId: "does-not-exist", name: "Orphan", dosage: "1")
        XCTAssertThrowsError(try db.insertMedication(orphan))
    }
}
