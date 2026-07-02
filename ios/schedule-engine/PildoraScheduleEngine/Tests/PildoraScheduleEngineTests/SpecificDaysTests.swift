import XCTest
@testable import PildoraScheduleEngine

final class SpecificDaysTests: XCTestCase {
    func testFiresOnlyOnSelectedWeekdays() {
        let cal = TestSupport.calendar()
        // 2026-06-01 is a Monday.
        let start = TestSupport.date(2026, 6, 1, calendar: cal)
        XCTAssertEqual(cal.component(.weekday, from: start), Weekday.monday.calendarValue)

        let rule = TestSupport.rule(
            pattern: .specificDays(
                weekdays: [.monday, .wednesday, .friday],
                anchors: TestSupport.anchors("08:00")
            ),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let interval = DateInterval(
            start: TestSupport.date(2026, 6, 1, calendar: cal),
            end: TestSupport.date(2026, 6, 7, 23, 59, calendar: cal) // Mon–Sun
        )
        let doses = engine.occurrences(in: interval, calendar: cal)

        // Mon 1, Wed 3, Fri 5.
        XCTAssertEqual(doses.map { cal.component(.day, from: $0.scheduledAt) }, [1, 3, 5])
        for dose in doses {
            let weekday = Weekday(calendarValue: cal.component(.weekday, from: dose.scheduledAt))
            XCTAssertTrue([.monday, .wednesday, .friday].contains(weekday))
        }
    }

    func testWeekendOnlySchedule() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 6, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .specificDays(
                weekdays: [.saturday, .sunday],
                anchors: TestSupport.anchors("11:00")
            ),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(count: 2, after: start, calendar: cal)
        // First weekend after Mon Jun 1: Sat Jun 6, Sun Jun 7.
        XCTAssertEqual(
            doses.map { cal.component(.day, from: $0.scheduledAt) },
            [6, 7]
        )
    }
}
