import XCTest
@testable import PildoraTodayView

@MainActor
final class TodayStoreTests: XCTestCase {
    func testSectionsAreGroupedByWindowAndSortedChronologically() {
        let calendar = makeUTCCalendar()
        let now = makeDate(hour: 10, minute: 0, calendar: calendar)
        let doses = [
            makeDose(id: "morning-1", hour: 8, minute: 0, name: "A", calendar: calendar),
            makeDose(id: "afternoon-1", hour: 13, minute: 0, name: "B", calendar: calendar),
            makeDose(id: "evening-1", hour: 19, minute: 0, name: "C", calendar: calendar),
            makeDose(id: "bedtime-1", hour: 22, minute: 0, name: "D", calendar: calendar),
        ]

        let store = TodayStore(
            scheduledDoses: doses,
            prnMedications: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(store.sections.map(\.window), [.morning, .afternoon, .evening, .bedtime])
        XCTAssertEqual(store.sections.flatMap(\.doses).map(\.id), ["morning-1", "afternoon-1", "evening-1", "bedtime-1"])
    }

    func testStateClassificationForUpcomingDueAndOverdue() {
        let calendar = makeUTCCalendar()
        let now = makeDate(hour: 14, minute: 0, calendar: calendar)
        let doses = [
            makeDose(id: "overdue", hour: 12, minute: 0, name: "Overdue Med", calendar: calendar),
            makeDose(id: "due-past", hour: 13, minute: 45, name: "Due Past Med", calendar: calendar),
            makeDose(id: "due-future", hour: 14, minute: 10, name: "Due Future Med", calendar: calendar),
            makeDose(id: "upcoming", hour: 16, minute: 0, name: "Upcoming Med", calendar: calendar),
        ]

        let store = TodayStore(
            scheduledDoses: doses,
            prnMedications: [],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(store.doseItems.first(where: { $0.id == "overdue" })?.state, .overdue)
        XCTAssertEqual(store.doseItems.first(where: { $0.id == "due-past" })?.state, .dueNow)
        XCTAssertEqual(store.doseItems.first(where: { $0.id == "due-future" })?.state, .dueNow)
        XCTAssertEqual(store.doseItems.first(where: { $0.id == "upcoming" })?.state, .upcoming)
    }

    func testMarkTakenPersistsLogAndUpdatesState() {
        let calendar = makeUTCCalendar()
        let now = makeDate(hour: 9, minute: 0, calendar: calendar)
        let dose = makeDose(id: "dose-1", hour: 9, minute: 5, name: "Metformin", calendar: calendar)

        let store = TodayStore(
            scheduledDoses: [dose],
            prnMedications: [],
            now: now,
            calendar: calendar
        )
        store.markTaken(doseID: "dose-1", at: now)

        XCTAssertEqual(store.doseLogs.count, 1)
        XCTAssertEqual(store.doseLogs.first?.status, .taken)
        XCTAssertEqual(store.doseItems.first?.state, .taken)
    }

    func testSnoozeThenSkipFlowPersistsExpectedState() {
        let calendar = makeUTCCalendar()
        let now = makeDate(hour: 10, minute: 0, calendar: calendar)
        let dose = makeDose(id: "dose-1", hour: 10, minute: 5, name: "Gabapentin", calendar: calendar)

        let store = TodayStore(
            scheduledDoses: [dose],
            prnMedications: [],
            now: now,
            calendar: calendar
        )

        store.snoozeDose(doseID: "dose-1", minutes: 20, at: now)
        XCTAssertEqual(store.doseItems.first?.state, .snoozed)

        store.advanceClock(to: makeDate(hour: 10, minute: 30, calendar: calendar))
        XCTAssertEqual(store.doseItems.first?.state, .dueNow)

        store.skipDose(doseID: "dose-1", reason: "Not at home", at: makeDate(hour: 10, minute: 31, calendar: calendar))
        XCTAssertEqual(store.doseItems.first?.state, .skipped)
        XCTAssertEqual(store.doseLogs.first?.note, "Not at home")
    }

    func testPRNQuickLogCreatesPRNEntry() {
        let calendar = makeUTCCalendar()
        let now = makeDate(hour: 11, minute: 0, calendar: calendar)
        let prn = PRNMedication(
            id: "prn-ibuprofen",
            vaultId: "vault-1",
            medicationName: "Ibuprofen",
            dosage: "200 mg"
        )

        let store = TodayStore(
            scheduledDoses: [],
            prnMedications: [prn],
            now: now,
            calendar: calendar
        )

        store.logPRN(medicationID: "prn-ibuprofen", at: now)

        XCTAssertEqual(store.prnHistoryToday.count, 1)
        XCTAssertTrue(store.prnHistoryToday[0].isPRN)
        XCTAssertEqual(store.prnHistoryToday[0].medicationName, "Ibuprofen")
        XCTAssertEqual(store.prnHistoryToday[0].status, .taken)
    }

    private func makeDose(
        id: String,
        hour: Int,
        minute: Int,
        name: String,
        calendar: Calendar
    ) -> ScheduledDose {
        ScheduledDose(
            id: id,
            vaultId: "vault-1",
            medicationID: "med-\(id)",
            medicationName: name,
            dosage: "1 tablet",
            scheduledAt: makeDate(hour: hour, minute: minute, calendar: calendar)
        )
    }

    private func makeDate(hour: Int, minute: Int, calendar: Calendar) -> Date {
        let base = DateComponents(calendar: calendar, year: 2026, month: 6, day: 1)
        let day = calendar.date(from: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
