import Foundation

#if canImport(UserNotifications)
import UserNotifications

/// Production ``NotificationScheduling`` backed by `UNUserNotificationCenter`.
///
/// This is the only type in the package that touches `UserNotifications`. It is
/// intentionally a thin translation layer — all scheduling logic lives in the
/// platform-neutral planner/orchestrator, which is why the package can be fully
/// unit-tested against ``InMemoryNotificationCenter`` without a live center.
///
/// > Not instantiated in `swift test`: `UNUserNotificationCenter.current()`
/// > requires an app bundle. The type compiles on the macOS toolchain (so CI
/// > type-checks it) but is only constructed inside the running app.
public final class SystemNotificationCenter: NotificationScheduling, @unchecked Sendable {

    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    @discardableResult
    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    public func setCategories(_ categories: [NotificationCategoryDescriptor]) async {
        let mapped = categories.map { descriptor -> UNNotificationCategory in
            let actions = descriptor.actions.map { action -> UNNotificationAction in
                UNNotificationAction(
                    identifier: action.identifier,
                    title: action.title,
                    options: action.opensApp ? [.foreground] : []
                )
            }
            return UNNotificationCategory(
                identifier: descriptor.identifier,
                actions: actions,
                intentIdentifiers: [],
                options: []
            )
        }
        center.setNotificationCategories(Set(mapped))
    }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ notification: PlannedNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.content.title
        content.body = notification.content.body
        content.categoryIdentifier = notification.content.categoryIdentifier
        if let thread = notification.content.threadIdentifier {
            content.threadIdentifier = thread
        }
        if let badge = notification.content.badge {
            content.badge = NSNumber(value: badge)
        }
        if notification.content.playsSound {
            content.sound = .default
        }
        content.userInfo = notification.content.userInfo

        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: trigger(for: notification.fireDate)
        )
        try await center.add(request)
    }

    /// Builds the trigger for a fire date.
    ///
    /// - Imminent (< 60s away, e.g. the overdue summary): a short
    ///   `UNTimeIntervalNotificationTrigger`, since a minute-granularity
    ///   calendar trigger for the current/past minute would not fire.
    /// - Otherwise: a non-repeating `UNCalendarNotificationTrigger` on
    ///   year/month/day/hour/minute, which fires in the device's current
    ///   timezone — the correct behavior across travel and DST.
    private func trigger(for fireDate: Date) -> UNNotificationTrigger {
        let interval = fireDate.timeIntervalSinceNow
        if interval < 60 {
            return UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, interval), repeats: false
            )
        }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    public func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func setBadgeCount(_ count: Int) async {
        try? await center.setBadgeCount(max(0, count))
    }
}
#endif
