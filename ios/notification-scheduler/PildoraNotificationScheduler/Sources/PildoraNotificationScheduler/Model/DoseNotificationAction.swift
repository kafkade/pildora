import Foundation

// MARK: - SnoozeOption

/// The snooze presets offered on a dose reminder ("Snooze 10/15/30 min").
///
/// A snooze reschedules a single one-shot reminder for the same dose at
/// `now + minutes`; it does not alter the underlying schedule.
public enum SnoozeOption: Int, CaseIterable, Codable, Sendable, CustomStringConvertible {
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    /// The preset used when the user taps the default "Snooze" action.
    public static let `default`: SnoozeOption = .fifteenMinutes

    public var minutes: Int { rawValue }

    /// Short label for the notification action button ("Snooze 15m").
    public var actionTitle: String { "Snooze \(minutes)m" }

    public var description: String { "\(minutes)m" }
}

// MARK: - DoseNotificationAction

/// The user's response to a dose reminder, produced from a tapped notification
/// action. The orchestrator translates these into dose-log outcomes the app
/// applies to its encrypted store.
public enum DoseNotificationAction: Hashable, Sendable {
    /// User confirmed the dose was taken. Logs a `taken` dose.
    case taken
    /// User skipped the dose. Logs a `skipped` dose.
    case skip
    /// User deferred the reminder by `minutes`. Reschedules a one-shot reminder.
    case snooze(minutes: Int)

    /// The stable action identifier registered with the notification category
    /// and reported back by the system when the user taps a button.
    public var identifier: String {
        switch self {
        case .taken: return Self.takenIdentifier
        case .skip: return Self.skipIdentifier
        case .snooze: return Self.snoozeIdentifier
        }
    }

    public static let takenIdentifier = "TAKEN"
    public static let skipIdentifier = "SKIP"
    public static let snoozeIdentifier = "SNOOZE"

    /// Reconstructs an action from a system action identifier. Snooze uses the
    /// default preset because the system reports only the identifier of the
    /// tapped button; multi-duration snooze is offered via distinct categories
    /// or the in-app confirmation screen.
    public init?(identifier: String, snooze: SnoozeOption = .default) {
        switch identifier {
        case Self.takenIdentifier: self = .taken
        case Self.skipIdentifier: self = .skip
        case Self.snoozeIdentifier: self = .snooze(minutes: snooze.minutes)
        default: return nil
        }
    }
}
