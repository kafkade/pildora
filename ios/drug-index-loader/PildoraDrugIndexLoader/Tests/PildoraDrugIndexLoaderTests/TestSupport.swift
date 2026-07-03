import Czlib
import CryptoKit
import Foundation
import PildoraDrugIndex
import XCTest

@testable import PildoraDrugIndexLoader

// MARK: - Gzip (test-only compressor)

/// gzip-compress bytes using zlib (`deflateInit2` with gzip window bits). Only
/// the app *decompresses* in production (the ETL produces the `.gz`); tests need
/// to synthesize gzip fixtures, so the symmetric compressor lives here.
enum TestGzip {
    static func compress(_ input: Data) -> Data {
        var stream = z_stream()
        let status = deflateInit2_(
            &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8,
            Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        )
        precondition(status == Z_OK, "deflateInit2 failed: \(status)")
        defer { deflateEnd(&stream) }

        var output = Data()
        let chunk = 64 * 1024
        var outBuffer = [UInt8](repeating: 0, count: chunk)
        var mutableInput = input
        mutableInput.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            stream.next_in = raw.bindMemory(to: UInt8.self).baseAddress
            stream.avail_in = uInt(input.count)
            var done = false
            repeat {
                let ret = outBuffer.withUnsafeMutableBufferPointer { out -> Int32 in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(chunk)
                    return deflate(&stream, Z_FINISH)
                }
                let produced = chunk - Int(stream.avail_out)
                if produced > 0 { output.append(contentsOf: outBuffer[0..<produced]) }
                done = ret == Z_STREAM_END
            } while !done
        }
        return output
    }
}

// MARK: - Hash helpers

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Fixtures

/// Builds schema-identical core + full index fixtures and a matching manifest,
/// mirroring what the `data/` ETL emits. The full index contains a distinctive
/// drug ("Warfarin") absent from core so tests can prove a tier swap took effect.
struct IndexFixture {
    let coreURL: URL
    let fullDBData: Data
    let fullGzData: Data
    let indexVersion: String
    let schemaVersion: String
    let coreDescriptor: [String: Any]
    let fullDescriptor: [String: Any]

    /// A drug present only in the full index.
    static let fullOnlyName = "Warfarin"
    static let fullOnlyPrefix = "warf"
    /// A drug present in both tiers.
    static let commonName = "Metformin"
    static let commonPrefix = "met"

    static func make(indexVersion: String = "2026.07.02", schemaVersion: String = "1.0") throws -> IndexFixture {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let coreURL = dir.appendingPathComponent("core.db")
        try DrugIndexBuilder.build(
            at: coreURL.path,
            drugs: [
                .init(preferredName: commonName, genericName: "metformin", rxcui: "6809",
                      brandNames: ["Glucophage"]),
                .init(preferredName: "Lisinopril", genericName: "lisinopril", rxcui: "29046",
                      brandNames: ["Zestril"]),
            ],
            supplements: [.init(name: "Vitamin D3", ingredients: ["cholecalciferol"])]
        )

        let fullURL = dir.appendingPathComponent("full.db")
        try DrugIndexBuilder.build(
            at: fullURL.path,
            drugs: [
                .init(preferredName: commonName, genericName: "metformin", rxcui: "6809",
                      brandNames: ["Glucophage"]),
                .init(preferredName: "Lisinopril", genericName: "lisinopril", rxcui: "29046",
                      brandNames: ["Zestril"]),
                .init(preferredName: fullOnlyName, genericName: "warfarin", rxcui: "11289",
                      brandNames: ["Coumadin"]),
                .init(preferredName: "Atorvastatin", genericName: "atorvastatin", rxcui: "83367",
                      brandNames: ["Lipitor"]),
            ],
            supplements: [
                .init(name: "Vitamin D3", ingredients: ["cholecalciferol"]),
                .init(name: "Fish Oil", ingredients: ["omega-3"]),
            ]
        )

        let fullDBData = try Data(contentsOf: fullURL)
        let fullGzData = TestGzip.compress(fullDBData)

        // Core descriptor (informational in the manifest).
        let coreDBData = try Data(contentsOf: coreURL)
        let coreGzData = TestGzip.compress(coreDBData)

        return IndexFixture(
            coreURL: coreURL,
            fullDBData: fullDBData,
            fullGzData: fullGzData,
            indexVersion: indexVersion,
            schemaVersion: schemaVersion,
            coreDescriptor: descriptor(gz: coreGzData, db: coreDBData, filename: "pildora_drugs_core.sqlite.gz"),
            fullDescriptor: descriptor(gz: fullGzData, db: fullDBData, filename: "pildora_drugs_full.sqlite.gz")
        )
    }

