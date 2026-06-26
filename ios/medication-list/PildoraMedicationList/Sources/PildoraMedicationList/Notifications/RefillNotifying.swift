import Foundation

// MARK: - Refill Reminder

/// A request to remind the user to refill a medication that has run low.
public struct RefillReminder: Equatable, Sendable {
    public let medicationID: String
    public let medicationName: String
    public let remainingCount: Int
    public let unitNoun: String

    public init(medicationID: String, medicationName: String, remainingCount: Int, unitNoun: String) {
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.remainingCount = remainingCount
        self.unitNoun = unitNoun
    }

    /// Stable per-medication notification identifier so re-evaluating replaces
    /// (rather than duplicates) an existing reminder.
    public var notificationID: String { "refill.\(medicationID)" }

    public var title: String { "Refill \(medicationName)" }

    public var body: String {
        let unit = remainingCount == 1 ? unitNoun : "\(unitNoun)s"
        return "Only \(remainingCount) \(unit) left. Time to request a refill."
    }
}

// MARK: - RefillNotifying

/// Abstraction over local refill notifications.
///
/// Refill reminders are **local notifications only** — the server never learns
/// when a user is low on a medication (zero-knowledge constraint). The iOS
/// implementation uses `UNUserNotificationCenter`; a simulated implementation
/// is used for previews, tests, and the macOS toolchain build.
public protocol RefillNotifying: AnyObject {
    /// Schedule (or replace) a refill reminder for the reminder's medication.
    func scheduleRefillReminder(_ reminder: RefillReminder)
    /// Cancel any pending refill reminder for the given medication.
    func cancelRefillReminder(medicationID: String)
}

// MARK: - Simulated implementation

/// In-memory `RefillNotifying` used in previews, unit tests, and on platforms
/// without `UserNotifications`. Records the current set of pending reminders so
/// tests can assert scheduling behavior.
public final class SimulatedRefillNotifier: RefillNotifying {
    public private(set) var pending: [String: RefillReminder] = [:]

    public init() {}

    public func scheduleRefillReminder(_ reminder: RefillReminder) {
        pending[reminder.medicationID] = reminder
    }

    public func cancelRefillReminder(medicationID: String) {
        pending[medicationID] = nil
    }

    /// Convenience for assertions/UI: the pending reminders sorted by name.
    public var pendingReminders: [RefillReminder] {
        pending.values.sorted { $0.medicationName < $1.medicationName }
    }
}
