import XCTest
@testable import PildoraScheduleEngine

final class TimeOfDayTests: XCTestCase {
    func testParsesValidStrings() {
        XCTAssertEqual(TimeOfDay("08:00"), TimeOfDay(hour: 8, minute: 0))
        XCTAssertEqual(TimeOfDay("23:59"), TimeOfDay(hour: 23, minute: 59))
        XCTAssertEqual(TimeOfDay("00:00"), TimeOfDay(hour: 0, minute: 0))
    }

    func testRejectsMalformedStrings() {
        XCTAssertNil(TimeOfDay("8:00"))     // not zero-padded
        XCTAssertNil(TimeOfDay("08:0"))     // not zero-padded
        XCTAssertNil(TimeOfDay("24:00"))    // hour out of range
        XCTAssertNil(TimeOfDay("08:60"))    // minute out of range
        XCTAssertNil(TimeOfDay("0800"))     // no separator
        XCTAssertNil(TimeOfDay("08:00:00")) // too many parts
        XCTAssertNil(TimeOfDay(""))
    }

    func testRejectsOutOfRangeComponents() {
        XCTAssertNil(TimeOfDay(hour: -1, minute: 0))
        XCTAssertNil(TimeOfDay(hour: 24, minute: 0))
        XCTAssertNil(TimeOfDay(hour: 0, minute: -1))
        XCTAssertNil(TimeOfDay(hour: 0, minute: 60))
    }

    func testFormattingIsZeroPadded() {
        XCTAssertEqual(TimeOfDay(hour: 8, minute: 5)?.formatted, "08:05")
        XCTAssertEqual(TimeOfDay(hour: 0, minute: 0)?.formatted, "00:00")
    }

    func testOrdering() {
        XCTAssertLessThan(TimeOfDay("08:00")!, TimeOfDay("08:01")!)
        XCTAssertLessThan(TimeOfDay("08:00")!, TimeOfDay("20:00")!)
        XCTAssertEqual(TimeOfDay("13:00")!.minutesSinceMidnight, 780)
    }

    func testWeekdayCalendarRoundTrip() {
        for weekday in Weekday.allCases {
            XCTAssertEqual(Weekday(calendarValue: weekday.calendarValue), weekday)
        }
        XCTAssertNil(Weekday(calendarValue: 0))
        XCTAssertNil(Weekday(calendarValue: 8))
    }

    func testWindowContainingTime() {
        XCTAssertEqual(DoseTimeWindow.containing(TimeOfDay("08:00")!), .morning)
        XCTAssertEqual(DoseTimeWindow.containing(TimeOfDay("13:00")!), .afternoon)
        XCTAssertEqual(DoseTimeWindow.containing(TimeOfDay("19:00")!), .evening)
        XCTAssertEqual(DoseTimeWindow.containing(TimeOfDay("23:00")!), .bedtime)
        XCTAssertEqual(DoseTimeWindow.containing(TimeOfDay("02:00")!), .bedtime)
    }

    func testWindowConfigurationResolution() {
        let config = TimeWindowConfiguration.default
        XCTAssertEqual(config.time(for: .morning), TimeOfDay("08:00"))
        XCTAssertEqual(config.time(for: .bedtime), TimeOfDay("22:00"))

        let anchor = DoseAnchor.window(.evening)
        XCTAssertEqual(anchor.resolvedTime(using: config), TimeOfDay("18:00"))
        XCTAssertEqual(anchor.resolvedWindow(using: config), .evening)
    }
}
