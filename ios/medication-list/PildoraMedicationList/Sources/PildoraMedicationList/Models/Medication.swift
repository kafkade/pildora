import Foundation

// MARK: - Medication Form

/// The physical form a medication or supplement takes.
public enum MedicationForm: String, Codable, CaseIterable, Sendable {
    case tablet
    case capsule
    case liquid
    case injection
    case patch
    case drops
    case gummy
    case powder

    /// Singular noun used when describing inventory units (e.g. "tablet").
    public var unitNoun: String {
        switch self {
        case .tablet: return "tablet"
        case .capsule: return "capsule"
        case .liquid: return "mL"
        case .injection: return "dose"
        case .patch: return "patch"
        case .drops: return "drop"
        case .gummy: return "gummy"
        case .powder: return "scoop"
        }
    }

    public var displayName: String { rawValue.capitalized }
}

// MARK: - Medication Category

/// Grouping bucket used to organize the medication list.
public enum MedicationCategory: String, Codable, CaseIterable, Sendable {
    case prescription
    case overTheCounter
    case supplement
    case vitamin

    public var displayName: String {
        switch self {
        case .prescription: return "Prescription"
        case .overTheCounter: return "Over-the-Counter"
        case .supplement: return "Supplement"
        case .vitamin: return "Vitamin"
        }
    }

    /// Stable ordering for grouped section display.
    public var sortOrder: Int {
        switch self {
        case .prescription: return 0
        case .overTheCounter: return 1
        case .supplement: return 2
        case .vitamin: return 3
        }
    }
}

// MARK: - Medication

/// A medication or supplement the user tracks.
///
/// Mirrors the field shape validated in the SQLCipher spike's `Medication`
/// record (`id`, `vaultId`, `name`, `genericName`, `dosage`, `form`,
/// `frequency`, `prescriber`, `notes`, `rxnormId`) so it can be mapped onto
/// the real persistence layer (#44/#48) with minimal friction.
public struct Medication: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    /// One vault = one encryption boundary. Carried from day one per repo convention.
    public var vaultId: String
    public var name: String
    public var genericName: String?
    public var dosage: String
    public var form: MedicationForm
    public var category: MedicationCategory
    public var frequency: String
    public var prescriber: String?
    public var notes: String?
    /// RxNorm concept id from the local drug index, when matched.
    public var rxnormId: String?
    /// Reference id linking to a `DrugReference`, when available.
    public var drugReferenceId: String?

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
        notes: String? = nil,
        rxnormId: String? = nil,
        drugReferenceId: String? = nil
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
        self.notes = notes
        self.rxnormId = rxnormId
        self.drugReferenceId = drugReferenceId
    }

    /// "Levothyroxine 88 mcg" — name plus dosage for compact display.
    public var titleWithDosage: String { "\(name) \(dosage)" }
}
