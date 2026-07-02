import XCTest
@testable import PildoraScheduleEngine

final class PRNTests: XCTestCase {
    func testAsNeededProducesNoScheduledDoses() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 2, 1, calendar: cal)
        let rule = TestSupport.rule(pattern: .asNeeded, startDate: start)
        let engine = ScheduleEngine(rule: rule)

        XCTAssertTrue(engine.nextDoses(count: 10, after: start, calendar: cal).isEmpty)

        let interval = DateInterval(
            start: TestSupport.date(2026, 2, 1, calendar: cal),
            end: TestSupport.date(2026, 12, 31, calendar: cal)
        )
        XCTAssertTrue(engine.occurrences(in: interval, calendar: cal).isEmpty)
    }

    func testAsNeededPatternIsNotScheduled() {
        XCTAssertFalse(SchedulePattern.asNeeded.isScheduled)
        XCTAssertTrue(SchedulePattern.asNeeded.anchors.isEmpty)
    }
}
