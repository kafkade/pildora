import XCTest
@testable import PildoraNotificationScheduler

/// Stand-in matching the schedule engine's `DoseOccurrence` shape. In the app,
/// the real `DoseOccurrence` conforms to `DoseOccurrenceLike` directly.
private struct StubOccurrence: DoseOccurrenceLike {
    var scheduleId: String
    var medicationId: String
    var vaultId: String
    var scheduledAt: Date
}

final class AdapterTests: XCTestCase {

    func testBuildsDoseFromOccurrence() {
        let occurrence = StubOccurrence(
            scheduleId: "sched-1",
            medicationId: "med-1",
            vaultId: "vault-9",
            scheduledAt: Fixture.now.addingTimeInterval(3600)
        )

        let dose = DoseNotification(
            occurrence: occurrence,
            medicationName: "Lisinopril",
            dosage: "10 mg",
            instructions: "Morning",
            priority: .high
        )

        XCTAssertEqual(dose.scheduleId, "sched-1")
        XCTAssertEqual(dose.medicationId, "med-1")
        XCTAssertEqual(dose.vaultId, "vault-9")
        XCTAssertEqual(dose.scheduledAt, occurrence.scheduledAt)
        XCTAssertEqual(dose.medicationName, "Lisinopril")
        XCTAssertEqual(dose.dosage, "10 mg")
        XCTAssertEqual(dose.instructions, "Morning")
        XCTAssertEqual(dose.priority, .high)
    }

    func testBatchMappingAppliesSharedMetadata() {
        let occurrences: [DoseOccurrenceLike] = (0..<3).map {
            StubOccurrence(
                scheduleId: "s\($0)",
                medicationId: "med-1",
                vaultId: "vault-1",
                scheduledAt: Fixture.now.addingTimeInterval(Double($0 + 1) * 3600)
            )
        }

        let doses = DoseNotification.from(
            occurrences: occurrences,
            medicationName: "Fish Oil",
            dosage: "1 capsule",
            priority: .low
        )

        XCTAssertEqual(doses.count, 3)
        XCTAssertTrue(doses.allSatisfy { $0.medicationName == "Fish Oil" && $0.priority == .low })
    }

    func testStableIdentifierAcrossRebuilds() {
        let occurrence = StubOccurrence(
            scheduleId: "sched-1",
            medicationId: "med-1",
            vaultId: "vault-1",
            scheduledAt: Fixture.now.addingTimeInterval(3600)
        )
        let a = DoseNotification(occurrence: occurrence, medicationName: "A")
        let b = DoseNotification(occurrence: occurrence, medicationName: "A")
        XCTAssertEqual(a.id, b.id, "Same schedule + instant must map to the same notification id")
    }
}