    static func descriptor(gz: Data, db: Data, filename: String) -> [String: Any] {
        [
            "filename": filename,
            "sha256": sha256Hex(gz),
            "size_bytes": gz.count,
            "uncompressed_sha256": sha256Hex(db),
            "uncompressed_size_bytes": db.count,
        ]
    }

    /// Build manifest JSON, optionally overriding top-level or full-tier fields
    /// to exercise failure paths (bad schema, wrong hash/size, etc.).
    func manifestData(
        schemaVersion: String? = nil,
        indexVersion: String? = nil,
        fullOverrides: [String: Any] = [:]
    ) -> Data {
        var full = fullDescriptor
        for (k, v) in fullOverrides { full[k] = v }
        let manifest: [String: Any] = [
            "schema_version": schemaVersion ?? self.schemaVersion,
            "index_version": indexVersion ?? self.indexVersion,
            "generated_at": "2026-07-02T00:00:00Z",
            "tiers": ["core": coreDescriptor, "full": full],
        ]
        return try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }

    /// Write the full `.gz` to a fresh temp file (the downloader deletes it).
    func makeArtifactFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-\(UUID().uuidString).gz")
        try fullGzData.write(to: url)
        return url
    }
}

// MARK: - MockDownloadClient

/// Deterministic `IndexDownloadClient` for tests: serves a canned manifest and
/// artifact, and can simulate transient download failures + progress.
final class MockDownloadClient: IndexDownloadClient, @unchecked Sendable {
    var manifestData: Data?
    var fetchError: Error?
    var artifactProvider: (@Sendable () throws -> URL)?
    var failDownloadsBeforeSuccess = 0
    var progressValues: [Double] = [0.25, 0.5, 1.0]

    private let lock = NSLock()
    private var _downloadAttempts = 0
    private var _manifestFetches = 0

    var downloadAttempts: Int { withLock { _downloadAttempts } }
    var manifestFetches: Int { withLock { _manifestFetches } }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }; return body()
    }

    func fetchData(from url: URL) async throws -> Data {
        if let fetchError { throw fetchError }
        withLock { _manifestFetches += 1 }
        guard url.lastPathComponent == "manifest.json", let manifestData else {
            throw DrugIndexLoaderError.downloadFailed("unexpected fetch: \(url)")
        }
        return manifestData
    }

    func downloadToFile(
        from url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let attempt = withLock { () -> Int in _downloadAttempts += 1; return _downloadAttempts }
        for p in progressValues { onProgress(p) }
        if attempt <= failDownloadsBeforeSuccess {
            throw DrugIndexLoaderError.downloadFailed("simulated transient failure #\(attempt)")
        }
        guard let artifactProvider else {
            throw DrugIndexLoaderError.downloadFailed("no artifact provider")
        }
        return try artifactProvider()
    }
}

/// Thread-safe recorder for progress callbacks fired off the test's actor.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    func update(_ p: Double) { lock.lock(); value = Swift.max(value, p); lock.unlock() }
    var current: Double { lock.lock(); defer { lock.unlock() }; return value }
}

let testBaseURL = URL(string: "https://cdn.test.invalid/drug-index/")!
