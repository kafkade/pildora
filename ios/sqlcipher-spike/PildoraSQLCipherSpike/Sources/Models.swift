import Foundation
import GRDB

// MARK: - Medication

struct Medication: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "medication"

    var id: String
    var vaultId: String
    var name: String
    var genericName: String?
    var dosage: String
    var form: String
    var frequency: String
    var prescriber: String?
    var pharmacy: String?
    var notes: String?
    var rxnormId: String?
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let vaultId = Column(CodingKeys.vaultId)
        static let name = Column(CodingKeys.name)
        static let genericName = Column(CodingKeys.genericName)
        static let dosage = Column(CodingKeys.dosage)
        static let form = Column(CodingKeys.form)
        static let frequency = Column(CodingKeys.frequency)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    static func new(
        vaultId: String,
        name: String,
        genericName: String? = nil,
        dosage: String,
        form: String = "tablet",
        frequency: String = "daily"
    ) -> Medication {
        let now = Date()
        return Medication(
            id: UUID().uuidString,
            vaultId: vaultId,
            name: name,
            genericName: genericName,
            dosage: dosage,
            form: form,
            frequency: frequency,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - Schedule

struct Schedule: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "schedule"

    var id: String
    var medicationId: String
    var pattern: String       // daily, multi_daily, every_n_days, specific_days, prn
    var timesJson: String     // JSON array of time strings, e.g. ["08:00","20:00"]
    var daysJson: String?     // JSON array for specific_days, e.g. ["mon","wed","fri"]
    var intervalDays: Int?    // for every_n_days pattern
    var startDate: String
    var endDate: String?
    var createdAt: Date
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let medicationId = Column(CodingKeys.medicationId)
        static let pattern = Column(CodingKeys.pattern)
        static let startDate = Column(CodingKeys.startDate)
    }

    static func daily(
        medicationId: String,
        times: [String],
        startDate: String = "2026-01-01"
    ) -> Schedule {
        let now = Date()
        let timesData = try! JSONEncoder().encode(times)
        return Schedule(
            id: UUID().uuidString,
            medicationId: medicationId,
            pattern: "daily",
            timesJson: String(data: timesData, encoding: .utf8)!,
            startDate: startDate,
            createdAt: now,
            updatedAt: now
        )
    }
}

// MARK: - DoseLog

struct DoseLog: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "dose_log"

    var id: String
    var medicationId: String
    var scheduleId: String?
    var scheduledAt: Date?
    var recordedAt: Date
    var status: String        // taken, skipped, missed
    var skipReason: String?
    var notes: String?
    var createdAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let medicationId = Column(CodingKeys.medicationId)
        static let status = Column(CodingKeys.status)
        static let recordedAt = Column(CodingKeys.recordedAt)
    }

    static func taken(medicationId: String, scheduleId: String? = nil) -> DoseLog {
        let now = Date()
        return DoseLog(
            id: UUID().uuidString,
            medicationId: medicationId,
            scheduleId: scheduleId,
            scheduledAt: now,
            recordedAt: now,
            status: "taken",
            createdAt: now
        )
    }
}

// MARK: - InventoryRecord

struct InventoryRecord: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "inventory"

    var id: String
    var medicationId: String
    var currentCount: Int
    var refillThreshold: Int?
    var lastRefillDate: String?
    var updatedAt: Date

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let medicationId = Column(CodingKeys.medicationId)
        static let currentCount = Column(CodingKeys.currentCount)
    }
}
