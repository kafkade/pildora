import Foundation
import GRDB

// MARK: - Schedule

/// When a medication's doses recur. Pattern-specific data is stored as JSON
/// strings (`timesJson`, `daysJson`) so the schedule engine can evolve the
/// encoding without a schema migration.
public struct Schedule: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    public static let databaseTableName = "schedule"

    public var id: String
    public var medicationId: String
    /// Denormalized owning vault, so schedules can be queried per-vault without
    /// a join (matches the roadmap's "vault_id on all health data" rule).
    public var vaultId: String
    public var pattern: SchedulePattern
    /// JSON array of "HH:mm" strings, e.g. `["08:00","20:00"]`.
    public var timesJson: String
    /// JSON array of weekday tokens for `.specificDays`, e.g. `["mon","wed"]`.
    public var daysJson: String?
    /// Interval in days for the `.everyNDays` pattern.
    public var intervalDays: Int?
    public var startDate: Date
    public var endDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        medicationId: String,
        vaultId: String,
        pattern: SchedulePattern = .daily,
        timesJson: String = "[]",
        daysJson: String? = nil,
        intervalDays: Int? = nil,
        startDate: Date = Date(),
        endDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.medicationId = medicationId
        self.vaultId = vaultId
        self.pattern = pattern
        self.timesJson = timesJson
        self.daysJson = daysJson
        self.intervalDays = intervalDays
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The decoded list of dose times, or an empty array if `timesJson` is invalid.
    public var times: [String] {
        guard let data = timesJson.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return decoded
    }

    /// Build a daily schedule from a list of "HH:mm" times.
    public static func daily(
        medicationId: String,
        vaultId: String,
        times: [String],
        startDate: Date = Date()
    ) -> Schedule {
        let json = (try? JSONEncoder().encode(times)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return Schedule(
            medicationId: medicationId,
            vaultId: vaultId,
            pattern: .daily,
            timesJson: json,
            startDate: startDate
        )
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let medicationId = Column(CodingKeys.medicationId)
        public static let vaultId = Column(CodingKeys.vaultId)
        public static let pattern = Column(CodingKeys.pattern)
        public static let startDate = Column(CodingKeys.startDate)
    }

    public static let medication = belongsTo(Medication.self)
}
