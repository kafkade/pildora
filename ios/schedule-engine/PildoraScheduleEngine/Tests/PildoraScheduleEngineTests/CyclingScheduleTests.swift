import XCTest
@testable import PildoraScheduleEngine

final class CyclingScheduleTests: XCTestCase {
    func testTwentyOneOnSevenOffContraceptivePattern() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 1, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .cycling(daysOn: 21, daysOff: 7, anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        // First full 28-day cycle: active Jan 1–21, off Jan 22–28.
        let interval = DateInterval(
            start: TestSupport.date(2026, 1, 1, calendar: cal),
            end: TestSupport.date(2026, 1, 28, 23, 59, calendar: cal)
        )
        let activeDays = engine.occurrences(in: interval, calendar: cal)
            .map { cal.component(.day, from: $0.scheduledAt) }

        XCTAssertEqual(activeDays, Array(1...21))
    }

    func testTwentyOneOnSevenOffResumesNextCycle() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 1, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .cycling(daysOn: 21, daysOff: 7, anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        // The dose after the last active day (Jan 21) is the first day of the
        // next cycle: Jan 29.
        let doses = engine.nextDoses(
            count: 1,
            after: TestSupport.date(2026, 1, 21, 12, 0, calendar: cal),
            calendar: cal
        )
        XCTAssertEqual(doses.first?.scheduledAt, TestSupport.date(2026, 1, 29, 8, 0, calendar: cal))
    }

    func testFiveOnTwoOffBoundaries() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 1, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .cycling(daysOn: 5, daysOff: 2, anchors: TestSupport.anchors("09:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let interval = DateInterval(
            start: TestSupport.date(2026, 1, 1, calendar: cal),
            end: TestSupport.date(2026, 1, 14, 23, 59, calendar: cal)
        )
        let activeDays = engine.occurrences(in: interval, calendar: cal)
            .map { cal.component(.day, from: $0.scheduledAt) }

        // On Jan 1–5, off 6–7, on 8–12, off 13–14.
        XCTAssertEqual(activeDays, [1, 2, 3, 4, 5, 8, 9, 10, 11, 12])
    }
}
