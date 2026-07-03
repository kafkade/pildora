import Foundation
import XCTest
@testable import PildoraDrugIndex

/// Verifies that a checked-in JSON seed round-trips into a schema-identical,
/// searchable `DrugIndex` — the mechanism behind the app's bundled core tier.
final class SeedIndexBuilderTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-index-\(UUID().uuidString).db")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    private static let seedJSON = """
    {
      "schema_version": "1.0",
      "drugs": [
        {
          "preferred_name": "Metformin",
          "generic_name": "metformin",
          "rxcui": "6809",
          "brand_names": ["Glucophage"]
        },
        {
          "preferred_name": "Lisinopril",
          "generic_name": "lisinopril",
          "rxcui": "29046",
          "brand_names": ["Zestril", "Prinivil"]
        }
      ],
      "supplements": [
        { "name": "Vitamin D3", "ingredients": ["cholecalciferol"] }
      ]
    }
    """

    func testDecodeSeed() throws {
        let seed = try SeedIndexBuilder.decodeSeed(from: Data(Self.seedJSON.utf8))
        XCTAssertEqual(seed.schemaVersion, "1.0")
        XCTAssertEqual(seed.drugs.count, 2)
        XCTAssertEqual(seed.supplements.count, 1)
        XCTAssertEqual(seed.drugs[0].preferredName, "Metformin")
        XCTAssertEqual(seed.drugs[1].brandNames, ["Zestril", "Prinivil"])
        XCTAssertEqual(seed.supplements[0].ingredients, ["cholecalciferol"])
    }

    func testBuildFromSeedProducesSearchableIndex() throws {
        let seed = try SeedIndexBuilder.decodeSeed(from: Data(Self.seedJSON.utf8))
        try SeedIndexBuilder.build(seed: seed, to: url.path)

        let index = try DrugIndex(path: url.path, readonly: true)
        XCTAssertEqual(try index.schemaVersion(), DrugIndexBuilder.schemaVersion)

        let met = try index.search("met", limit: 10)
        XCTAssertTrue(met.contains { $0.displayName == "Metformin" })

        let brand = try index.search("gluco", limit: 10)
        XCTAssertTrue(brand.contains { $0.displayName == "Metformin" })

        let supp = try index.search("vitamin d", limit: 10)
        XCTAssertTrue(supp.contains { $0.displayName == "Vitamin D3" })
    }

    func testBuildFromSeedFileURL() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("seed-\(UUID().uuidString).json")
        try Data(Self.seedJSON.utf8).write(to: seedURL)
        defer { try? FileManager.default.removeItem(at: seedURL) }

        try SeedIndexBuilder.build(fromSeedAt: seedURL, to: url.path)
        let index = try DrugIndex(path: url.path, readonly: true)
        XCTAssertFalse(try index.search("lisi", limit: 10).isEmpty)
    }

    func testRebuildOverwritesCleanly() throws {
        // Build once with the full seed, then rebuild with a reduced seed at the
        // same path — the old rows must not linger.
        let seed = try SeedIndexBuilder.decodeSeed(from: Data(Self.seedJSON.utf8))
        try SeedIndexBuilder.build(seed: seed, to: url.path)
        XCTAssertFalse(try DrugIndex(path: url.path, readonly: true).search("lisi", limit: 10).isEmpty)

        let reduced = DrugIndexSeed(
            drugs: [.init(preferredName: "Metformin", genericName: "metformin", rxcui: "6809")],
            supplements: []
        )
        try SeedIndexBuilder.build(seed: reduced, to: url.path)
        let index = try DrugIndex(path: url.path, readonly: true)
        XCTAssertTrue(try index.search("lisi", limit: 10).isEmpty, "stale rows survived a rebuild")
        XCTAssertFalse(try index.search("met", limit: 10).isEmpty)
    }
}
