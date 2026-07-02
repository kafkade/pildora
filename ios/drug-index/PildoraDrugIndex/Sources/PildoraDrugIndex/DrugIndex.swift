import Foundation
import GRDB

// MARK: - DrugIndex

/// Read-only reader over the bundled, plaintext FTS5 drug/supplement index.
///
/// The index is produced by the Python ETL pipeline (`data/`) and ships with the
/// app as public reference data. Its schema — the `drug_fts` / `supplement_fts`
/// virtual tables and their `drug_concepts` / `supplements` content tables — is
/// mirrored here so autocomplete runs entirely on-device.
///
/// ## Zero-knowledge
/// Every lookup is a local SQLite query. No query text, keystroke, or result is
/// ever sent to a server. This is a hard constraint, not a convenience.
public struct DrugIndex: Sendable {
    private let dbQueue: DatabaseQueue

    /// Open the index at `path`. Opened read-only by default since the bundled
    /// index is immutable reference data.
    ///
    /// - Parameters:
    ///   - path: Filesystem path to the index `.db`.
    ///   - readonly: Open read-only (default `true`).
    public init(path: String, readonly: Bool = true) throws {
        var config = Configuration()
        config.readonly = readonly
        self.dbQueue = try DatabaseQueue(path: path, configuration: config)
    }

    /// Wrap an already-open queue (used by tests and previews).
    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: Search

    /// Autocomplete against the index, returning merged drug + supplement
    /// suggestions ordered by FTS5 relevance (best first).
    ///
    /// Returns an empty array for blank/punctuation-only input. Never throws for
    /// malformed FTS syntax — user input is sanitized into a safe prefix query.
    ///
    /// - Parameters:
    ///   - query: Raw, user-typed text.
    ///   - limit: Maximum number of merged suggestions to return.
    public func search(_ query: String, limit: Int = 10) throws -> [DrugSuggestion] {
        guard limit > 0, let match = FTSQuery.prefixMatch(for: query) else { return [] }

        return try dbQueue.read { db in
            let drugs = try rankedDrugs(db, match: match, limit: limit)
            let supplements = try rankedSupplements(db, match: match, limit: limit)

            // Interleave by rank (lower is better, matching the ETL's search.py).
            let merged = (drugs + supplements)
                .sorted { $0.rank < $1.rank }
                .prefix(limit)
                .map(\.suggestion)
            return Array(merged)
        }
    }

    /// The index's `schema_version` metadata value, if present.
    public func schemaVersion() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM metadata WHERE key = 'schema_version'"
            )
        }
    }

    // MARK: Private

    private struct RankedSuggestion {
        let rank: Double
        let suggestion: DrugSuggestion
    }

    private func rankedDrugs(_ db: Database, match: String, limit: Int) throws -> [RankedSuggestion] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT dc.id AS id,
                   dc.preferred_name AS preferred_name,
                   dc.generic_name AS generic_name,
                   dc.rxcui AS rxcui,
                   drug_fts.rank AS rank
            FROM drug_fts
            JOIN drug_concepts dc ON dc.id = drug_fts.rowid
            WHERE drug_fts MATCH ?
            ORDER BY drug_fts.rank
            LIMIT ?
            """,
            arguments: [match, limit]
        )
        return rows.map { row in
            let id: Int64 = row["id"]
            return RankedSuggestion(
                rank: row["rank"] ?? 0,
                suggestion: DrugSuggestion(
                    id: "drug-\(id)",
                    displayName: row["preferred_name"] ?? "",
                    genericName: row["generic_name"],
                    rxcui: row["rxcui"],
                    kind: .drug
                )
            )
        }
    }

    private func rankedSupplements(_ db: Database, match: String, limit: Int) throws -> [RankedSuggestion] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT s.id AS id,
                   s.name AS name,
                   supplement_fts.rank AS rank
            FROM supplement_fts
            JOIN supplements s ON s.id = supplement_fts.rowid
            WHERE supplement_fts MATCH ?
            ORDER BY supplement_fts.rank
            LIMIT ?
            """,
            arguments: [match, limit]
        )
        return rows.map { row in
            let id: Int64 = row["id"]
            return RankedSuggestion(
                rank: row["rank"] ?? 0,
                suggestion: DrugSuggestion(
                    id: "supplement-\(id)",
                    displayName: row["name"] ?? "",
                    genericName: nil,
                    rxcui: nil,
                    kind: .supplement
                )
            )
        }
    }
}
