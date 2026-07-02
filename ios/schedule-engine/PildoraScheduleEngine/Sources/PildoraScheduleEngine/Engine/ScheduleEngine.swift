import Foundation

// MARK: - ScheduleEngine

/// Computes concrete dose times from a `ScheduleRule`.
///
/// The engine is pure and deterministic: every query takes an explicit
/// `Calendar` (which carries the `TimeZone`), and occurrences are computed with
/// **wall-clock** semantics — a `TimeOfDay` of `08:00` means 8am in that
/// calendar's timezone on each active day. This makes timezone travel and DST
/// transitions fall out of `Calendar` arithmetic rather than requiring special
/// cases:
///
/// - **Travel:** query with the destination's `Calendar`/`TimeZone` and the
///   same rule yields doses at local 08:00 there.
/// - **DST spring-forward:** a nonexistent wall time resolves to the next valid
///   instant (Foundation's `Calendar.date(from:)` behavior).
/// - **DST fall-back:** an ambiguous wall time resolves to its earlier
///   occurrence.
///
/// > This is a timing tool only and provides no medical advice.
public struct ScheduleEngine: Sendable {
    public let rule: ScheduleRule

    public init(rule: ScheduleRule) {
        self.rule = rule
    }

    // MARK: Public API

    /// The next `count` dose times strictly after `date`, in chronological
    /// order. This is the primary API for local-notification scheduling and the
    /// Today view.
    ///
    /// PRN (`asNeeded`) schedules return an empty array. Returns fewer than
    /// `count` items when the schedule ends (via `endDate`) or no further doses
    /// occur within `maxLookaheadDays`.
    ///
    /// - Parameters:
    ///   - count: How many upcoming doses to return. Non-positive returns `[]`.
    ///   - date: The exclusive lower bound; only doses after this instant are
    ///     returned. Defaults to now.
    ///   - calendar: The calendar/timezone to resolve wall-clock times in.
    ///   - maxLookaheadDays: A safety bound on how far ahead to search for
    ///     sparse schedules. Defaults to ~10 years.
    public func nextDoses(
        count: Int,
        after date: Date = Date(),
        calendar: Calendar = .current,
        maxLookaheadDays: Int = 3660
    ) -> [DoseOccurrence] {
        guard count > 0, rule.pattern.isScheduled, !rule.pattern.anchors.isEmpty else {
            return []
        }

        let startDay = calendar.startOfDay(for: rule.startDate)
        let lastDay = rule.endDate.map { calendar.startOfDay(for: $0) }
        var day = max(startDay, calendar.startOfDay(for: date))

        var results: [DoseOccurrence] = []
        var daysScanned = 0

        while results.count < count, daysScanned <= maxLookaheadDays {
            if let lastDay, day > lastDay { break }

            if isActive(on: day, startDay: startDay, calendar: calendar) {
                for occurrence in occurrences(on: day, calendar: calendar)
                where occurrence.scheduledAt > date {
                    results.append(occurrence)
                    if results.count == count { break }
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            daysScanned += 1
        }

        return results
    }

    /// Every dose occurring within `interval` (inclusive of both ends), in
    /// chronological order. Useful for rendering a Today timeline or
    /// backfilling adherence over a range.
    public func occurrences(
        in interval: DateInterval,
        calendar: Calendar = .current
    ) -> [DoseOccurrence] {
        guard rule.pattern.isScheduled, !rule.pattern.anchors.isEmpty else { return [] }

        let startDay = calendar.startOfDay(for: rule.startDate)
        let lastDay = rule.endDate.map { calendar.startOfDay(for: $0) }
        var day = max(startDay, calendar.startOfDay(for: interval.start))

        var results: [DoseOccurrence] = []

        while day <= interval.end {
            if let lastDay, day > lastDay { break }

            if isActive(on: day, startDay: startDay, calendar: calendar) {
                for occurrence in occurrences(on: day, calendar: calendar)
                where occurrence.scheduledAt >= interval.start
                    && occurrence.scheduledAt <= interval.end {
                    results.append(occurrence)
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return results.sorted()
    }

    // MARK: Per-day computation

    /// The occurrences for a single active day, ordered by time-of-day.
    private func occurrences(on day: Date, calendar: Calendar) -> [DoseOccurrence] {
        let config = rule.windowConfiguration
        return rule.pattern.anchors.compactMap { anchor -> DoseOccurrence? in
            let time = anchor.resolvedTime(using: config)
            guard let instant = self.instant(on: day, at: time, calendar: calendar) else {
                return nil
            }
            return DoseOccurrence(
                scheduleId: rule.scheduleId,
                medicationId: rule.medicationId,
                vaultId: rule.vaultId,
                scheduledAt: instant,
                time: time,
                window: anchor.resolvedWindow(using: config)
            )
        }
        .sorted()
    }

    /// Whether the pattern fires on the given calendar day.
    private func isActive(on day: Date, startDay: Date, calendar: Calendar) -> Bool {
        guard let dayIndex = calendar.dateComponents([.day], from: startDay, to: day).day,
              dayIndex >= 0
        else { return false }

        switch rule.pattern {
        case .daily:
            return true

        case let .specificDays(weekdays, _):
            let value = calendar.component(.weekday, from: day)
            guard let weekday = Weekday(calendarValue: value) else { return false }
            return weekdays.contains(weekday)

        case let .everyNDays(interval, _):
            guard interval >= 1 else { return false }
            return dayIndex % interval == 0

        case let .cycling(daysOn, daysOff, _):
            let cycleLength = daysOn + daysOff
            guard cycleLength > 0, daysOn > 0 else { return false }
            return dayIndex % cycleLength < daysOn

        case .asNeeded:
            return false
        }
    }

    /// Resolves a wall-clock `TimeOfDay` on a specific day into an absolute
    /// instant in the given calendar. For nonexistent/ambiguous DST times,
    /// `Calendar.date(from:)` yields the next-valid / earlier instant
    /// respectively, matching the documented policy.
    private func instant(on day: Date, at time: TimeOfDay, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return calendar.date(from: components)
    }
}
