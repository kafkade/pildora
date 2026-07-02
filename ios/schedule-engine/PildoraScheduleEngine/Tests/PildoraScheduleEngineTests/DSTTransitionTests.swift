import XCTest
@testable import PildoraScheduleEngine

final class DSTTransitionTests: XCTestCase {
    private let newYork = TestSupport.calendar(timeZone: "America/New_York")

    func testNoonDoseGapIsTwentyThreeHoursAcrossSpringForward() {
        // US spring-forward: 2026-03-08, clocks jump 02:00 -> 03:00.
        let start = TestSupport.date(2026, 3, 7, calendar: newYork)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("12:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 2,
            after: TestSupport.date(2026, 3, 6, 23, 59, calendar: newYork),
            calendar: newYork
        )

        // Both fire at local noon; the calendar day loses an hour, so the
        // absolute gap is 23h — proving wall-clock (not fixed-instant) timing.
        XCTAssertEqual(doses.count, 2)
        XCTAssertEqual(doses[0].wallClock(in: newYork).hour, 12)
        XCTAssertEqual(doses[1].wallClock(in: newYork).hour, 12)
        XCTAssertEqual(doses[1].scheduledAt.timeIntervalSince(doses[0].scheduledAt), 23 * 3600)
    }

    func testNoonDoseGapIsTwentyFiveHoursAcrossFallBack() {
        // US fall-back: 2026-11-01, clocks fall 02:00 -> 01:00.
        let start = TestSupport.date(2026, 10, 31, calendar: newYork)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("12:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 2,
            after: TestSupport.date(2026, 10, 30, 23, 59, calendar: newYork),
            calendar: newYork
        )

        XCTAssertEqual(doses.count, 2)
        XCTAssertEqual(doses[1].scheduledAt.timeIntervalSince(doses[0].scheduledAt), 25 * 3600)
    }

    func testSpringForwardNonexistentTimeAdvancesToNextValidInstant() {
        // 02:30 does not exist on 2026-03-08; policy: advance to next valid.
        let start = TestSupport.date(2026, 3, 8, calendar: newYork)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("02:30")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 1,
            after: TestSupport.date(2026, 3, 8, 0, 0, calendar: newYork),
            calendar: newYork
        )

        XCTAssertEqual(doses.count, 1)
        // Resolves to 03:30 EDT (the next valid wall time).
        XCTAssertEqual(doses.first?.wallClock(in: newYork).hour, 3)
        XCTAssertEqual(doses.first?.wallClock(in: newYork).minute, 30)
    }

    func testFallBackAmbiguousTimeUsesEarlierOccurrence() {
        // 01:30 occurs twice on 2026-11-01; policy: earlier (EDT) occurrence.
        let start = TestSupport.date(2026, 11, 1, calendar: newYork)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("01:30")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(
            count: 1,
            after: TestSupport.date(2026, 11, 1, 0, 0, calendar: newYork),
            calendar: newYork
        )

        XCTAssertEqual(doses.count, 1)
        // EDT offset is -4h; the later (EST) occurrence would be -5h.
        let offset = newYork.timeZone.secondsFromGMT(for: doses[0].scheduledAt)
        XCTAssertEqual(offset, -4 * 3600)
    }
}
