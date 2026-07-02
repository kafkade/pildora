import Foundation

// MARK: - TimeOfDay

/// A wall-clock time of day (hour + minute), independent of any calendar date
/// or timezone. Serialized as an `"HH:mm"` string to match the persisted
/// `Schedule.timesJson` encoding in the data layer.
///
/// This is a *wall-clock* value: `TimeOfDay(hour: 8, minute: 0)` means "8am
/// wherever the user is", not a fixed instant. The engine resolves it against
/// a concrete calendar day + `Calendar`/`TimeZone` when computing occurrences,
/// which is what makes travel and DST behave correctly.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public let hour: Int
    public let minute: Int

    /// Creates a time of day, or returns `nil` if the components fall outside
    /// `00:00…23:59`.
    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Parses an `"HH:mm"` string (e.g. `"08:00"`, `"20:30"`). Returns `nil`
    /// for malformed or out-of-range input.
    public init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              parts[0].count == 2,
              parts[1].count == 2
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    /// The zero-padded `"HH:mm"` representation.
    public var formatted: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Minutes elapsed since midnight, useful for ordering and de-duplication.
    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

extension TimeOfDay: CustomStringConvertible {
    public var description: String { formatted }
}
