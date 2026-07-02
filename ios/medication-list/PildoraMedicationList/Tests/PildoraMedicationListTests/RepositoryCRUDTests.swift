import Foundation
import PildoraDataLayer
import XCTest
@testable import PildoraMedicationList

/// A deterministic key deriver for opening a plain-SQLite `AppDatabase` under
/// `swift test` (encryption itself is validated in `PildoraDataLayer`).
private struct FixedKeyDeriver: DatabaseKeyDeriving {
    func deriveDatabaseKey(vaultKey: Data) throws -> Data {
        // Domain-separate from the vault key by reversing it — length preserved.
        Data(vaultKey.reversed())
    }
}

/// Exercises the persistence seam: the store's add/update/delete write through a
/// repository, and a database-backed repository cascades deletes to child rows.
@MainActor
final class RepositoryCRUDTests: XCTestCase {

    // MARK: In-memory store CRUD

    func testAddMedicationPersistsAndAppears() {
        let store = MedicationStore(medications: [], inventory: [], references: [])
        let med = Medication(id: "m1", vaultId: "v1", name: "Sertraline", dosage: "50 mg")
        store.addMedication(med, inventory: InventoryRecord(medicationId: "m1", vaultId: "v1", currentCount: 30, refillThreshold: 5))

        XCTAssertTrue(store.medications.contains { $0.id == "m1" })
        XCTAssertEqual(store.inventory(for: "m1")?.currentCount, 30)
        XCTAssertNil(store.lastError)
    }

    func testUpdateMedicationReflectsImmediately() {
        let store = MedicationStore(medications: SampleData.medications, inventory: [], references: [])
        var med = try! XCTUnwrap(store.medications.first { $0.id == "med-2" })
        med.dosage = "1000 mg"
        med.notes = "With dinner"
        store.updateMedication(med)

        let updated = store.medications.first { $0.id == "med-2" }
        XCTAssertEqual(updated?.dosage, "1000 mg")
        XCTAssertEqual(updated?.notes, "With dinner")
    }

    func testDeleteMedicationRemovesItAndInventory() {
        let store = MedicationStore(
            medications: SampleData.medications,
            inventory: SampleData.inventory(),
            references: []
        )
        XCTAssertNotNil(store.inventory(for: "med-4"))
        store.deleteMedication(id: "med-4")
        XCTAssertFalse(store.medications.contains { $0.id == "med-4" })
        XCTAssertNil(store.inventory(for: "med-4"))
    }

    // MARK: Database-backed repository

    func testDatabaseRepositoryRoundTripsThroughStore() throws {
        let (db, url) = try makeDatabase()
        defer { removeDatabase(at: url) }
        try db.insertVault(Vault(id: "v1", name: "Personal"))

        let repo = DatabaseMedicationRepository(database: db, vaultId: "v1")
        let store = try MedicationStore(repository: repo)
        XCTAssertTrue(store.medications.isEmpty)

        store.addMedication(Medication(id: "m1", vaultId: "v1", name: "Lisinopril", dosage: "10 mg"))
        // A fresh store loaded from the same DB sees the persisted medication.
        let reopened = try MedicationStore(repository: DatabaseMedicationRepository(database: db, vaultId: "v1"))
        XCTAssertTrue(reopened.medications.contains { $0.id == "m1" })
    }

    func testDatabaseDeleteCascadesToSchedulesAndDoseLogs() throws {
        let (db, url) = try makeDatabase()
        defer { removeDatabase(at: url) }
        try db.insertVault(Vault(id: "v1", name: "Personal"))

        let repo = DatabaseMedicationRepository(database: db, vaultId: "v1")
        let store = try MedicationStore(repository: repo)
        store.addMedication(Medication(id: "m1", vaultId: "v1", name: "Metformin", dosage: "500 mg"))

        // Attach children directly, then delete via the store's repository.
        try db.insertSchedule(Schedule.daily(medicationId: "m1", vaultId: "v1", times: ["08:00"]))
        try db.insertDoseLog(DoseLog.taken(medicationId: "m1", vaultId: "v1"))
        XCTAssertEqual(try db.fetchSchedules(medicationId: "m1").count, 1)

        store.deleteMedication(id: "m1")

        XCTAssertNil(store.lastError)
        XCTAssertTrue(try db.fetchSchedules(medicationId: "m1").isEmpty)
        XCTAssertEqual(try db.doseLogCount(vaultId: "v1"), 0)
        XCTAssertNil(try db.fetchMedication(id: "m1"))
    }

    // MARK: Helpers

    private func makeDatabase() throws -> (AppDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("med-crud-\(UUID().uuidString).db")
        let db = try AppDatabase.open(
            at: url.path,
            vaultKey: Data(repeating: 7, count: 32),
            keyDeriver: FixedKeyDeriver(),
            fileProtection: false
        )
        return (db, url)
    }

    private func removeDatabase(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
