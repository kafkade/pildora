import Foundation

// MARK: - SchedulePattern

/// How a medication's doses recur. This is the engine's richer pattern model:
/// it is a superset of the persisted `SchedulePattern` (data layer), adding
/// `cycling` and letting each pattern carry `DoseAnchor`s (so time windows and
/// multi-daily fall out naturally). Mapping to/from the persisted model is the
/// job of a future persistence-wiring layer, not the engine.
///
/// - `daily`: fire at each anchor every day (one anchor = once daily, many
///   anchors = multi-daily, e.g. 3×/day).
/// - `specificDays`: like `daily`, but only on the listed weekdays.
/// - `everyNDays`: fire at each anchor once every `interval` days, counted
///   from the schedule's `startDate`.
/// - `cycling`: `daysOn` active days followed by `daysOff` inactive days,
///   repeating from `startDate` (e.g. 21 on / 7 off, or 5 on / 2 off). Fires at
///   each anchor on active days only.
/// - `asNeeded`: PRN. Produces **no** computed occurrences; doses are logged
///   manually.
public enum SchedulePattern: Hashable, Sendable {
    case daily(anchors: [DoseAnchor])
    case specificDays(weekdays: Set<Weekday>, anchors: [DoseAnchor])
    case everyNDays(interval: Int, anchors: [DoseAnchor])
    case cycling(daysOn: Int, daysOff: Int, anchors: [DoseAnchor])
    case asNeeded

    /// The dose anchors for this pattern (empty for `asNeeded`).
    public var anchors: [DoseAnchor] {
        switch self {
        case let .daily(anchors),
             let .specificDays(_, anchors),
             let .everyNDays(_, anchors),
             let .cycling(_, _, anchors):
            return anchors
        case .asNeeded:
            return []
        }
    }

    /// Whether the pattern ever produces scheduled occurrences. `asNeeded` does
    /// not.
    public var isScheduled: Bool {
        if case .asNeeded = self { return false }
        return true
    }
}
