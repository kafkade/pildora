import Foundation
import GRDB
import XCTest
@testable import PildoraDrugIndex

/// Exercises the drug index reader against a small, schema-identical fixture
/// built with `DrugIndexBuilder`, plus the FTS query sanitizer and a latency
/// budget for autocomplete.
final class DrugIndexTests: XCTestCase {
    private var url: URL!
    private var index: DrugIndex!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drug-index-\(UUID().uuidString).db")
        try DrugIndexBuilder.build(
            at: url.path,
            drugs: Self.sampleDrugs,
            supplements: Self.sampleSupplements
        )
        index = try DrugIndex(path: url.path)
    }

    override func tearDownWithError() throws {
        index = nil
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    // MARK: Prefix matching

    func testPrefixMatchesGenericName() throws {
        let results = try index.search("met")
        XCTAssertTrue(
            results.contains { $0.displayName == "Metformin" },
            "expected 'met' to prefix-match Metformin, got \(results.map(\.displayName))"
        )
    }

    func testMatchesBrandNameAndResolvesToConcept() throws {
        // "Glucophage" is a brand alias of the Metformin concept.
        let results = try index.search("glucoph")
        let hit = try XCTUnwrap(results.first { $0.displayName == "Metformin" })
        XCTAssertEqual(hit.kind, .drug)
        XCTAssertEqual(hit.rxcui, "6809")
        XCTAssertEqual(hit.genericName, "metformin")
    }

    func testMatchesSupplement() throws {
        let results = try index.search("vitamin d")
        let hit = try XCTUnwrap(results.first { $0.kind == .supplement })
        XCTAssertTrue(hit.displayName.localizedCaseInsensitiveContains("vitamin d"))
        XCTAssertNil(hit.rxcui)
    }

    func testDrugAndSupplementResultsAreMerged() throws {
        // "vitamin" hits the supplement; "b12" also a supplement. Ensure both
        // drug and supplement paths are queried and merged without error.
        let results = try index.search("vitamin")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { !$0.displayName.isEmpty })
    }

    func testLimitIsRespected() throws {
        let results = try index.search("a", limit: 2)
        XCTAssertLessThanOrEqual(results.count, 2)
    }

    // MARK: Empty / malformed input

    func testBlankQueryReturnsEmpty() throws {
        XCTAssertTrue(try index.search("").isEmpty)
        XCTAssertTrue(try index.search("   ").isEmpty)
        XCTAssertTrue(try index.search("!!!").isEmpty)
    }

    func testMalformedFTSInputDoesNotThrow() throws {
        // Characters that are FTS5 operators must be sanitized, not injected.
        XCTAssertNoThrow(try index.search("\"metformin"))
        XCTAssertNoThrow(try index.search("met*("))
        XCTAssertNoThrow(try index.search("a OR b NEAR c"))
    }

    func testZeroLimitReturnsEmpty() throws {
        XCTAssertTrue(try index.search("met", limit: 0).isEmpty)
    }

    // MARK: Metadata

    func testSchemaVersionMatchesBuilder() throws {
        XCTAssertEqual(try index.schemaVersion(), DrugIndexBuilder.schemaVersion)
    }

    // MARK: Latency budget

    func testAutocompleteLatencyUnder50ms() throws {
        // Acceptance criterion: < 50 ms search latency against the local index.
        let queries = ["m", "me", "met", "atorv", "lis", "vit", "glucoph"]
        for q in queries {
            let start = DispatchTime.now()
            _ = try index.search(q)
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            XCTAssertLessThan(elapsedMs, 50, "query \"\(q)\" took \(elapsedMs) ms")
        }
    }

    // MARK: Fixtures

    private static let sampleDrugs: [DrugIndexBuilder.DrugEntry] = [
        .init(preferredName: "Metformin", genericName: "metformin", rxcui: "6809",
              brandNames: ["Glucophage", "Fortamet"]),
        .init(preferredName: "Atorvastatin", genericName: "atorvastatin", rxcui: "83367",
              brandNames: ["Lipitor"]),
        .init(preferredName: "Lisinopril", genericName: "lisinopril", rxcui: "29046",
              brandNames: ["Prinivil", "Zestril"]),
        .init(preferredName: "Levothyroxine", genericName: "levothyroxine sodium", rxcui: "10582",
              brandNames: ["Synthroid"]),
        .init(preferredName: "Amoxicillin", genericName: "amoxicillin", rxcui: "723",
              brandNames: ["Amoxil"]),
    ]

    private static let sampleSupplements: [DrugIndexBuilder.SupplementEntry] = [
        .init(name: "Vitamin D3 2000 IU", ingredients: ["cholecalciferol"]),
        .init(name: "Vitamin B12 Sublingual", ingredients: ["cyanocobalamin"]),
        .init(name: "Omega-3 Fish Oil", ingredients: ["epa", "dha"]),
    ]
}

/// Unit tests for the FTS5 query sanitizer in isolation.
final class FTSQueryTests: XCTestCase {
    func testTokenizesAndAddsPrefixWildcard() {
        XCTAssertEqual(FTSQuery.prefixMatch(for: "met"), "\"met\"*")
    }

    func testMultipleTokensAreAnded() {
        XCTAssertEqual(FTSQuery.prefixMatch(for: "vitamin d"), "\"vitamin\"* \"d\"*")
    }

    func testStripsPunctuationAndOperators() {
        XCTAssertEqual(FTSQuery.prefixMatch(for: "met* ("), "\"met\"*")
        XCTAssertEqual(FTSQuery.prefixMatch(for: "omega-3"), "\"omega\"* \"3\"*")
    }

    func testEmptyOrPunctuationOnlyReturnsNil() {
        XCTAssertNil(FTSQuery.prefixMatch(for: ""))
        XCTAssertNil(FTSQuery.prefixMatch(for: "   "))
        XCTAssertNil(FTSQuery.prefixMatch(for: "!@#$"))
    }

    func testEmbeddedQuotesAreEscaped() {
        // A stray double quote must be doubled, never left to open a string.
        XCTAssertEqual(FTSQuery.prefixMatch(for: "a\"b"), "\"a\"* \"b\"*")
    }
}
