import Foundation

// MARK: - ScheduleValidationError

/// A reason a `ScheduleRule` is invalid or impossible. Returned by
/// `ScheduleRule.validate()`; a schedule is safe to hand to the engine only
/// when validation returns an empty array.
public enum ScheduleValidationError: Error, Hashable, Sendable {
    /// A scheduled pattern (anything other than PRN) has no dose anchors, so it
    /// would never fire.
    case missingDoseTimes

    /// `everyNDays` interval is less than 1 day.
    case invalidInterval(Int)

    /// `specificDays` was given an empty weekday set, so it would never fire.
    case noWeekdaysSelected

    /// A cycling schedule has `daysOn < 1` (or a non-positive cycle), so the
    /// medication is never active.
    case invalidCycle(daysOn: Int, daysOff: Int)

    /// `endDate` is earlier than `startDate`, so the schedule is empty.
    case endBeforeStart

    /// Two dose anchors resolve to the same time-of-day within a single day,
    /// producing overlapping (duplicate) doses.
    case duplicateDoseTimes(TimeOfDay)
}

// MARK: - Validation

extension ScheduleRule {
    /// Checks the rule for impossible or overlapping configurations. An empty
    /// result means the rule is valid.
    ///
    /// This guards the acceptance-criteria requirement to "prevent overlapping
    /// or impossible schedules" before the rule reaches the engine, notification
    /// scheduler, or persistence.
    public func validate() -> [ScheduleValidationError] {
        var errors: [ScheduleValidationError] = []

        if let endDate, endDate < startDate {
            errors.append(.endBeforeStart)
        }

        switch pattern {
        case .asNeeded:
            // PRN carries no anchors or cadence by construction, so it is always
            // valid regardless of start/end.
            return errors

        case let .everyNDays(interval, _):
            if interval < 1 {
                errors.append(.invalidInterval(interval))
            }

        case let .specificDays(weekdays, _):
            if weekdays.isEmpty {
                errors.append(.noWeekdaysSelected)
            }

        case let .cycling(daysOn, daysOff, _):
            if daysOn < 1 || daysOff < 0 || (daysOn + daysOff) < 1 {
                errors.append(.invalidCycle(daysOn: daysOn, daysOff: daysOff))
            }

        case .daily:
            break
        }

        // All scheduled patterns need at least one dose anchor.
        if pattern.anchors.isEmpty {
            errors.append(.missingDoseTimes)
        } else {
            errors.append(contentsOf: duplicateTimeErrors())
        }

        return errors
    }

    /// Detects anchors that resolve (via the window configuration) to the same
    /// time-of-day, which would fire overlapping doses.
    private func duplicateTimeErrors() -> [ScheduleValidationError] {
        var seen: Set<Int> = []
        var duplicates: [TimeOfDay] = []
        for anchor in pattern.anchors {
            let time = anchor.resolvedTime(using: windowConfiguration)
            if seen.insert(time.minutesSinceMidnight).inserted == false,
               !duplicates.contains(time) {
                duplicates.append(time)
            }
        }
        return duplicates
            .sorted()
            .map { ScheduleValidationError.duplicateDoseTimes($0) }
    }

    /// Convenience: whether the rule passes validation.
    public var isValid: Bool {
        validate().isEmpty
    }
}
