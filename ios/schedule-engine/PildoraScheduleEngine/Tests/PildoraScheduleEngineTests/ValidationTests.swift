import XCTest
@testable import PildoraScheduleEngine

final class ValidationTests: XCTestCase {
    private let cal = TestSupport.calendar()
    private var start: Date { TestSupport.date(2026, 1, 1, calendar: cal) }

    func testValidDailyRulePasses() {
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00", "20:00")),
            startDate: start
        )
        XCTAssertTrue(rule.validate().isEmpty)
        XCTAssertTrue(rule.isValid)
    }

    func testMissingDoseTimesIsRejected() {
        let rule = TestSupport.rule(pattern: .daily(anchors: []), startDate: start)
        XCTAssertEqual(rule.validate(), [.missingDoseTimes])
    }

    func testAsNeededIsAlwaysValid() {
        // PRN carries no anchors or cadence by construction, so it validates
        // cleanly and daily-with-times is the correct path for scheduled meds.
        let prn = TestSupport.rule(pattern: .asNeeded, startDate: start)
        XCTAssertTrue(prn.validate().isEmpty)
    }

    func testInvalidIntervalIsRejected() {
        let zero = TestSupport.rule(
            pattern: .everyNDays(interval: 0, anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        XCTAssertEqual(zero.validate(), [.invalidInterval(0)])

        let negative = TestSupport.rule(
            pattern: .everyNDays(interval: -3, anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        XCTAssertEqual(negative.validate(), [.invalidInterval(-3)])
    }

    func testEmptyWeekdaysIsRejected() {
        let rule = TestSupport.rule(
            pattern: .specificDays(weekdays: [], anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        XCTAssertEqual(rule.validate(), [.noWeekdaysSelected])
    }

    func testInvalidCycleIsRejected() {
        let rule = TestSupport.rule(
            pattern: .cycling(daysOn: 0, daysOff: 7, anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        XCTAssertEqual(rule.validate(), [.invalidCycle(daysOn: 0, daysOff: 7)])
    }

    func testEndBeforeStartIsRejected() {
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00")),
            startDate: start,
            endDate: TestSupport.date(2025, 12, 1, calendar: cal)
        )
        XCTAssertTrue(rule.validate().contains(.endBeforeStart))
    }

    func testDuplicateDoseTimesIsRejected() {
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00", "08:00")),
            startDate: start
        )
        XCTAssertEqual(rule.validate(), [.duplicateDoseTimes(TimeOfDay("08:00")!)])
    }

    func testDuplicateAcrossTimeAndWindowIsRejected() {
        // Morning window resolves to 08:00 by default; combining it with an
        // explicit 08:00 time overlaps.
        let rule = TestSupport.rule(
            pattern: .daily(anchors: [.time(TimeOfDay("08:00")!), .window(.morning)]),
            startDate: start
        )
        XCTAssertEqual(rule.validate(), [.duplicateDoseTimes(TimeOfDay("08:00")!)])
    }

    func testMultipleErrorsAreAllReported() {
        let rule = TestSupport.rule(
            pattern: .everyNDays(interval: 0, anchors: []),
            startDate: start,
            endDate: TestSupport.date(2025, 1, 1, calendar: cal)
        )
        let errors = Set(rule.validate())
        XCTAssertTrue(errors.contains(.invalidInterval(0)))
        XCTAssertTrue(errors.contains(.missingDoseTimes))
        XCTAssertTrue(errors.contains(.endBeforeStart))
    }
}
