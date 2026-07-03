import Foundation
import XCTest

@testable import PildoraDrugIndexLoader

final class IndexManifestTests: XCTestCase {

    func testDecodeSnakeCase() throws {
        let json = """
        {
          "schema_version": "1.0",
          "index_version": "2026.07.02",
          "generated_at": "2026-07-02T00:00:00Z",
          "tiers": {
            "core": {
              "filename": "pildora_drugs_core.sqlite.gz",
              "sha256": "aa",
              "size_bytes": 10,
              "uncompressed_sha256": "bb",
              "uncompressed_size_bytes": 20
            },
            "full": {
              "filename": "pildora_drugs_full.sqlite.gz",
              "sha256": "cc",
              "size_bytes": 30,
              "uncompressed_sha256": "dd",
              "uncompressed_size_bytes": 40
            }
          }
        }
        """
        let manifest = try IndexManifest.decode(from: Data(json.utf8))
        XCTAssertEqual(manifest.schemaVersion, "1.0")
        XCTAssertEqual(manifest.indexVersion, "2026.07.02")
        XCTAssertEqual(manifest.generatedAt, "2026-07-02T00:00:00Z")
        XCTAssertEqual(manifest.tiers.full.filename, "pildora_drugs_full.sqlite.gz")
        XCTAssertEqual(manifest.tiers.full.sha256, "cc")
        XCTAssertEqual(manifest.tiers.full.sizeBytes, 30)
        XCTAssertEqual(manifest.tiers.full.uncompressedSha256, "dd")
        XCTAssertEqual(manifest.tiers.full.uncompressedSizeBytes, 40)
        XCTAssertEqual(manifest.tiers.core.sizeBytes, 10)
    }

    func testDecodeFixtureManifest() throws {
        let fixture = try IndexFixture.make()
        let manifest = try IndexManifest.decode(from: fixture.manifestData())
        XCTAssertEqual(manifest.schemaVersion, fixture.schemaVersion)
        XCTAssertEqual(manifest.indexVersion, fixture.indexVersion)
        XCTAssertEqual(manifest.tiers.full.sizeBytes, fixture.fullGzData.count)
        XCTAssertEqual(manifest.tiers.full.uncompressedSizeBytes, fixture.fullDBData.count)
    }

    func testDecodeRejectsMalformed() {
        XCTAssertThrowsError(try IndexManifest.decode(from: Data("{ not json".utf8)))
    }
}
