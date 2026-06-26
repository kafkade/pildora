import Foundation

// MARK: - Drug Reference

/// Public, plaintext drug reference data shown alongside a medication.
///
/// This is **published reference data** (e.g. from openFDA / RxNorm via the
/// local ETL index), not user health data — it is not encrypted. Per the
/// project's disclaimer rules, every reference datum must display its
/// `source` and `sourceDate`, and reference UI must carry the
/// informational-only disclaimer.
///
/// Risk classification: 🟡 Informational — displays published reference data
/// with source attribution. It must never present dosing recommendations or
/// diagnostic suggestions.
public struct DrugReference: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    /// Therapeutic / pharmacologic class, e.g. "Biguanide (antidiabetic)".
    public var drugClass: String
    /// Commonly reported side effects (informational, not exhaustive).
    public var commonSideEffects: [String]
    /// Attribution: where this datum came from, e.g. "openFDA" or "RxNorm".
    public var source: String
    /// The date the source data was published / last refreshed.
    public var sourceDate: Date

    public init(
        id: String = UUID().uuidString,
        drugClass: String,
        commonSideEffects: [String],
        source: String,
        sourceDate: Date
    ) {
        self.id = id
        self.drugClass = drugClass
        self.commonSideEffects = commonSideEffects
        self.source = source
        self.sourceDate = sourceDate
    }

    /// The standard informational-only disclaimer required on all reference data.
    public static let disclaimer =
        "This is informational only. Consult your healthcare provider."

    /// "Source: openFDA · Jan 12, 2026" — attribution line for display.
    public func attribution(formatter: DateFormatter = DrugReference.attributionDateFormatter) -> String {
        "Source: \(source) · \(formatter.string(from: sourceDate))"
    }

    public static let attributionDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
