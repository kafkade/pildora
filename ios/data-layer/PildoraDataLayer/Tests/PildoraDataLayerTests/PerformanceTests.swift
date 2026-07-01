import XCTest
@testable import PildoraDataLayer

/// Performance guardrail for the acceptance criterion: a single-item
/// store → retrieve roundtrip must stay under 10ms.
///
/// Timings are measured on plain SQLite under `swift test`; SQLCipher adds a
/// modest 5–15% per-page overhead, so a comfortable margin here keeps the
/// encrypted app-target path within budget too. The threshold is intentionally
/// loose relative to typical sub-millisecond results to avoid CI flakiness on
/// shared runners.
final class PerformanceTests: XCTestCase {
    private var url: URL!
    private var db: AppDatabase!

    override func setUpWithError() throws {
        (db, url) = try TestFixtures.makeDatabase()
        try TestFixtures.seedVault(db, id: "vault-1")
    }

    override func tearDownWithError() throws {
        db = nil
        TestFixtures.remove(at: url)
    }

    func testSingleItemRoundtripUnder10ms() throws {
        let iterations = 200
        // Warm up caches and the prepared-statement path.
        try db.insertMedication(Medication(id: "warmup", vaultId: "vault-1", name: "W", dosage: "1"))
        _ = try db.fetchMedication(id: "warmup")

        let start = DispatchTime.now()
        for i in 0..<iterations {
            let med = Medication(id: "perf-\(i)", vaultId: "vault-1", name: "Med \(i)", dosage: "1 mg")
            try db.insertMedication(med)
            _ = try db.fetchMedication(id: med.id)
        }
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let averageMs = Double(elapsedNs) / 1_000_000 / Double(iterations)

        XCTAssertLessThan(
            averageMs, 10.0,
            "insert+fetch roundtrip averaged \(averageMs)ms/item (target < 10ms)"
        )
    }
}
