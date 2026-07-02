import Foundation

/// In-memory ``NotificationScheduling`` used by unit tests and the 48-hour
/// stress simulation. It faithfully mimics the two production behaviors that
/// matter for the rotation strategy:
///
/// 1. **Silent drop past the 64-pending limit.** Like the real center, `add`
///    beyond the limit completes without error and does not persist the request
///    (tracked via ``droppedCount`` so tests can assert the planner never
///    overflows).
/// 2. **Identifier-keyed replace.** Adding a request whose identifier already
///    exists overwrites it, matching `UNUserNotificationCenter` semantics.
public actor InMemoryNotificationCenter: NotificationScheduling {

    /// The iOS hard limit for pending local notifications per app.
    public static let pendingLimit = 64

    private var pending: [String: PlannedNotification] = [:]
    private var pendingOrder: [String] = []

    private var status: NotificationAuthorizationStatus
    private var grantOnRequest: Bool

    public private(set) var categories: [NotificationCategoryDescriptor] = []
    public private(set) var badgeCount: Int = 0

    /// Number of `add` calls silently dropped because the limit was reached.
    public private(set) var droppedCount: Int = 0
    /// Total successful `add` calls across the lifetime (for metrics).
    public private(set) var totalAdded: Int = 0
    /// Number of `requestAuthorization` calls made.
    public private(set) var authorizationRequestCount: Int = 0

    public init(
        initialStatus: NotificationAuthorizationStatus = .notDetermined,
        grantOnRequest: Bool = true
    ) {
        self.status = initialStatus
        self.grantOnRequest = grantOnRequest
    }

    // MARK: NotificationScheduling

    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        status
    }

    @discardableResult
    public func requestAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        // The system only prompts when undetermined; a settled decision stands.
        if status == .notDetermined {
            status = grantOnRequest ? .authorized : .denied
        }
        return status.canDeliver
    }

    public func setCategories(_ categories: [NotificationCategoryDescriptor]) async {
        self.categories = categories
    }

    public func pendingIdentifiers() async -> [String] {
        pendingOrder
    }

    public func add(_ notification: PlannedNotification) async throws {
        if let existingIndex = pendingOrder.firstIndex(of: notification.identifier) {
            // Replace in place — identifier-keyed, does not consume a new slot.
            pending[notification.identifier] = notification
            pendingOrder[existingIndex] = notification.identifier
            return
        }
        guard pendingOrder.count < Self.pendingLimit else {
            droppedCount += 1 // Silently dropped, exactly like the real center.
            return
        }
        pending[notification.identifier] = notification
        pendingOrder.append(notification.identifier)
        totalAdded += 1
    }

    public func removePending(identifiers: [String]) async {
        let removalSet = Set(identifiers)
        pendingOrder.removeAll { removalSet.contains($0) }
        for identifier in removalSet { pending.removeValue(forKey: identifier) }
    }

    public func setBadgeCount(_ count: Int) async {
        badgeCount = max(0, count)
    }

    // MARK: Test inspection

    /// The pending notifications in scheduling order.
    public func pendingNotifications() -> [PlannedNotification] {
        pendingOrder.compactMap { pending[$0] }
    }

    /// Pending notifications whose identifier marks them as dose reminders.
    public func pendingDoseNotifications() -> [PlannedNotification] {
        pendingNotifications().filter {
            $0.identifier.hasPrefix(DoseNotification.identifierPrefix)
        }
    }

    /// Overrides the authorization status (e.g. to simulate a denied user).
    public func setAuthorizationStatus(_ newStatus: NotificationAuthorizationStatus) {
        status = newStatus
    }
}
