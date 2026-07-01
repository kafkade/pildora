import XCTest
@testable import PildoraDataLayer

/// Exercises CRUD and encryption roundtrip for every entity, plus cascade
/// deletes and vault-scoped isolation.
final class CRUDTests: XCTestCase {
    private var url: URL!
    private var db: AppDatabase!

    override func setUpWithError() throws {
        (db, url) = try TestFixtures.makeDatabase()
        try TestFixtures.seedVault(db, id: "vault-1", name: "Personal")
    }

    override func tearDownWithError() throws {
        db = nil
        TestFixtures.remove(at: url)
    }

    // MARK: Vault

    func testVaultRoundtrip() throws {
        var vault = try db.fetchVault(id: "vault-1")
        XCTAssertEqual(vault?.name, "Personal")

        let before = Date()
        vault?.name = "Renamed"
        let updated = try db.updateVault(vault!)
        XCTAssertEqual(try db.fetchVault(id: "vault-1")?.name, "Renamed")
        // updateVault stamps updatedAt to "now", which is at or after `before`.
        XCTAssertGreaterThanOrEqual(updated.updatedAt, before)
    }

    // MARK: Medication

    func testMedicationRoundtripPreservesAllFields() throws {
        // Use whole-second timestamps: GRDB persists dates with millisecond
        // precision, so sub-millisecond components of `Date()` wouldn't survive
        // a roundtrip and would defeat an exact-equality check.
        let fixed = Date(timeIntervalSince1970: 1_700_000_100)
        let med = Medication(
            id: "med-1",
            vaultId: "vault-1",
            name: "Levothyroxine",
            genericName: "levothyroxine sodium",
            dosage: "88 mcg",
            form: .tablet,
            category: .prescription,
            frequency: "Once daily",
            prescriber: "Dr. Rivera",
            pharmacy: "Central Pharmacy",
            notes: "Take on empty stomach",
            rxnormId: "10582",
            drugReferenceId: "ref-99",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            createdAt: fixed,
            updatedAt: fixed
        )
        try db.insertMedication(med)

        let fetched = try XCTUnwrap(try db.fetchMedication(id: "med-1"))
        XCTAssertEqual(fetched, med)
        XCTAssertEqual(fetched.form, .tablet)
        XCTAssertEqual(fetched.category, .prescription)
        XCTAssertEqual(fetched.rxnormId, "10582")
    }

    func testMedicationUpdateAndDelete() throws {
        var med = Medication(id: "med-1", vaultId: "vault-1", name: "Aspirin", dosage: "81 mg")
        try db.insertMedication(med)

        med.dosage = "100 mg"
        try db.updateMedication(med)
        XCTAssertEqual(try db.fetchMedication(id: "med-1")?.dosage, "100 mg")

        XCTAssertTrue(try db.deleteMedication(id: "med-1"))
        XCTAssertNil(try db.fetchMedication(id: "med-1"))
    }

    // MARK: Schedule

    func testScheduleRoundtrip() throws {
        try db.insertMedication(Medication(id: "med-1", vaultId: "vault-1", name: "Metformin", dosage: "500 mg"))
        let schedule = Schedule.daily(medicationId: "med-1", vaultId: "vault-1", times: ["08:00", "20:00"])
        try db.insertSchedule(schedule)

        let fetched = try XCTUnwrap(try db.fetchSchedules(medicationId: "med-1").first)
        XCTAssertEqual(fetched.pattern, .daily)
        XCTAssertEqual(fetched.times, ["08:00", "20:00"])
    }

    // MARK: DoseLog

    func testDoseLogRoundtripAndRangeQuery() throws {
        try db.insertMedication(Medication(id: "med-1", vaultId: "vault-1", name: "Vitamin D", dosage: "2000 IU"))
        let day0 = Date(timeIntervalSince1970: 1_700_000_000)
        let logs = (0..<3).map { i in
            DoseLog(
                medicationId: "med-1",
                vaultId: "vault-1",
                recordedAt: day0.addingTimeInterval(Double(i) * 86_400),
                status: .taken
            )
        }
        try db.insertDoseLogs(logs)

        let inRange = try db.fetchDoseLogs(
            medicationId: "med-1",
            from: day0,
            to: day0.addingTimeInterval(86_400)
        )
        XCTAssertEqual(inRange.count, 2)
        XCTAssertEqual(try db.doseLogCount(vaultId: "vault-1"), 3)
    }

