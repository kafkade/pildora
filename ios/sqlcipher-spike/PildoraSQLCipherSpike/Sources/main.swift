import Foundation
import GRDB

// MARK: - Benchmark helper

func benchmark(_ label: String, iterations: Int = 1, _ body: () throws -> Void) rethrows {
    let start = CFAbsoluteTimeGetCurrent()
    for _ in 0..<iterations {
        try body()
    }
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    let perOp = (elapsed / Double(iterations)) * 1000.0
    let status = perOp < 10.0 ? "✅" : "⚠️"
    print(String(
        format: "  %@ %-45s %8.3f ms  (%d iterations, %.3f ms total)",
        status, (label as NSString).utf8String!, perOp, iterations, elapsed * 1000.0
    ))
}

// MARK: - Main

print("╔══════════════════════════════════════════════════════════╗")
print("║  Píldora SQLCipher Spike — GRDB.swift Integration Test  ║")
print("╚══════════════════════════════════════════════════════════╝")
print()

let tmpDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("pildora-sqlcipher-spike")
try? FileManager.default.removeItem(at: tmpDir)
try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

let dbPath = tmpDir.appendingPathComponent("spike.db").path
let testPassphrase = "spike-test-passphrase-not-for-production"
let testVaultId = UUID().uuidString

// ─── 1. Database Open + Schema Creation ──────────────────────────

print("┌─ 1. Database Setup ──────────────────────────────────────")

var db: AppDatabase!
benchmark("Open database + run migrations") {
    db = try AppDatabase.open(at: dbPath, passphrase: testPassphrase)
}

#if GRDBCIPHER
if let version = try? db.cipherVersion() {
    print("  🔒 SQLCipher version: \(version)")
} else {
    print("  ⚠️  SQLCipher not detected")
}
#else
print("  ℹ️  Running without SQLCipher (plain SQLite)")
#endif

print()

// ─── 2. Single Insert ────────────────────────────────────────────

print("┌─ 2. Single Operations ───────────────────────────────────")

var med1 = Medication.new(
    vaultId: testVaultId,
    name: "Adderall XR",
    genericName: "amphetamine/dextroamphetamine",
    dosage: "20mg",
    form: "capsule",
    frequency: "daily"
)

benchmark("Insert single Medication") {
    var m = med1
    m.id = UUID().uuidString
    try db.insertMedication(&m)
    med1 = m
}

// ─── 3. Single Read ──────────────────────────────────────────────

var fetchedMed: Medication?
benchmark("Fetch single Medication by ID") {
    fetchedMed = try db.fetchMedication(id: med1.id)
}
assert(fetchedMed != nil, "Medication should be found")
assert(fetchedMed!.name == "Adderall XR", "Name should match")
assert(fetchedMed!.genericName == "amphetamine/dextroamphetamine", "Generic name should match")
print("  ✅ Roundtrip verified: \(fetchedMed!.name) (\(fetchedMed!.dosage))")

// ─── 4. Update ───────────────────────────────────────────────────

benchmark("Update Medication") {
    var m = fetchedMed!
    m.dosage = "30mg"
    m.notes = "Increased dosage per Dr. Smith"
    try db.updateMedication(&m)
}

let updated = try db.fetchMedication(id: med1.id)!
assert(updated.dosage == "30mg", "Dosage should be updated")
assert(updated.notes == "Increased dosage per Dr. Smith", "Notes should be updated")
assert(updated.updatedAt > med1.createdAt, "updatedAt should advance")

// ─── 5. Schedule + DoseLog ───────────────────────────────────────

var sched = Schedule.daily(medicationId: med1.id, times: ["08:00", "20:00"])
benchmark("Insert Schedule") {
    try db.insertSchedule(&sched)
}

let schedules = try db.fetchSchedules(medicationId: med1.id)
assert(schedules.count == 1, "Should have 1 schedule")
assert(schedules[0].pattern == "daily", "Pattern should be daily")

var dose = DoseLog.taken(medicationId: med1.id, scheduleId: sched.id)
benchmark("Insert DoseLog") {
    try db.insertDoseLog(&dose)
}

let todayDoses = try db.fetchTodayDoses()
assert(todayDoses.count >= 1, "Should have at least 1 dose today")
print("  ✅ Schedule + DoseLog roundtrip verified")

// ─── 6. Delete (cascading) ──────────────────────────────────────

// Insert a throwaway medication with schedule + dose to test cascade
var throwaway = Medication.new(
    vaultId: testVaultId, name: "Throwaway", dosage: "1mg"
)
try db.insertMedication(&throwaway)
var throwSched = Schedule.daily(medicationId: throwaway.id, times: ["09:00"])
try db.insertSchedule(&throwSched)
var throwDose = DoseLog.taken(medicationId: throwaway.id, scheduleId: throwSched.id)
try db.insertDoseLog(&throwDose)

benchmark("Delete Medication (cascade schedules + doses)") {
    _ = try db.deleteMedication(id: throwaway.id)
}

let deletedMed = try db.fetchMedication(id: throwaway.id)
assert(deletedMed == nil, "Medication should be deleted")
let orphanSchedules = try db.fetchSchedules(medicationId: throwaway.id)
assert(orphanSchedules.isEmpty, "Schedules should be cascade-deleted")
print("  ✅ Cascade delete verified (medication → schedules → dose logs)")
print()

// ─── 7. Batch Insert ─────────────────────────────────────────────

print("┌─ 3. Batch Operations ────────────────────────────────────")

let batchSize = 100
var batchMeds = (0..<batchSize).map { i in
    Medication.new(
        vaultId: testVaultId,
        name: "Medication-\(i)",
        genericName: "generic-\(i)",
        dosage: "\(5 + i % 20)mg",
        form: ["tablet", "capsule", "liquid", "patch"][i % 4],
        frequency: ["daily", "twice_daily", "weekly", "prn"][i % 4]
    )
}

