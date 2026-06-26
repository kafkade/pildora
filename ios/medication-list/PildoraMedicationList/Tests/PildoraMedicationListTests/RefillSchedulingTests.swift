import XCTest
@testable import PildoraMedicationList

@MainActor
final class RefillSchedulingTests: XCTestCase {

    func testReminderScheduledWhenStockDropsLow() {
        let notifier = SimulatedRefillNotifier()
        let store = MedicationStore(
            medications: SampleData.medications,
            inventory: SampleData.inventory(),
            references: SampleData.drugReferences(),
            notifier: notifier
        )
        store.setInventoryCount(2, for: "med-1") // threshold 7 -> low
        XCTAssertNotNil(notifier.pending["med-1"])
        XCTAssertEqual(notifier.pending["med-1"]?.remainingCount, 2)
    }

    func testReminderCancelledWhenRestocked() {
        let notifier = SimulatedRefillNotifier()
        let store = MedicationStore(
            medications: SampleData.medications,
            inventory: SampleData.inventory(),
            references: SampleData.drugReferences(),
            notifier: notifier
        )
        store.setInventoryCount(2, for: "med-1")
        XCTAssertNotNil(notifier.pending["med-1"])
        store.recordRefill(newCount: 60, for: "med-1")
        XCTAssertNil(notifier.pending["med-1"])
    }

    func testNoReminderWhenAppWideRemindersDisabled() {
        let notifier = SimulatedRefillNotifier()
        let store = MedicationStore(
            medications: SampleData.medications,
            inventory: SampleData.inventory(),
            references: SampleData.drugReferences(),
            settings: AppSettings(refillRemindersEnabled: false),
            notifier: notifier
        )
        store.setInventoryCount(1, for: "med-1")
        XCTAssertNil(notifier.pending["med-1"])
    }

    func testPerMedicationReminderToggleRespected() {
        let notifier = SimulatedRefillNotifier()
        let store = MedicationStore(
            medications: SampleData.medications,
            inventory: SampleData.inventory(),
            references: SampleData.drugReferences(),
            notifier: notifier
        )
        store.setRefillReminderEnabled(false, for: "med-4") // med-4 is low
        XCTAssertNil(notifier.pending["med-4"])
    }

    func testReminderBodyPluralization() {
        let one = RefillReminder(medicationID: "x", medicationName: "Med", remainingCount: 1, unitNoun: "tablet")
        XCTAssertTrue(one.body.contains("1 tablet "))
        let many = RefillReminder(medicationID: "x", medicationName: "Med", remainingCount: 3, unitNoun: "tablet")
        XCTAssertTrue(many.body.contains("3 tablets"))
    }
}
