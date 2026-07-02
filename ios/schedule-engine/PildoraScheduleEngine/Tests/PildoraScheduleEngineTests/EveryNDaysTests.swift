import XCTest
@testable import PildoraScheduleEngine

final class EveryNDaysTests: XCTestCase {
    func testEveryThreeDaysFromStart() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 4, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .everyNDays(interval: 3, anchors: TestSupport.anchors("10:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 4,
            after: TestSupport.date(2026, 3, 31, calendar: cal),
            calendar: cal
        )

        XCTAssertEqual(
            doses.map(\.scheduledAt),
            [
                TestSupport.date(2026, 4, 1, 10, 0, calendar: cal),
                TestSupport.date(2026, 4, 4, 10, 0, calendar: cal),
                TestSupport.date(2026, 4, 7, 10, 0, calendar: cal),
                TestSupport.date(2026, 4, 10, 10, 0, calendar: cal),
            ]
        )
    }

    func testEveryTwoDaysSkipsOffDays() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 4, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .everyNDays(interval: 2, anchors: TestSupport.anchors("09:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let interval = DateInterval(
            start: TestSupport.date(2026, 4, 1, calendar: cal),
            end: TestSupport.date(2026, 4, 6, 23, 59, calendar: cal)
        )
        let days = engine.occurrences(in: interval, calendar: cal)
            .map { cal.component(.day, from: $0.scheduledAt) }

        XCTAssertEqual(days, [1, 3, 5])
    }

    func testEveryNDaysQueriedFromMidStreamStaysOnCadence() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 4, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .everyNDays(interval: 3, anchors: TestSupport.anchors("10:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        // Querying after the 5th should still land on the 7th (start + 6 days),
        // not reset the cadence to the query date.
        let doses = engine.nextDoses(
            count: 1,
            after: TestSupport.date(2026, 4, 5, 12, 0, calendar: cal),
            calendar: cal
        )
        XCTAssertEqual(doses.first?.scheduledAt, TestSupport.date(2026, 4, 7, 10, 0, calendar: cal))
    }
}
