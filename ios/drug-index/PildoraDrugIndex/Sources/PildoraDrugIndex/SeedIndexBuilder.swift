import Foundation

// MARK: - DrugIndexSeed

/// A JSON-serializable seed describing the drugs + supplements that make up a
/// drug index. This is the checked-in source for the **bundled core index**: a
/// small, curated, schema-identical subset of the full ETL corpus.
///
/// It is public reference data (drug/supplement names) — never user health data.
public struct DrugIndexSeed: Codable, Equatable, Sendable {

    public struct Drug: Codable, Equatable, Sendable {
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

    public struct Supplement: Codable, Equatable, Sendable {
        public let name: String
        public let ingredients: [String]

        public init(name: String, ingredients: [String] = []) {
            self.name = name
            self.ingredients = ingredients
        }
    }

    /// Schema version the seed targets. Optional; defaults to the current
    /// builder schema when decoding older seeds.
    public let schemaVersion: String?
    public let drugs: [Drug]
    public let supplements: [Supplement]

    public init(schemaVersion: String? = nil, drugs: [Drug], supplements: [Supplement]) {
        self.schemaVersion = schemaVersion
        self.drugs = drugs
        self.supplements = supplements
    }
}

// MARK: - SeedIndexBuilder

/// Builds a schema-identical `DrugIndex` database from a checked-in
/// ``DrugIndexSeed`` JSON file.
///
/// Used both by the app (to generate the bundled core index) and by a small
/// build-time generator tool, so the exact same code path is exercised in unit
/// tests and in production.
public enum SeedIndexBuilder {

    /// Decode a seed from raw JSON bytes (snake_case keys).
    public static func decodeSeed(from data: Data) throws -> DrugIndexSeed {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DrugIndexSeed.self, from: data)
    }

    /// Decode a seed from a JSON file on disk.
    public static func loadSeed(from url: URL) throws -> DrugIndexSeed {
        try decodeSeed(from: Data(contentsOf: url))
    }

    /// Build (or overwrite) a drug index at `dbPath` from an in-memory seed.
    public static func build(seed: DrugIndexSeed, to dbPath: String) throws {
        try DrugIndexBuilder.build(
            at: dbPath,
            drugs: seed.drugs.map {
                .init(
                    preferredName: $0.preferredName,
                    genericName: $0.genericName,
                    rxcui: $0.rxcui,
                    brandNames: $0.brandNames
                )
            },
            supplements: seed.supplements.map {
                .init(name: $0.name, ingredients: $0.ingredients)
            }
        )
    }

    /// Build a drug index at `dbPath` from a seed JSON file at `seedURL`.
    public static func build(fromSeedAt seedURL: URL, to dbPath: String) throws {
        try build(seed: loadSeed(from: seedURL), to: dbPath)
    }
}
