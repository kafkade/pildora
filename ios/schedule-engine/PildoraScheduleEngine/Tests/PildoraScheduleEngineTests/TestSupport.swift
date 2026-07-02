import Foundation
import XCTest
@testable import PildoraScheduleEngine

// Shared helpers for building deterministic dates, calendars, and rules.
// Every test pins an explicit `TimeZone` so results never depend on the
// machine running them.

enum TestSupport {
    /// A Gregorian calendar fixed to a named timezone (UTC by default) so
    /// wall-clock math is reproducible.
    static func calendar(timeZone identifier: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        // Force a stable week definition (Sunday = 1) across hosts.
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Builds a `Date` from components in the given calendar.
    static func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)!
    }

    /// Builds a rule with sensible identifier defaults.
    static func rule(
        pattern: SchedulePattern,
        startDate: Date,
        endDate: Date? = nil,
        windows: TimeWindowConfiguration = .default
    ) -> ScheduleRule {
        ScheduleRule(
            scheduleId: "sched-1",
            medicationId: "med-1",
            vaultId: "vault-1",
            pattern: pattern,
            startDate: startDate,
            endDate: endDate,
            windowConfiguration: windows
        )
    }

    /// Convenience to build `.time` anchors from `"HH:mm"` strings, failing the
    /// test on a malformed literal.
    static func anchors(_ times: String..., file: StaticString = #filePath, line: UInt = #line) -> [DoseAnchor] {
        times.map { string in
            guard let anchor = DoseAnchor.time(string) else {
                XCTFail("Invalid time literal \(string)", file: file, line: line)
                return .time(TimeOfDay(hour: 0, minute: 0)!)
            }
            return anchor
        }
    }
}

extension DoseOccurrence {
    /// The occurrence's hour/minute in a calendar, for readable assertions.
    func wallClock(in calendar: Calendar) -> (hour: Int, minute: Int) {
        let components = calendar.dateComponents([.hour, .minute], from: scheduledAt)
        return (components.hour!, components.minute!)
    }
}
