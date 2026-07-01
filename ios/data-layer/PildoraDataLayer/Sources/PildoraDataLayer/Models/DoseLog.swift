import Foundation
import GRDB

// MARK: - DoseLog

/// A single recorded dose event (taken / skipped / missed / snoozed). Adherence
/// history is derived from these rows. `scheduleId` is optional so as-needed
/// (PRN) doses, which have no schedule, can still be logged.
public struct DoseLog: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    public static let databaseTableName = "dose_log"

    public var id: String
    public var medicationId: String
    public var scheduleId: String?
    /// Denormalized owning vault for per-vault adherence queries.
    public var vaultId: String
    /// When the dose was due (nil for PRN logs).
    public var scheduledAt: Date?
    /// When the event was actually recorded.
    public var recordedAt: Date
    public var status: DoseStatus
    public var skipReason: String?
    public var notes: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        medicationId: String,
        scheduleId: String? = nil,
        vaultId: String,
        scheduledAt: Date? = nil,
        recordedAt: Date = Date(),
        status: DoseStatus = .taken,
        skipReason: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.medicationId = medicationId
        self.scheduleId = scheduleId
        self.vaultId = vaultId
        self.scheduledAt = scheduledAt
        self.recordedAt = recordedAt
        self.status = status
        self.skipReason = skipReason
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Record a taken dose now.
    public static func taken(
        medicationId: String,
        vaultId: String,
        scheduleId: String? = nil,
        at date: Date = Date()
    ) -> DoseLog {
        DoseLog(
            medicationId: medicationId,
            scheduleId: scheduleId,
            vaultId: vaultId,
            scheduledAt: scheduleId == nil ? nil : date,
            recordedAt: date,
            status: .taken
        )
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let medicationId = Column(CodingKeys.medicationId)
        public static let scheduleId = Column(CodingKeys.scheduleId)
        public static let vaultId = Column(CodingKeys.vaultId)
        public static let status = Column(CodingKeys.status)
        public static let recordedAt = Column(CodingKeys.recordedAt)
    }

    public static let medication = belongsTo(Medication.self)
}
