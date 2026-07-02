import XCTest
@testable import PildoraScheduleEngine

final class TimezoneTravelTests: XCTestCase {
    func testSameRuleFiresAtLocalWallTimeInEachTimezone() {
        let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 arbitrary
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("08:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let tokyo = TestSupport.calendar(timeZone: "Asia/Tokyo")
        let london = TestSupport.calendar(timeZone: "Europe/London")

        let after = TestSupport.date(2026, 6, 10, 0, 0, calendar: tokyo)
        let tokyoDose = engine.nextDoses(count: 1, after: after, calendar: tokyo).first
        let londonDose = engine.nextDoses(count: 1, after: after, calendar: london).first

        // Both read as local 08:00 in their respective timezones...
        XCTAssertEqual(tokyoDose?.wallClock(in: tokyo).hour, 8)
        XCTAssertEqual(londonDose?.wallClock(in: london).hour, 8)

        // ...but they are different absolute instants (Tokyo is ahead of London),
        // demonstrating the wall-clock recomputation on travel.
        XCTAssertNotEqual(tokyoDose?.scheduledAt, londonDose?.scheduledAt)
    }

    func testTravellingMidStreamShiftsSubsequentDosesToNewLocalTime() {
        let start = TestSupport.date(2026, 6, 1, calendar: TestSupport.calendar())
        let rule = TestSupport.rule(
            pattern: .daily(anchors: TestSupport.anchors("09:00")),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        // Same query instant, evaluated as if the user is in Los Angeles vs.
        // New York — the next 09:00 dose lands at a different absolute instant.
        let after = Date(timeIntervalSince1970: 1_781_000_000)
        let la = TestSupport.calendar(timeZone: "America/Los_Angeles")
        let ny = TestSupport.calendar(timeZone: "America/New_York")

        let laDose = engine.nextDoses(count: 1, after: after, calendar: la).first
        let nyDose = engine.nextDoses(count: 1, after: after, calendar: ny).first

        XCTAssertEqual(laDose?.wallClock(in: la).hour, 9)
        XCTAssertEqual(nyDose?.wallClock(in: ny).hour, 9)
        XCTAssertNotEqual(laDose?.scheduledAt, nyDose?.scheduledAt)
    }
}
