import XCTest
@testable import PildoraScheduleEngine

final class DailyAndMultiDailyTests: XCTestCase {
    func testSingleDailyDoseAcrossThreeDays() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 3, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let interval = DateInterval(
            start: TestSupport.date(2026, 3, 1, calendar: cal),
            end: TestSupport.date(2026, 3, 3, 23, 59, calendar: cal)
        )
        let doses = engine.occurrences(in: interval, calendar: cal)

        XCTAssertEqual(doses.count, 3)
        for dose in doses {
            XCTAssertEqual(dose.wallClock(in: cal).hour, 8)
            XCTAssertEqual(dose.window, .morning)
            XCTAssertEqual(dose.medicationId, "med-1")
            XCTAssertEqual(dose.scheduleId, "sched-1")
            XCTAssertEqual(dose.vaultId, "vault-1")
        }
        // Chronologically ordered.
        XCTAssertEqual(doses, doses.sorted())
    }

    func testMultiDailyThreeTimesPerDayOrdering() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 6, 10, calendar: cal)
        let rule = TestSupport.rule(
            // Deliberately out of order to prove the engine sorts within a day.
            pattern: .daily(anchors: TestSupport.anchors("20:00", "08:00", "14:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let interval = DateInterval(
            start: TestSupport.date(2026, 6, 10, calendar: cal),
            end: TestSupport.date(2026, 6, 10, 23, 59, calendar: cal)
        )
        let doses = engine.occurrences(in: interval, calendar: cal)

        XCTAssertEqual(doses.map { $0.wallClock(in: cal).hour }, [8, 14, 20])
        XCTAssertEqual(doses.map(\.window), [.morning, .afternoon, .evening])
    }

    func testDosesBeforeStartDateAreExcluded() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 3, 15, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("09:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let interval = DateInterval(
            start: TestSupport.date(2026, 3, 10, calendar: cal),
            end: TestSupport.date(2026, 3, 20, 23, 59, calendar: cal)
        )
        let doses = engine.occurrences(in: interval, calendar: cal)

        XCTAssertEqual(doses.count, 6) // 15th through 20th inclusive
        XCTAssertEqual(
            doses.first?.scheduledAt,
            TestSupport.date(2026, 3, 15, 9, 0, calendar: cal)
        )
    }

    func testEndDateIsInclusiveOfThatDaysDoses() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 3, 1, calendar: cal)
        let end = TestSupport.date(2026, 3, 3, 0, 0, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("22:00")),
            startDate: start,
            endDate: end
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 10,
            after: TestSupport.date(2026, 2, 28, calendar: cal),
            calendar: cal
        )

        // 1st, 2nd, 3rd — the 22:00 dose on the end day is still included even
        // though it is after the endDate's midnight time-of-day.
        XCTAssertEqual(doses.count, 3)
        XCTAssertEqual(
            doses.last?.scheduledAt,
            TestSupport.date(2026, 3, 3, 22, 0, calendar: cal)
        )
    }
}
