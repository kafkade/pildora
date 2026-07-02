import Foundation
import PildoraDataLayer

// MARK: - Display helpers for shared model enums

// These presentation-only helpers live in the feature module (not the data
// layer) so `PildoraDataLayer` stays free of UI concerns. Full model unification
// (#48) moved the model types to the data layer; the display strings that used
// to hang off the feature's own enums are re-homed here as extensions.

public extension MedicationForm {
    /// Human-facing name for the form, e.g. "Tablet".
    var displayName: String { rawValue.capitalized }

    /// Singular noun used when describing inventory units (e.g. "tablet").
    var unitNoun: String {
        switch self {
        case .tablet: return "tablet"
        case .capsule: return "capsule"
        case .liquid: return "mL"
        case .injection: return "dose"
        case .patch: return "patch"
        case .drops: return "drop"
        case .gummy: return "gummy"
        case .powder: return "scoop"
        case .other: return "unit"
        }
    }
}

public extension MedicationCategory {
    /// Human-facing section title.
    var displayName: String {
        switch self {
        case .prescription: return "Prescription"
        case .overTheCounter: return "Over-the-Counter"
        case .supplement: return "Supplement"
        case .vitamin: return "Vitamin"
        }
    }

    /// Stable ordering for grouped section display.
    var sortOrder: Int {
        switch self {
        case .prescription: return 0
        case .overTheCounter: return 1
        case .supplement: return 2
        case .vitamin: return 3
        }
    }
}

public extension InventoryRecord {
    /// True when stock is critically low (at or below half the threshold, or 3
    /// units, whichever is larger) — used for stronger visual emphasis. Treats a
    /// missing threshold as 0.
    var isCritical: Bool {
        currentCount <= max(3, (refillThreshold ?? 0) / 2)
    }
}
