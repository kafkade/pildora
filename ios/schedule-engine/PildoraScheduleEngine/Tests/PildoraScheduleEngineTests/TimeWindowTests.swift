import XCTest
@testable import PildoraScheduleEngine

final class TimeWindowTests: XCTestCase {
    func testWindowAnchorsResolveViaDefaultConfiguration() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 5, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: [.window(.morning), .window(.bedtime)]),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let interval = DateInterval(
            start: TestSupport.date(2026, 5, 1, calendar: cal),
            end: TestSupport.date(2026, 5, 1, 23, 59, calendar: cal)
        )
        let doses = engine.occurrences(in: interval, calendar: cal)

        XCTAssertEqual(doses.map { $0.wallClock(in: cal).hour }, [8, 22]) // default morning/bedtime
        XCTAssertEqual(doses.map(\.window), [.morning, .bedtime])
    }

    func testUserConfiguredWindowTimesAreHonored() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 5, 1, calendar: cal)
        let customWindows = TimeWindowConfiguration(
            morning: TimeOfDay("07:30")!,
            afternoon: TimeOfDay("12:30")!,
            evening: TimeOfDay("17:30")!,
            bedtime: TimeOfDay("21:15")!
        )
        let rule = TestSupport.rule(
            pattern: .daily(anchors: [.window(.morning), .window(.evening)]),
            startDate: start,
            windows: customWindows
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(count: 2, after: start, calendar: cal)
        XCTAssertEqual(
            doses.map { $0.wallClock(in: cal) }.map { "\($0.hour):\($0.minute)" },
            ["7:30", "17:30"]
        )
    }

    func testMixedTimeAndWindowAnchors() {
        let cal = TestSupport.calendar()
        let start = TestSupport.date(2026, 5, 1, calendar: cal)
        let rule = TestSupport.rule(
            pattern: .daily(anchors: [.time(TimeOfDay("06:45")!), .window(.afternoon)]),
            startDate: start
        )
        let engine = ScheduleEngine(rule: rule)

        let doses = engine.nextDoses(count: 2, after: start, calendar: cal)
        XCTAssertEqual(doses.map(\.window), [.morning, .afternoon])
        XCTAssertEqual(doses.first?.time, TimeOfDay("06:45"))
        XCTAssertEqual(doses.last?.time, TimeOfDay("13:00")) // default afternoon
    }
}
