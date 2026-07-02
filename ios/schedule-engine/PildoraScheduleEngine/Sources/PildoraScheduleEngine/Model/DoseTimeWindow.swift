import Foundation

// MARK: - DoseTimeWindow

/// A coarse part of the day a dose belongs to. Mirrors the today-view's
/// `DoseTimeWindow` so computed occurrences can be grouped into the same
/// morning/afternoon/evening/bedtime sections the UI already renders.
///
/// A window is *not* a concrete time on its own — it resolves to a
/// `TimeOfDay` through a `TimeWindowConfiguration`, which the user can
/// customize (e.g. "morning = 07:30").
public enum DoseTimeWindow: String, CaseIterable, Codable, Sendable {
    case morning
    case afternoon
    case evening
    case bedtime

    /// Stable chronological ordering for grouping/sorting.
    public var sortOrder: Int {
        switch self {
        case .morning: return 0
        case .afternoon: return 1
        case .evening: return 2
        case .bedtime: return 3
        }
    }

    /// The window a concrete time falls into. Boundaries match the today-view:
    /// morning 05–11, afternoon 12–16, evening 17–20, otherwise bedtime.
    public static func containing(_ time: TimeOfDay) -> DoseTimeWindow {
        switch time.hour {
        case 5...11: return .morning
        case 12...16: return .afternoon
        case 17...20: return .evening
        default: return .bedtime
        }
    }
}

// MARK: - TimeWindowConfiguration

/// Maps each `DoseTimeWindow` to the concrete `TimeOfDay` a dose fires at.
/// These are user-configurable; the defaults below are sensible starting
/// points (08:00 / 13:00 / 18:00 / 22:00).
public struct TimeWindowConfiguration: Codable, Hashable, Sendable {
    public var morning: TimeOfDay
    public var afternoon: TimeOfDay
    public var evening: TimeOfDay
    public var bedtime: TimeOfDay

    public init(
        morning: TimeOfDay,
        afternoon: TimeOfDay,
        evening: TimeOfDay,
        bedtime: TimeOfDay
    ) {
        self.morning = morning
        self.afternoon = afternoon
        self.evening = evening
        self.bedtime = bedtime
    }

    /// The default window times: 08:00 / 13:00 / 18:00 / 22:00.
    public static let `default` = TimeWindowConfiguration(
        // Force-unwraps are safe: all components are in range.
        morning: TimeOfDay(hour: 8, minute: 0)!,
        afternoon: TimeOfDay(hour: 13, minute: 0)!,
        evening: TimeOfDay(hour: 18, minute: 0)!,
        bedtime: TimeOfDay(hour: 22, minute: 0)!
    )

    /// The concrete time configured for a given window.
    public func time(for window: DoseTimeWindow) -> TimeOfDay {
        switch window {
        case .morning: return morning
        case .afternoon: return afternoon
        case .evening: return evening
        case .bedtime: return bedtime
        }
    }
}
