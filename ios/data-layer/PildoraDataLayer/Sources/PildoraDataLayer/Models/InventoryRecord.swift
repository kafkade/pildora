import Foundation
import GRDB

// MARK: - InventoryRecord

/// Current on-hand quantity for a medication, plus the low-stock threshold that
/// drives local refill reminders. One inventory row per medication (the
/// `medicationId` column is unique).
public struct InventoryRecord: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    public static let databaseTableName = "inventory"

    public var id: String
    public var medicationId: String
    /// Denormalized owning vault for per-vault inventory queries.
    public var vaultId: String
    public var currentCount: Int
    /// Reorder when `currentCount` falls to or below this value.
    public var refillThreshold: Int?
    public var lastRefillDate: Date?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        medicationId: String,
        vaultId: String,
        currentCount: Int,
        refillThreshold: Int? = nil,
        lastRefillDate: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.medicationId = medicationId
        self.vaultId = vaultId
        self.currentCount = currentCount
        self.refillThreshold = refillThreshold
        self.lastRefillDate = lastRefillDate
        self.updatedAt = updatedAt
    }

    /// True when stock has reached or dropped below the configured threshold.
    public var isLow: Bool {
        guard let refillThreshold else { return false }
        return currentCount <= refillThreshold
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let medicationId = Column(CodingKeys.medicationId)
        public static let vaultId = Column(CodingKeys.vaultId)
        public static let currentCount = Column(CodingKeys.currentCount)
    }

    public static let medication = belongsTo(Medication.self)
}
