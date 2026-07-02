import XCTest
@testable import PildoraNotificationScheduler

final class ContentBuilderTests: XCTestCase {

    let builder = DoseNotificationContentBuilder()

    func testTitleIsMedicationName() {
        let dose = Fixture.dose(schedule: "s1", name: "Metformin", dosage: "500 mg", minutesFromNow: 10)
        let content = builder.content(for: dose)
        XCTAssertEqual(content.title, "Metformin")
    }

    func testBodyIncludesDosage() {
        let dose = Fixture.dose(schedule: "s1", name: "Metformin", dosage: "500 mg", minutesFromNow: 10)
        let content = builder.content(for: dose)
        XCTAssertEqual(content.body, "Time to take 500 mg")
    }

    func testBodyIncludesInstructions() {
        let dose = Fixture.dose(
            schedule: "s1", name: "Metformin", dosage: "500 mg",
            instructions: "Take with food", minutesFromNow: 10
        )
        let content = builder.content(for: dose)
        XCTAssertEqual(content.body, "Time to take 500 mg — Take with food")
    }

    func testBodyFallsBackToNameWhenNoDosage() {
        let dose = Fixture.dose(schedule: "s1", name: "Vitamin D", dosage: nil, minutesFromNow: 10)
        let content = builder.content(for: dose)
        XCTAssertEqual(content.body, "Time to take Vitamin D")
    }

    func testUsesDoseReminderCategoryAndThread() {
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)
        let content = builder.content(for: dose)
        XCTAssertEqual(content.categoryIdentifier, DoseNotificationCategories.doseReminder)
        // A shared thread identifier groups reminders together, including on the
        // Apple Watch where notifications mirror automatically.
        XCTAssertEqual(content.threadIdentifier, DoseNotificationCategories.doseThread)
    }

    func testPlannedNotificationUsesDoseIdentifierAndFireDate() {
        let dose = Fixture.dose(schedule: "s1", minutesFromNow: 10)
        let planned = builder.plannedNotification(for: dose)
        XCTAssertEqual(planned.identifier, dose.id)
        XCTAssertTrue(planned.identifier.hasPrefix(DoseNotification.identifierPrefix))
        XCTAssertEqual(planned.fireDate, dose.scheduledAt)
    }

    func testOverdueSummaryPluralization() {
        let one = builder.overdueSummaryContent(missedCount: 1)
        XCTAssertEqual(one.title, "Missed 1 dose")
        let many = builder.overdueSummaryContent(missedCount: 3)
        XCTAssertEqual(many.title, "Missed 3 doses")
        XCTAssertEqual(many.badge, 3)
        XCTAssertFalse(many.playsSound)
    }

    func testCategoryHasThreeActionsInOrder() {
        let category = DoseNotificationCategories.doseReminderCategory()
        XCTAssertEqual(
            category.actions.map(\.identifier),
            [DoseNotificationAction.takenIdentifier,
             DoseNotificationAction.snoozeIdentifier,
             DoseNotificationAction.skipIdentifier]
        )
    }
}
