import Foundation

// MARK: - DrugSuggestion

/// A single autocomplete result from the local drug index.
///
/// This is **public reference data** derived from the bundled openFDA / RxNorm
/// index — it is not user health data and is never encrypted. Autocomplete runs
/// entirely against the on-device index; queries never leave the device
/// (zero-knowledge constraint).
public struct DrugSuggestion: Identifiable, Hashable, Sendable {

    /// Whether the suggestion is a drug concept or a supplement.
    public enum Kind: String, Sendable, Hashable {
        case drug
        case supplement
    }

    /// Stable identity across the merged drug + supplement result set,
    /// e.g. `"drug-42"` or `"supplement-7"`.
    public let id: String

    /// The name to display and to prefill the medication name field with
    /// (a drug's preferred name, or the supplement's product name).
    public let displayName: String

    /// The generic name, when known (drugs only; `nil` for supplements).
    public let genericName: String?

    /// RxNorm concept id, when matched (drugs only; `nil` for supplements).
    public let rxcui: String?

    /// Drug vs. supplement.
    public let kind: Kind

    public init(
        id: String,
        displayName: String,
        genericName: String? = nil,
        rxcui: String? = nil,
        kind: Kind
    ) {
        self.id = id
        self.displayName = displayName
        self.genericName = genericName
        self.rxcui = rxcui
        self.kind = kind
    }

    /// A short secondary line for the suggestion row, e.g. the generic name for
    /// a brand match, or the word "Supplement".
    public var subtitle: String? {
        switch kind {
        case .drug:
            guard let genericName, !genericName.isEmpty,
                  genericName.caseInsensitiveCompare(displayName) != .orderedSame
            else { return nil }
            return genericName
        case .supplement:
            return "Supplement"
        }
    }
}
