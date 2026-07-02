import Foundation

// MARK: - NotificationAuthorizationStatus

/// Platform-neutral mirror of `UNAuthorizationStatus`, so callers and tests can
/// reason about permission without importing `UserNotifications`.
public enum NotificationAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    /// Whether the app may currently deliver visible dose reminders.
    public var canDeliver: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied: return false
        }
    }
}

// MARK: - NotificationContent

/// Platform-neutral notification payload built by the content layer and handed
/// to the center seam. `SystemNotificationCenter` maps this onto
/// `UNMutableNotificationContent`.
public struct NotificationContent: Hashable, Sendable {
    public var title: String
    public var body: String
    public var categoryIdentifier: String
    /// Groups related notifications (e.g. all dose reminders) in Notification
    /// Center and on the Watch.
    public var threadIdentifier: String?
    /// App icon badge to set when this notification is delivered. `nil` leaves
    /// the badge unchanged.
    public var badge: Int?
    /// Whether to play the default alert sound.
    public var playsSound: Bool
    /// Opaque, non-sensitive routing hints (identifiers only — never health
    /// data) echoed back when the user acts on the notification.
    public var userInfo: [String: String]

    public init(
        title: String,
        body: String,
        categoryIdentifier: String,
        threadIdentifier: String? = nil,
        badge: Int? = nil,
        playsSound: Bool = true,
        userInfo: [String: String] = [:]
    ) {
        self.title = title
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier
        self.badge = badge
        self.playsSound = playsSound
        self.userInfo = userInfo
    }
}

// MARK: - PlannedNotification

/// A fully-resolved notification ready to be handed to the notification center:
/// a stable identifier, its content, and the wall-clock instant it should fire.
public struct PlannedNotification: Hashable, Sendable {
    public var identifier: String
    public var content: NotificationContent
    /// The instant the notification should fire. `SystemNotificationCenter`
    /// converts this into a non-repeating `UNCalendarNotificationTrigger` on
    /// year/month/day/hour/minute components, which fires in the device's
    /// current timezone (correct behavior across travel and DST).
    public var fireDate: Date

    public init(identifier: String, content: NotificationContent, fireDate: Date) {
        self.identifier = identifier
        self.content = content
        self.fireDate = fireDate
    }
}

// MARK: - NotificationScheduling

/// The minimal seam over `UNUserNotificationCenter` this package depends on.
///
/// Keeping the surface this small means the planner, content builder, overdue
/// tracker, and orchestrator are all exercised in CI against
/// ``InMemoryNotificationCenter`` with no entitlements, bundle, or live system
/// notification center — while ``SystemNotificationCenter`` provides the real
/// behavior on device.
public protocol NotificationScheduling: AnyObject, Sendable {
    /// Current permission state.
    func authorizationStatus() async -> NotificationAuthorizationStatus

    /// Requests alert + badge + sound authorization (the onboarding prompt).
    /// Returns whether authorization was granted.
    @discardableResult
    func requestAuthorization() async throws -> Bool

    /// Registers the actionable categories (dose reminder Taken/Snooze/Skip).
    func setCategories(_ categories: [NotificationCategoryDescriptor]) async

    /// Identifiers of all currently pending (scheduled, not yet delivered)
    /// notification requests.
    func pendingIdentifiers() async -> [String]

    /// Schedules a notification. On the real center, exceeding the 64-pending
    /// limit causes the request to be **silently dropped** — the rotation
    /// planner is responsible for never planning more than the budget allows.
    func add(_ notification: PlannedNotification) async throws

    /// Removes the given pending notifications by identifier.
    func removePending(identifiers: [String]) async

    /// Sets the app icon badge (missed-dose count). `0` clears it.
    func setBadgeCount(_ count: Int) async
}
