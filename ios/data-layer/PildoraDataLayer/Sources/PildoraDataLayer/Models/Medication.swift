import Foundation
import GRDB

// MARK: - Medication

/// A medication or supplement the user tracks. Every field lives inside the
/// vault's SQLCipher database; nothing here is ever stored or synced in
/// plaintext.
///
/// Reference-data links (`rxnormId`, `drugReferenceId`) are nullable and
/// unenforced at this layer — they connect to the plaintext, public drug index
/// (openFDA / RxNorm) and are populated opportunistically. They anticipate the
/// Phase 3 drug-reference and interaction features.
public struct Medication: Codable, Identifiable, FetchableRecord, PersistableRecord, Hashable, Sendable {
    public static let databaseTableName = "medication"

    public var id: String
    /// Owning vault (encryption boundary). Carried on every health row from day one.
    public var vaultId: String
    public var name: String
    public var genericName: String?
    public var dosage: String
    public var form: MedicationForm
    public var category: MedicationCategory
    public var frequency: String
    public var prescriber: String?
    public var pharmacy: String?
    public var notes: String?
    /// RxNorm concept id from the local drug index, when matched (Phase 3).
    public var rxnormId: String?
    /// Reference id linking to a bundled `DrugReference`, when available (Phase 3).
    public var drugReferenceId: String?
    public var startDate: Date?
    public var endDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        vaultId: String,
        name: String,
        genericName: String? = nil,
        dosage: String,
        form: MedicationForm = .tablet,
        category: MedicationCategory = .prescription,
        frequency: String = "Once daily",
        prescriber: String? = nil,
        pharmacy: String? = nil,
        notes: String? = nil,
        rxnormId: String? = nil,
        drugReferenceId: String? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.vaultId = vaultId
        self.name = name
        self.genericName = genericName
        self.dosage = dosage
        self.form = form
        self.category = category
        self.frequency = frequency
        self.prescriber = prescriber
        self.pharmacy = pharmacy
        self.notes = notes
        self.rxnormId = rxnormId
        self.drugReferenceId = drugReferenceId
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// "Levothyroxine 88 mcg" — name plus dosage for compact display.
    public var titleWithDosage: String { "\(name) \(dosage)" }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let vaultId = Column(CodingKeys.vaultId)
        public static let name = Column(CodingKeys.name)
        public static let genericName = Column(CodingKeys.genericName)
        public static let dosage = Column(CodingKeys.dosage)
        public static let form = Column(CodingKeys.form)
        public static let category = Column(CodingKeys.category)
        public static let frequency = Column(CodingKeys.frequency)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let updatedAt = Column(CodingKeys.updatedAt)
    }

    public static let schedules = hasMany(Schedule.self)
    public static let doseLogs = hasMany(DoseLog.self)
    public static let inventory = hasOne(InventoryRecord.self)
}
