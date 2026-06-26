import Foundation

#if os(iOS)
import UserNotifications

/// `RefillNotifying` backed by `UNUserNotificationCenter`.
///
/// Schedules **local** notifications only. Each medication maps to a single
/// stable notification id, so re-scheduling replaces the previous reminder
/// rather than stacking duplicates — this also keeps refill reminders within
/// the reserved slots of the app's 64-notification budget (see the
/// notification spike).
public final class LocalRefillNotifier: RefillNotifying {
    private let center: UNUserNotificationCenter
    /// Delay before a freshly-triggered refill reminder fires, so it does not
    /// interrupt the action that caused it (e.g. editing the count).
    private let fireDelay: TimeInterval

    public init(
        center: UNUserNotificationCenter = .current(),
        fireDelay: TimeInterval = 60 * 60
    ) {
        self.center = center
        self.fireDelay = fireDelay
    }

    /// Request authorization for alerts/sounds/badges. Safe to call repeatedly.
    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func scheduleRefillReminder(_ reminder: RefillReminder) {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.threadIdentifier = "refill"

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, fireDelay),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: reminder.notificationID,
            content: content,
            trigger: trigger
        )
        // Replace any existing reminder for this medication first.
        center.removePendingNotificationRequests(withIdentifiers: [reminder.notificationID])
        center.add(request)
    }

    public func cancelRefillReminder(medicationID: String) {
        let id = "refill.\(medicationID)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
}
#endif
