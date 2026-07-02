import Foundation

// MARK: - FTSQuery

/// Turns raw, user-typed text into a safe FTS5 `MATCH` expression for
/// autocomplete.
///
/// User input must never be interpolated into an FTS5 query directly: characters
/// like `"`, `*`, `:`, `(`, `-` and `^` are FTS5 operators and would either
/// change the query's meaning or raise a syntax error. We instead extract
/// alphanumeric tokens, quote each one (doubling any embedded quote), and append
/// a `*` for prefix matching so typing "met" matches "Metformin".
///
/// Multiple tokens are combined with implicit AND (FTS5's default), so
/// "vit d" narrows to results containing both prefixes.
public enum FTSQuery {

    /// Build a prefix `MATCH` expression from raw input, or `nil` when the input
    /// contains no searchable tokens (e.g. empty or punctuation-only).
    public static func prefixMatch(for raw: String) -> String? {
        let tokens = tokenize(raw)
        guard !tokens.isEmpty else { return nil }
        return tokens
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " ")
    }

    /// Split input into lowercased alphanumeric tokens, mirroring the index's
    /// `unicode61` tokenizer closely enough for prefix search.
    static func tokenize(_ raw: String) -> [String] {
        raw
            .lowercased()
            .components(separatedBy: tokenSeparators)
            .filter { !$0.isEmpty }
    }

    /// Everything that is not a letter or number separates tokens.
    private static let tokenSeparators: CharacterSet = CharacterSet.alphanumerics.inverted
}
