import Foundation
import PildoraDrugIndex
import XCTest

@testable import PildoraDrugIndexLoader

final class FullIndexDownloaderTests: XCTestCase {

    private var storeDir: URL!

    override func setUpWithError() throws {
        storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dl-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDir)
    }

    private func makeStore() throws -> InstalledIndexStore {
        try InstalledIndexStore(directory: storeDir)
    }

    private func makeDownloader(
        client: MockDownloadClient,
        store: InstalledIndexStore
    ) -> FullIndexDownloader {
        FullIndexDownloader(
            baseURL: testBaseURL,
            client: client,
            store: store,
            maxAttempts: 3,
            retryBackoff: .zero
        )
    }

    func testSuccessfulDownloadInstallsFullIndex() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }

        let progress = ProgressBox()
        let outcome = try await makeDownloader(client: client, store: store)
            .updateIfAvailable { progress.update($0) }

        XCTAssertEqual(outcome, .installed(version: fixture.indexVersion))
        XCTAssertEqual(progress.current, 1.0, accuracy: 0.0001)
        XCTAssertTrue(store.hasInstalledFullIndex())
        XCTAssertEqual(store.installedVersion(), fixture.indexVersion)

        // The installed index is a real, readable index containing the full-only drug.
        let index = try DrugIndex(path: store.installedFullIndexURL.path, readonly: true)
        let hits = try index.search(IndexFixture.fullOnlyPrefix, limit: 10)
        XCTAssertTrue(hits.contains { $0.displayName == IndexFixture.fullOnlyName })
    }

    func testUpToDateWhenVersionMatchesInstalled() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        // Pre-install the same version.
        let temp = storeDir.appendingPathComponent("pre.db")
        try fixture.fullDBData.write(to: temp)
        try store.install(databaseAt: temp, version: fixture.indexVersion)

        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }

        let outcome = try await makeDownloader(client: client, store: store).updateIfAvailable()

        XCTAssertEqual(outcome, .upToDate(version: fixture.indexVersion))
        XCTAssertEqual(client.downloadAttempts, 0, "should not download when already current")
    }

    func testNewerVersionDownloadsOverOld() async throws {
        let fixture = try IndexFixture.make(indexVersion: "2026.09.09")
        let store = try makeStore()
        let temp = storeDir.appendingPathComponent("old.db")
        try Data("stale".utf8).write(to: temp)
        try store.install(databaseAt: temp, version: "2026.01.01")

        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }

        let outcome = try await makeDownloader(client: client, store: store).updateIfAvailable()
        XCTAssertEqual(outcome, .installed(version: "2026.09.09"))
        XCTAssertEqual(store.installedVersion(), "2026.09.09")
    }

    func testUnsupportedSchemaThrowsAndInstallsNothing() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData(schemaVersion: "9.9")
        client.artifactProvider = { try fixture.makeArtifactFile() }

        await assertThrows(makeDownloader(client: client, store: store)) { error in
            guard case DrugIndexLoaderError.unsupportedSchema(let found, _) = error else {
                return XCTFail("expected unsupportedSchema, got \(error)")
            }
            XCTAssertEqual(found, "9.9")
        }
        XCTAssertFalse(store.hasInstalledFullIndex())
    }

    func testCompressedHashMismatchFallsBack() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData(
            fullOverrides: ["sha256": String(repeating: "0", count: 64)]
        )
        client.artifactProvider = { try fixture.makeArtifactFile() }

        await assertThrows(makeDownloader(client: client, store: store)) { error in
            guard case DrugIndexLoaderError.integrityMismatch(let kind, _, _) = error else {
                return XCTFail("expected integrityMismatch, got \(error)")
            }
            XCTAssertEqual(kind, .compressed)
        }
        XCTAssertFalse(store.hasInstalledFullIndex())
    }

    func testCompressedSizeMismatchFallsBack() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData(fullOverrides: ["size_bytes": 999_999])
        client.artifactProvider = { try fixture.makeArtifactFile() }

        await assertThrows(makeDownloader(client: client, store: store)) { error in
            guard case DrugIndexLoaderError.sizeMismatch = error else {
                return XCTFail("expected sizeMismatch, got \(error)")
            }
        }
        XCTAssertFalse(store.hasInstalledFullIndex())
    }

    func testDecompressedHashMismatchFallsBack() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData(
            fullOverrides: ["uncompressed_sha256": String(repeating: "1", count: 64)]
        )
        client.artifactProvider = { try fixture.makeArtifactFile() }

        await assertThrows(makeDownloader(client: client, store: store)) { error in
            guard case DrugIndexLoaderError.integrityMismatch(let kind, _, _) = error else {
                return XCTFail("expected integrityMismatch, got \(error)")
            }
            XCTAssertEqual(kind, .decompressed)
        }
        XCTAssertFalse(store.hasInstalledFullIndex())
    }

    func testCorruptGzipFallsBack() async throws {
        // Craft an artifact whose compressed hash/size match the manifest but is
        // not a valid gzip stream, so gunzip fails.
        let store = try makeStore()
        let garbage = Data([0x1f, 0x8b, 0x08, 0x00] + Array(repeating: UInt8(0x7f), count: 64))
        let manifest: [String: Any] = [
            "schema_version": "1.0",
            "index_version": "2026.07.02",
            "generated_at": "2026-07-02T00:00:00Z",
            "tiers": [
                "core": [
                    "filename": "c.gz", "sha256": "aa", "size_bytes": 1,
                    "uncompressed_sha256": "bb", "uncompressed_size_bytes": 1,
                ],
                "full": [
                    "filename": "pildora_drugs_full.sqlite.gz",
                    "sha256": sha256Hex(garbage),
                    "size_bytes": garbage.count,
                    "uncompressed_sha256": "cc",
                    "uncompressed_size_bytes": 999,
                ],
            ],
        ]
        let client = MockDownloadClient()
        client.manifestData = try JSONSerialization.data(withJSONObject: manifest)
        client.artifactProvider = {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bad-\(UUID().uuidString).gz")
            try garbage.write(to: url)
            return url
        }

        await assertThrows(makeDownloader(client: client, store: store)) { error in
            guard case DrugIndexLoaderError.decompressionFailed = error else {
                return XCTFail("expected decompressionFailed, got \(error)")
            }
        }
        XCTAssertFalse(store.hasInstalledFullIndex())
    }

    func testTransientDownloadFailuresAreRetried() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }
        client.failDownloadsBeforeSuccess = 2  // fail twice, succeed on the 3rd

        let outcome = try await makeDownloader(client: client, store: store).updateIfAvailable()
        XCTAssertEqual(outcome, .installed(version: fixture.indexVersion))
        XCTAssertEqual(client.downloadAttempts, 3)
        XCTAssertTrue(store.hasInstalledFullIndex())
    }

    func testDownloadFailsAfterExhaustingRetries() async throws {
        let fixture = try IndexFixture.make()
        let store = try makeStore()
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }
        client.failDownloadsBeforeSuccess = 5  // more than maxAttempts

        await assertThrows(makeDownloader(client: client, store: store)) { error in
            guard case DrugIndexLoaderError.downloadFailed = error else {
                return XCTFail("expected downloadFailed, got \(error)")
            }
        }
        XCTAssertEqual(client.downloadAttempts, 3)
        XCTAssertFalse(store.hasInstalledFullIndex())
    }

    // MARK: - Helpers

    private func assertThrows(
        _ downloader: FullIndexDownloader,
        _ check: (Error) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await downloader.updateIfAvailable()
            XCTFail("expected an error to be thrown", file: file, line: line)
        } catch {
            check(error)
        }
    }
}