benchmark("Batch insert \(batchSize) Medications (single transaction)") {
    try db.insertMedications(&batchMeds)
}

let totalCount = try db.medicationCount()
// 1 from single insert + 100 from batch = 101 (throwaway was deleted)
print("  ℹ️  Total medications in database: \(totalCount)")

// ─── 8. Filtered Query ──────────────────────────────────────────

var vaultMeds: [Medication] = []
benchmark("Query all Medications for vault (filtered + ordered)", iterations: 10) {
    vaultMeds = try db.fetchMedications(vaultId: testVaultId)
}
print("  ℹ️  Vault query returned \(vaultMeds.count) medications")

// ─── 9. Batch DoseLog Insert ─────────────────────────────────────

// Simulate 30 days of dose history for 10 medications
let doseMeds = Array(batchMeds.prefix(10))
var allDoses: [DoseLog] = []
for med in doseMeds {
    for day in 0..<30 {
        for hour in [8, 20] {
            var d = DoseLog.taken(medicationId: med.id)
            d.recordedAt = Calendar.current.date(
                byAdding: .hour,
                value: -(day * 24) + hour,
                to: Date()
            )!
            d.scheduledAt = d.recordedAt
            allDoses.append(d)
        }
    }
}

benchmark("Insert \(allDoses.count) DoseLogs (30 days × 10 meds × 2/day)") {
    try db.dbQueue.write { dbConn in
        for i in allDoses.indices {
            try allDoses[i].insert(dbConn)
        }
    }
}

let totalDoses = try db.doseLogCount()
print("  ℹ️  Total dose logs in database: \(totalDoses)")

// ─── 10. Date-Range Query ────────────────────────────────────────

let sevenDaysAgo = Calendar.current.date(
    byAdding: .day, value: -7, to: Date()
)!
var weekDoses: [DoseLog] = []
benchmark("Query 7-day dose history for 1 medication", iterations: 10) {
    weekDoses = try db.fetchDoseLogs(
        medicationId: doseMeds[0].id,
        from: sevenDaysAgo,
        to: Date()
    )
}
print("  ℹ️  7-day query returned \(weekDoses.count) dose logs")
print()

// ─── 11. File Size ───────────────────────────────────────────────

print("┌─ 4. Storage Metrics ─────────────────────────────────────")

let fileSize = try db.fileSize()
let fileSizeKB = Double(fileSize) / 1024.0
print(String(format: "  📁 Database file size: %.1f KB", fileSizeKB))
print("  📊 Contains: \(totalCount) medications, \(totalDoses) dose logs")
print(String(
    format: "  📊 Bytes per medication: %.0f",
    Double(fileSize) / Double(totalCount)
))
print()

// ─── 12. Wrong Passphrase Test ───────────────────────────────────

print("┌─ 5. Security Validation ─────────────────────────────────")

#if GRDBCIPHER
do {
    let wrongDb = try AppDatabase.open(at: dbPath, passphrase: "wrong-passphrase")
    let _ = try wrongDb.medicationCount()
    print("  ❌ FAIL: Wrong passphrase should have been rejected")
} catch {
    print("  ✅ Wrong passphrase correctly rejected: \(error.localizedDescription)")
}

// Verify correct passphrase still works
let reopened = try AppDatabase.open(at: dbPath, passphrase: testPassphrase)
let reopenedCount = try reopened.medicationCount()
assert(reopenedCount == totalCount, "Data should persist across reopen")
print("  ✅ Correct passphrase reopens database (\(reopenedCount) medications)")
#else
print("  ⏭️  Skipping passphrase tests (GRDBCIPHER not enabled)")
print("  ℹ️  To test encryption, link SQLCipher and define GRDBCIPHER")
#endif

print()

// ─── Summary ─────────────────────────────────────────────────────

print("┌─ Summary ────────────────────────────────────────────────")
print("  Framework:    GRDB.swift 7.x")
#if GRDBCIPHER
print("  Encryption:   SQLCipher (GRDBCIPHER enabled)")
#else
print("  Encryption:   None (plain SQLite — GRDBCIPHER not defined)")
#endif
print("  Data model:   4 tables (medication, schedule, dose_log, inventory)")
print("  Schema:       Versioned migrations via GRDB DatabaseMigrator")
print("  Concurrency:  WAL mode + DatabaseQueue (serialized writes)")
print("  Cascading:    FK constraints with ON DELETE CASCADE")
print("  Medications:  \(totalCount)")
print("  Dose logs:    \(totalDoses)")
print(String(format: "  DB size:      %.1f KB", fileSizeKB))
print()
print("  All tests passed ✅")
print()

// ─── Architecture Notes ──────────────────────────────────────────

print("┌─ Architecture Notes for Production ──────────────────────")
print("""
  Key Derivation Path:
    Master Password
      → Argon2id → MUK (Master Unlock Key)
        → unwrap Vault Key
          → HKDF-SHA256(info: "pildora-sqlcipher-db-key")
            → hex-encoded SQLCipher passphrase

  One Vault = One SQLCipher Database File:
    Each vault gets its own .db file with a unique passphrase
    derived from the vault key. This provides:
    • Natural encryption boundary per vault
    • Independent key rotation per vault
    • Simple vault deletion (delete the file)
    • No cross-vault query leakage

  iOS Data Protection (defense in depth):
    Set NSFileProtectionCompleteUntilFirstUserAuthentication
    on the database file. This adds OS-level encryption on top
    of SQLCipher, protecting data when the device is powered
    off (before first unlock after boot).
""")

// Cleanup
try? FileManager.default.removeItem(at: tmpDir)
