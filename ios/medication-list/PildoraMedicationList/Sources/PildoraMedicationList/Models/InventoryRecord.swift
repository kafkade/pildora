import Foundation

// MARK: - Inventory Record

/// Manual inventory state for a medication: how many units remain, and the
/// user-configurable threshold at or below which a low-stock / refill alert
/// fires.
///
/// Inventory is **manual** in this feature (issue #50): the user edits the
/// count. Automatic decrement on dose confirmation belongs with dose logging
/// and is intentionally out of scope here.
public struct InventoryRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var medicationId: String
    /// Units (pills, mL, patches…) remaining.
    public var currentCount: Int
    /// Alert fires when `currentCount <= refillThreshold`. User-configurable.
    public var refillThreshold: Int
    /// Whether a refill reminder notification should be scheduled for this med.
    public var refillReminderEnabled: Bool
    public var lastRefillDate: Date?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        medicationId: String,
        currentCount: Int,
        refillThreshold: Int,
        refillReminderEnabled: Bool = true,
        lastRefillDate: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.medicationId = medicationId
        self.currentCount = currentCount
        self.refillThreshold = refillThreshold
        self.refillReminderEnabled = refillReminderEnabled
        self.lastRefillDate = lastRefillDate
        self.updatedAt = updatedAt
    }

    /// True when stock is at or below the user's threshold.
    public var isLow: Bool { currentCount <= refillThreshold }

    /// True when stock is critically low (at or below half the threshold,
    /// or 3 units, whichever is larger) — used for stronger visual emphasis.
    public var isCritical: Bool {
        currentCount <= max(3, refillThreshold / 2)
    }
}
