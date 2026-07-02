import Foundation
import PildoraDrugIndex

// MARK: - DrugSuggesting

/// Autocomplete seam for the medication editor.
///
/// The editor depends on this protocol rather than on `PildoraDrugIndex`
/// directly, so previews and unit tests can inject a deterministic fake while
/// the app injects the real bundled FTS5 `DrugIndex`.
///
/// Zero-knowledge: implementations query a **local** index only. Autocomplete
/// text is never sent to a server.
public protocol DrugSuggesting: Sendable {
    /// Ranked drug + supplement matches for a prefix query (already trimmed).
    func suggestions(matching query: String, limit: Int) throws -> [DrugSuggestion]
}

extension DrugIndex: DrugSuggesting {
    public func suggestions(matching query: String, limit: Int) throws -> [DrugSuggestion] {
        try search(query, limit: limit)
    }
}
