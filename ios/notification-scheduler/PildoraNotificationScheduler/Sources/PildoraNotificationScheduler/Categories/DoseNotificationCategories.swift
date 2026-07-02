import Foundation

// MARK: - NotificationActionDescriptor

/// A platform-neutral description of one actionable button on a notification.
public struct NotificationActionDescriptor: Hashable, Sendable {
    public var identifier: String
    public var title: String
    /// Whether tapping the action foregrounds the app (e.g. to open the dose
    /// confirmation screen). Taken/Skip/Snooze are handled in the background.
    public var opensApp: Bool

    public init(identifier: String, title: String, opensApp: Bool = false) {
        self.identifier = identifier
        self.title = title
        self.opensApp = opensApp
    }
}

// MARK: - NotificationCategoryDescriptor

/// A platform-neutral description of a notification category and its actions,
/// mapped to `UNNotificationCategory` by ``SystemNotificationCenter``.
public struct NotificationCategoryDescriptor: Hashable, Sendable {
    public var identifier: String
    public var actions: [NotificationActionDescriptor]

    public init(identifier: String, actions: [NotificationActionDescriptor]) {
        self.identifier = identifier
        self.actions = actions
    }
}

// MARK: - DoseNotificationCategories

/// The categories this package registers with the notification center.
public enum DoseNotificationCategories {

    /// Category identifier for actionable dose reminders.
    public static let doseReminder = "DOSE_REMINDER"

    /// Category identifier for the non-actionable overdue summary notification.
    public static let overdueSummary = "OVERDUE_SUMMARY"

    /// Thread identifier grouping all dose reminders together in Notification
    /// Center and on the Apple Watch.
    public static let doseThread = "pildora-doses"

    /// The dose-reminder category with Taken / Snooze / Skip actions, in the
    /// order they appear on the notification.
    public static func doseReminderCategory(
        snooze: SnoozeOption = .default
    ) -> NotificationCategoryDescriptor {
        NotificationCategoryDescriptor(
            identifier: doseReminder,
            actions: [
                NotificationActionDescriptor(
                    identifier: DoseNotificationAction.takenIdentifier,
                    title: "Taken"
                ),
                NotificationActionDescriptor(
                    identifier: DoseNotificationAction.snoozeIdentifier,
                    title: snooze.actionTitle
                ),
                NotificationActionDescriptor(
                    identifier: DoseNotificationAction.skipIdentifier,
                    title: "Skip"
                ),
            ]
        )
    }

    /// All categories to register during app launch.
    public static func all(snooze: SnoozeOption = .default) -> [NotificationCategoryDescriptor] {
        [
            doseReminderCategory(snooze: snooze),
            NotificationCategoryDescriptor(identifier: overdueSummary, actions: []),
        ]
    }
}
