import Foundation
import PildoraDrugIndex

/// Provides the on-device drug autocomplete index for the running app.
///
/// The production index ships from the Python ETL (openFDA + RxNorm). Until that
/// bundled artifact is wired into the app resources, this seed builds a small,
/// schema-identical index on first launch via `DrugIndexBuilder` so the
/// autocomplete feature is fully exercisable. `DrugIndex` reads either
/// interchangeably because the schema matches byte-for-byte.
///
/// This is public reference data — it is stored in plaintext by design and is
/// never mixed with the encrypted vault database. Autocomplete queries run
/// entirely against this local file and never touch a server (zero-knowledge).
enum DrugSeed {

    /// Open the local drug index, building the seed on first launch (or when the
    /// on-disk schema version is stale).
    static func openOrBuildIndex() throws -> DrugIndex {
        let url = try indexURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try build(at: url.path)
        } else if try isSchemaStale(at: url.path) {
            try build(at: url.path)
        }
        return try DrugIndex(path: url.path, readonly: true)
    }

    private static func isSchemaStale(at path: String) throws -> Bool {
        let index = try DrugIndex(path: path, readonly: true)
        return try index.schemaVersion() != DrugIndexBuilder.schemaVersion
    }

    private static func indexURL() throws -> URL {
        let dir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("PildoraDrugIndex", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("drug-index.db", isDirectory: false)
    }

    private static func build(at path: String) throws {
        try DrugIndexBuilder.build(at: path, drugs: seedDrugs, supplements: seedSupplements)
    }

    // MARK: Curated seed (a small, common subset — not the full ETL corpus)

    private static let seedDrugs: [DrugIndexBuilder.DrugEntry] = [
        .init(preferredName: "Lisinopril", genericName: "lisinopril", rxcui: "29046", brandNames: ["Zestril", "Prinivil"]),
        .init(preferredName: "Atorvastatin", genericName: "atorvastatin", rxcui: "83367", brandNames: ["Lipitor"]),
        .init(preferredName: "Metformin", genericName: "metformin", rxcui: "6809", brandNames: ["Glucophage"]),
        .init(preferredName: "Amlodipine", genericName: "amlodipine", rxcui: "17767", brandNames: ["Norvasc"]),
        .init(preferredName: "Omeprazole", genericName: "omeprazole", rxcui: "7646", brandNames: ["Prilosec"]),
        .init(preferredName: "Levothyroxine", genericName: "levothyroxine", rxcui: "10582", brandNames: ["Synthroid"]),
        .init(preferredName: "Sertraline", genericName: "sertraline", rxcui: "36437", brandNames: ["Zoloft"]),
        .init(preferredName: "Ibuprofen", genericName: "ibuprofen", rxcui: "5640", brandNames: ["Advil", "Motrin"]),
        .init(preferredName: "Amoxicillin", genericName: "amoxicillin", rxcui: "723", brandNames: ["Amoxil"]),
        .init(preferredName: "Metoprolol", genericName: "metoprolol", rxcui: "6918", brandNames: ["Lopressor", "Toprol"]),
        .init(preferredName: "Gabapentin", genericName: "gabapentin", rxcui: "25480", brandNames: ["Neurontin"]),
        .init(preferredName: "Losartan", genericName: "losartan", rxcui: "52175", brandNames: ["Cozaar"]),
        .init(preferredName: "Albuterol", genericName: "albuterol", rxcui: "435", brandNames: ["Ventolin", "ProAir"]),
        .init(preferredName: "Acetaminophen", genericName: "acetaminophen", rxcui: "161", brandNames: ["Tylenol"]),
        .init(preferredName: "Simvastatin", genericName: "simvastatin", rxcui: "36567", brandNames: ["Zocor"]),
    ]

    private static let seedSupplements: [DrugIndexBuilder.SupplementEntry] = [
        .init(name: "Vitamin D3", ingredients: ["cholecalciferol"]),
        .init(name: "Magnesium Glycinate", ingredients: ["magnesium", "glycine"]),
        .init(name: "Fish Oil", ingredients: ["omega-3", "epa", "dha"]),
        .init(name: "Vitamin B12", ingredients: ["cyanocobalamin"]),
        .init(name: "Iron", ingredients: ["ferrous sulfate"]),
        .init(name: "Vitamin C", ingredients: ["ascorbic acid"]),
        .init(name: "Zinc", ingredients: ["zinc gluconate"]),
        .init(name: "Probiotic", ingredients: ["lactobacillus", "bifidobacterium"]),
    ]
}
