import XCTest
@testable import PildoraScheduleEngine

final class NextDosesTests: XCTestCase {
    func testReturnsRequestedCountInChronologicalOrder() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 3, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00", "20:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 5,
            after: TestSupport.date(2026, 3, 1, 9, 0, calendar: cal),
            calendar: cal
        )

        XCTAssertEqual(doses.count, 5)
        XCTAssertEqual(doses, doses.sorted())
        // First returned dose is the 20:00 on Mar 1 (08:00 already passed).
        XCTAssertEqual(doses.first?.scheduledAt, TestSupport.date(2026, 3, 1, 20, 0, calendar: cal))
        XCTAssertEqual(doses.last?.scheduledAt, TestSupport.date(2026, 3, 3, 20, 0, calendar: cal))
    }

    func testStrictlyExcludesDoseExactlyAtAfterInstant() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 3, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 1,
            after: TestSupport.date(2026, 3, 1, 8, 0, calendar: cal),
            calendar: cal
        )
        // The 08:00 dose on Mar 1 equals `after`, so the next is Mar 2 08:00.
        XCTAssertEqual(doses.first?.scheduledAt, TestSupport.date(2026, 3, 2, 8, 0, calendar: cal))
    }

    func testTruncatesAtEndDate() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 3, 1, calendar: cal)
        let end = TestSupport.date(2026, 3, 2, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00")),
            startDate: start,
            endDate: end
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(count: 10, after: start, calendar: cal)
        // Mar 1 08:00 (after midnight start) and Mar 2 08:00; the schedule ends
        // Mar 2 so nothing beyond it is returned.
        XCTAssertEqual(doses.count, 2)
        XCTAssertEqual(doses.first?.scheduledAt, TestSupport.date(2026, 3, 1, 8, 0, calendar: cal))
        XCTAssertEqual(doses.last?.scheduledAt, TestSupport.date(2026, 3, 2, 8, 0, calendar: cal))
    }

    func testZeroCountReturnsEmpty() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 3, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)
        XCTAssertTrue(engine.nextDoses(count: 0, after: start, calendar: cal).isEmpty)
    }

    func testSparseScheduleStopsAtLookaheadBound() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 1, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .everyNDays(interval: 100, anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        // With a 10-day lookahead, only the start-day dose is reachable.
        let doses = engine.nextDoses(
            count: 5,
            after: TestSupport.date(2025, 12, 31, calendar: cal),
            calendar: cal,
            maxLookaheadDays: 10
        )
        XCTAssertEqual(doses.count, 1)
    }
}