    func testPRNDoseLogHasNoSchedule() throws {
        try db.insertMedication(Medication(id: "med-1", vaultId: "vault-1", name: "Ibuprofen", dosage: "200 mg"))
        let prn = DoseLog.taken(medicationId: "med-1", vaultId: "vault-1", scheduleId: nil)
        try db.insertDoseLog(prn)
        let fetched = try XCTUnwrap(try db.fetchDoseLog(id: prn.id))
        XCTAssertNil(fetched.scheduleId)
        XCTAssertNil(fetched.scheduledAt)
    }

    // MARK: Inventory

    func testInventoryUpsertAndLowStock() throws {
        try db.insertMedication(Medication(id: "med-1", vaultId: "vault-1", name: "Sertraline", dosage: "50 mg"))
        var inv = InventoryRecord(medicationId: "med-1", vaultId: "vault-1", currentCount: 30, refillThreshold: 10)
        try db.upsertInventory(inv)
        XCTAssertFalse(try XCTUnwrap(try db.fetchInventory(medicationId: "med-1")).isLow)

        inv.currentCount = 8
        try db.upsertInventory(inv)
        let refetched = try XCTUnwrap(try db.fetchInventory(medicationId: "med-1"))
        XCTAssertEqual(refetched.currentCount, 8)
        XCTAssertTrue(refetched.isLow)
    }

    // MARK: Cascades & scoping

    func testDeletingMedicationCascadesToChildren() throws {
        try db.insertMedication(Medication(id: "med-1", vaultId: "vault-1", name: "Med", dosage: "1"))
        try db.insertSchedule(Schedule.daily(medicationId: "med-1", vaultId: "vault-1", times: ["08:00"]))
        try db.insertDoseLog(DoseLog.taken(medicationId: "med-1", vaultId: "vault-1"))
        try db.upsertInventory(InventoryRecord(medicationId: "med-1", vaultId: "vault-1", currentCount: 5))

        try db.deleteMedication(id: "med-1")

        XCTAssertTrue(try db.fetchSchedules(medicationId: "med-1").isEmpty)
        XCTAssertEqual(try db.doseLogCount(vaultId: "vault-1"), 0)
        XCTAssertNil(try db.fetchInventory(medicationId: "med-1"))
    }

    func testDeletingVaultCascadesToAllHealthData() throws {
        try db.insertMedication(Medication(id: "med-1", vaultId: "vault-1", name: "Med", dosage: "1"))
        try db.insertSchedule(Schedule.daily(medicationId: "med-1", vaultId: "vault-1", times: ["08:00"]))
        try db.insertDoseLog(DoseLog.taken(medicationId: "med-1", vaultId: "vault-1"))

        try db.deleteVault(id: "vault-1")

        XCTAssertEqual(try db.medicationCount(vaultId: "vault-1"), 0)
        XCTAssertTrue(try db.fetchSchedules(vaultId: "vault-1").isEmpty)
        XCTAssertEqual(try db.doseLogCount(vaultId: "vault-1"), 0)
    }

    func testVaultScopedQueriesIsolateVaults() throws {
        try TestFixtures.seedVault(db, id: "vault-2", name: "Mom")
        try db.insertMedication(Medication(vaultId: "vault-1", name: "A", dosage: "1"))
        try db.insertMedication(Medication(vaultId: "vault-1", name: "B", dosage: "1"))
        try db.insertMedication(Medication(vaultId: "vault-2", name: "C", dosage: "1"))

        XCTAssertEqual(try db.medicationCount(vaultId: "vault-1"), 2)
        XCTAssertEqual(try db.medicationCount(vaultId: "vault-2"), 1)
        XCTAssertEqual(try db.fetchMedications(vaultId: "vault-2").map(\.name), ["C"])
    }
}
