import Foundation

// MARK: - NotificationBudget

/// The slot budget for pending local notifications, derived from the iOS
/// 64-pending hard limit validated in the `notification-spike` (issue #23).
///
/// A few slots are reserved for non-dose notifications (low-inventory alerts,
/// refill reminders, one-shot snoozes, system alerts) so a full dose queue can
/// never starve them.
public struct NotificationBudget: Equatable, Sendable {

    /// The iOS hard limit for pending local notifications per app.
    public static let iosLimit = 64

    /// Slots reserved for non-dose notifications.
    public let reservedSlots: Int

    public init(reservedSlots: Int = 4) {
        precondition(reservedSlots >= 0 && reservedSlots < Self.iosLimit,
                     "reservedSlots must be within the iOS limit")
        self.reservedSlots = reservedSlots
    }

    /// Maximum number of dose notifications that may be pending at once.
    public var maxDoseNotifications: Int {
        Self.iosLimit - reservedSlots
    }

    /// The default budget: 60 dose slots, 4 reserved.
    public static let `default` = NotificationBudget()
}
