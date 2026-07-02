import Foundation

// MARK: - Weekday

/// A day of the week. Raw values are the lowercase three-letter tokens used by
/// the persisted `Schedule.daysJson` array (e.g. `["mon","wed"]`), so the
/// engine's `specificDays` pattern maps cleanly onto stored data.
public enum Weekday: String, CaseIterable, Codable, Sendable {
    case sunday = "sun"
    case monday = "mon"
    case tuesday = "tue"
    case wednesday = "wed"
    case thursday = "thu"
    case friday = "fri"
    case saturday = "sat"

    /// The `Calendar` weekday component value (1 = Sunday … 7 = Saturday),
    /// matching Foundation's `Calendar.component(.weekday:)`.
    public var calendarValue: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        }
    }

    /// Builds a `Weekday` from a `Calendar` weekday component (1…7).
    public init?(calendarValue: Int) {
        switch calendarValue {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}
