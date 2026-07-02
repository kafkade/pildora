import XCTest
@testable import PildoraMedicationList

@MainActor
final class InventoryThresholdTests: XCTestCase {

    private func makeStore(notifier: SimulatedRefillNotifier = .init()) -> MedicationStore {
        MedicationStore(
            medications: SampleData.medications,
            inventory: SampleData.inventory(),
            references: SampleData.drugReferences(),
            notifier: notifier
        )
    }

    func testIsLowAndCriticalDerivation() {
        var rec = InventoryRecord(medicationId: "m", vaultId: "v", currentCount: 7, refillThreshold: 7)
        XCTAssertTrue(rec.isLow)
        rec.currentCount = 8
        XCTAssertFalse(rec.isLow)
        // Critical: <= max(3, threshold/2).
        rec = InventoryRecord(medicationId: "m", vaultId: "v", currentCount: 3, refillThreshold: 7)
        XCTAssertTrue(rec.isCritical)
        rec.currentCount = 4
        XCTAssertFalse(rec.isCritical)
    }

    func testLowStockMedicationsReflectsThreshold() {
        let store = makeStore()
        // med-4 (Magnesium) seeded at 3 with threshold 7 -> low.
        XCTAssertTrue(store.lowStockMedications.contains { $0.id == "med-4" })
        // med-3 (Vitamin D3) seeded at 90 with threshold 14 -> not low.
        XCTAssertFalse(store.lowStockMedications.contains { $0.id == "med-3" })
    }

    func testSetInventoryCountClampsAtZero() {
        let store = makeStore()
        store.setInventoryCount(-5, for: "med-1")
        XCTAssertEqual(store.inventory(for: "med-1")?.currentCount, 0)
    }

    func testAdjustInventoryDelta() {
        let store = makeStore()
        let before = store.inventory(for: "med-2")?.currentCount ?? 0
        store.adjustInventory(by: -1, for: "med-2")
        XCTAssertEqual(store.inventory(for: "med-2")?.currentCount, before - 1)
    }

    func testCrossingThresholdTogglesLowStock() {
        let store = makeStore()
        // med-1 starts at 22 (threshold 7) -> not low.
        XCTAssertFalse(store.lowStockMedications.contains { $0.id == "med-1" })
        store.setInventoryCount(5, for: "med-1")
        XCTAssertTrue(store.lowStockMedications.contains { $0.id == "med-1" })
    }
}
