import Foundation

// MARK: - DoseAnchor

/// Where a single dose within a day is pinned. Either an explicit wall-clock
/// time, or a `DoseTimeWindow` that resolves to a time via the schedule's
/// `TimeWindowConfiguration`.
///
/// Using an anchor (rather than only a `TimeOfDay`) lets a schedule say
/// "morning + bedtime" and follow the user's configured window times, while
/// still supporting precise `"HH:mm"` entries.
public enum DoseAnchor: Codable, Hashable, Sendable {
    case time(TimeOfDay)
    case window(DoseTimeWindow)

    /// Resolves the anchor to a concrete time using the supplied window
    /// configuration.
    public func resolvedTime(using configuration: TimeWindowConfiguration) -> TimeOfDay {
        switch self {
        case let .time(time):
            return time
        case let .window(window):
            return configuration.time(for: window)
        }
    }

    /// The window this anchor belongs to once resolved, for UI grouping.
    public func resolvedWindow(using configuration: TimeWindowConfiguration) -> DoseTimeWindow {
        switch self {
        case let .window(window):
            return window
        case let .time(time):
            return DoseTimeWindow.containing(time)
        }
    }
}

extension DoseAnchor {
    /// Convenience for building an anchor from an `"HH:mm"` string. Returns
    /// `nil` if the string is malformed.
    public static func time(_ string: String) -> DoseAnchor? {
        TimeOfDay(string).map(DoseAnchor.time)
    }
}
