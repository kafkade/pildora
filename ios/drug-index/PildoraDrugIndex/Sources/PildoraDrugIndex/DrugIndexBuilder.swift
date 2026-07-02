import Foundation
import GRDB

// MARK: - DrugIndexBuilder

/// Builds a drug index SQLite file with the **exact same schema** as the Python
/// ETL pipeline (`data/src/pildora_data/index_builder.py`).
///
/// The production index is produced by the ETL from openFDA / RxNorm. This
/// builder exists so tests — and the app's on-device dev/seed index — can create
/// a small, schema-identical index without the full pipeline. Because the schema
/// matches, `DrugIndex` reads either interchangeably.
public enum DrugIndexBuilder {

    /// Schema version stamped into the built index's metadata, mirroring the
    /// ETL's `SCHEMA_VERSION`.
    public static let schemaVersion = "1.0"

    /// One drug concept plus its brand-name aliases.
    public struct DrugEntry: Sendable {
        public let preferredName: String
        public let genericName: String?
        public let rxcui: String?
        public let brandNames: [String]

        public init(
            preferredName: String,
            genericName: String? = nil,
            rxcui: String? = nil,
            brandNames: [String] = []
        ) {
            self.preferredName = preferredName
            self.genericName = genericName
            self.rxcui = rxcui
            self.brandNames = brandNames
        }
    }

    /// One supplement product plus its ingredient list.
    public struct SupplementEntry: Sendable {
        public let name: String
        public let ingredients: [String]

        public init(name: String, ingredients: [String] = []) {
            self.name = name
            self.ingredients = ingredients
        }
    }

    /// Build (or overwrite) an index at `path` from the given entries.
    public static func build(
        at path: String,
        drugs: [DrugEntry],
        supplements: [SupplementEntry]
    ) throws {
        // Start fresh so a rebuild is deterministic.
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }

        let queue = try DatabaseQueue(path: path)
        try queue.write { db in
            try createSchema(db)

            for (offset, drug) in drugs.enumerated() {
                let conceptID = Int64(offset + 1)
                try db.execute(
                    sql: """
                    INSERT INTO drug_concepts (id, preferred_name, generic_name, rxcui, product_type)
                    VALUES (?, ?, ?, ?, 'drug')
                    """,
                    arguments: [conceptID, drug.preferredName, drug.genericName, drug.rxcui]
                )
                if let generic = drug.genericName, !generic.isEmpty {
                    try db.execute(
                        sql: """
                        INSERT OR IGNORE INTO drug_aliases (concept_id, alias, alias_type, source)
                        VALUES (?, ?, 'generic', 'openfda')
                        """,
                        arguments: [conceptID, generic]
                    )
                }
                for brand in drug.brandNames where !brand.isEmpty {
                    try db.execute(
                        sql: """
                        INSERT OR IGNORE INTO drug_aliases (concept_id, alias, alias_type, source)
                        VALUES (?, ?, 'brand', 'openfda')
                        """,
                        arguments: [conceptID, brand]
                    )
                }
                let aliases = drug.brandNames.sorted().joined(separator: " ")
                try db.execute(
                    sql: """
                    INSERT INTO drug_fts (rowid, preferred_name, aliases, generic_name)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [conceptID, drug.preferredName, aliases, drug.genericName ?? ""]
                )
            }

            for (offset, supp) in supplements.enumerated() {
                let suppID = Int64(offset + 1)
                let ingredientsJSON = String(
                    data: try JSONSerialization.data(withJSONObject: supp.ingredients),
                    encoding: .utf8
                ) ?? "[]"
                try db.execute(
                    sql: """
                    INSERT INTO supplements (id, name, ingredients, manufacturer, dosage_form, source)
                    VALUES (?, ?, ?, NULL, NULL, 'dailymed')
                    """,
                    arguments: [suppID, supp.name, ingredientsJSON]
                )
                try db.execute(
                    sql: "INSERT INTO supplement_fts (rowid, name, ingredients_text) VALUES (?, ?, ?)",
                    arguments: [suppID, supp.name, supp.ingredients.joined(separator: " ")]
                )
            }

            try db.execute(
                sql: "INSERT OR REPLACE INTO metadata (key, value) VALUES ('schema_version', ?)",
                arguments: [schemaVersion]
            )
        }
    }

    /// The schema DDL, kept byte-for-byte compatible with the ETL builder.
    private static func createSchema(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS drug_concepts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                preferred_name TEXT NOT NULL,
                generic_name TEXT,
                rxcui TEXT,
                product_type TEXT DEFAULT 'drug'
            );

            CREATE TABLE IF NOT EXISTS drug_aliases (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                concept_id INTEGER NOT NULL REFERENCES drug_concepts(id),
                alias TEXT NOT NULL,
                alias_type TEXT NOT NULL,
                source TEXT NOT NULL,
                UNIQUE(concept_id, alias, alias_type)
            );

            CREATE TABLE IF NOT EXISTS drug_products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                concept_id INTEGER NOT NULL REFERENCES drug_concepts(id),
                ndc TEXT,
                dosage_form TEXT,
                strength TEXT,
                route TEXT,
                manufacturer TEXT,
                source TEXT NOT NULL
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS drug_fts USING fts5(
                preferred_name,
                aliases,
                generic_name,
                content='',
                content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2'
            );

            CREATE TABLE IF NOT EXISTS supplements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                ingredients TEXT,
                manufacturer TEXT,
                dosage_form TEXT,
                source TEXT NOT NULL DEFAULT 'dailymed'
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS supplement_fts USING fts5(
                name,
                ingredients_text,
                content='',
                content_rowid='rowid',
                tokenize='unicode61 remove_diacritics 2'
            );

            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_drug_aliases_concept ON drug_aliases(concept_id);
            CREATE INDEX IF NOT EXISTS idx_drug_products_concept ON drug_products(concept_id);
            CREATE INDEX IF NOT EXISTS idx_drug_concepts_rxcui ON drug_concepts(rxcui);
            CREATE INDEX IF NOT EXISTS idx_drug_products_ndc ON drug_products(ndc);
        """)
    }
}
