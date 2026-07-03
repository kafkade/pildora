import Foundation
import PildoraDrugIndex

// MARK: - FullIndexDownloader

/// Orchestrates fetching, verifying, and installing the **full** drug index from
/// a configured base URL, using the manifest as the source of truth.
///
/// Every failure mode is non-fatal: the caller keeps serving autocomplete from
/// the bundled **core** index and can retry later. Nothing here ever transmits
/// user data — it only performs anonymous GETs of public reference-data URLs.
public struct FullIndexDownloader: Sendable {

    /// Base URL that `manifest.json` and the artifact filename resolve against
    /// (e.g. `https://cdn.example.com/drug-index/`).
    public let baseURL: URL
    public let client: IndexDownloadClient
    public let store: InstalledIndexStore
    /// Schema version the app is able to read (defaults to the reader's).
    public let supportedSchemaVersion: String
    /// Outer download attempts (each attempt also resumes internally).
    public let maxAttempts: Int
    /// Base backoff between outer attempts; grows exponentially.
    public let retryBackoff: Duration

    public init(
        baseURL: URL,
        client: IndexDownloadClient,
        store: InstalledIndexStore,
        supportedSchemaVersion: String = DrugIndexBuilder.schemaVersion,
        maxAttempts: Int = 3,
        retryBackoff: Duration = .seconds(2)
    ) {
        self.baseURL = baseURL
        self.client = client
        self.store = store
        self.supportedSchemaVersion = supportedSchemaVersion
        self.maxAttempts = max(1, maxAttempts)
        self.retryBackoff = retryBackoff
    }

    /// Outcome of an update check.
    public enum Outcome: Equatable, Sendable {
        /// The installed full index already matches the manifest version.
        case upToDate(version: String)
        /// A newer full index was downloaded, verified, and installed.
        case installed(version: String)
    }

    /// Fetch the manifest and, if a newer full index is available, download →
    /// verify → install it atomically.
    ///
    /// - Parameter onProgress: fractional download progress in `0...1`.
    /// - Returns: whether an install happened or the index was already current.
    /// - Throws: ``DrugIndexLoaderError`` on any failure (index left unchanged).
    public func updateIfAvailable(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Outcome {
        let manifest = try await fetchManifest()

        guard manifest.schemaVersion == supportedSchemaVersion else {
            throw DrugIndexLoaderError.unsupportedSchema(
                found: manifest.schemaVersion, expected: supportedSchemaVersion
            )
        }

        if store.installedVersion() == manifest.indexVersion {
            return .upToDate(version: manifest.indexVersion)
        }

        let artifact = manifest.tiers.full
        let artifactURL = baseURL.appendingPathComponent(artifact.filename)

        let gzURL = try await downloadWithRetry(artifactURL, onProgress: onProgress)
        defer { try? FileManager.default.removeItem(at: gzURL) }

        try verifyCompressed(gzURL, against: artifact)
        let dbData = try decompressAndVerify(gzURL, against: artifact)
        let dbURL = try writeAndValidate(dbData, schemaVersion: manifest.schemaVersion)
        defer { try? FileManager.default.removeItem(at: dbURL) }

        try store.install(databaseAt: dbURL, version: manifest.indexVersion)
        return .installed(version: manifest.indexVersion)
    }

    // MARK: Steps

    private func fetchManifest() async throws -> IndexManifest {
        let url = baseURL.appendingPathComponent("manifest.json")
        let data: Data
        do {
            data = try await client.fetchData(from: url)
        } catch {
            throw DrugIndexLoaderError.downloadFailed("manifest: \(error)")
        }
        do {
            return try IndexManifest.decode(from: data)
        } catch {
            throw DrugIndexLoaderError.invalidIndex("manifest decode: \(error)")
        }
    }

    private func downloadWithRetry(
        _ url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        var lastError: Error = DrugIndexLoaderError.downloadFailed("not attempted")
        for attempt in 0..<maxAttempts {
            do {
                return try await client.downloadToFile(from: url, onProgress: onProgress)
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delay = retryBackoff * Int(pow(2.0, Double(attempt)))
                    try? await Task.sleep(for: delay)
                }
            }
        }
        throw DrugIndexLoaderError.downloadFailed(String(describing: lastError))
    }

    private func verifyCompressed(_ gzURL: URL, against artifact: ArtifactDescriptor) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: gzURL.path)[.size] as? Int) ?? nil
        if let size, size != artifact.sizeBytes {
            throw DrugIndexLoaderError.sizeMismatch(expected: artifact.sizeBytes, actual: size)
        }
        let actual = try IndexIntegrity.sha256Hex(ofFileAt: gzURL)
        try IndexIntegrity.verify(.compressed, expected: artifact.sha256, actual: actual)
    }

    private func decompressAndVerify(_ gzURL: URL, against artifact: ArtifactDescriptor) throws -> Data {
        let data = try Gunzip.decompressFile(at: gzURL)
        guard data.count == artifact.uncompressedSizeBytes else {
            throw DrugIndexLoaderError.sizeMismatch(
                expected: artifact.uncompressedSizeBytes, actual: data.count
            )
        }
        let actual = IndexIntegrity.sha256Hex(of: data)
        try IndexIntegrity.verify(.decompressed, expected: artifact.uncompressedSha256, actual: actual)
        return data
    }

    private func writeAndValidate(_ dbData: Data, schemaVersion: String) throws -> URL {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pildora-index-\(UUID().uuidString).db")
        try dbData.write(to: dbURL, options: .atomic)

        // Opening it proves the bytes are a real SQLite index with a matching
        // schema before we let it replace the live index.
        do {
            let index = try DrugIndex(path: dbURL.path, readonly: true)
            let onDisk = try index.schemaVersion()
            guard onDisk == schemaVersion else {
                throw DrugIndexLoaderError.invalidIndex(
                    "schema \(onDisk ?? "nil") != manifest \(schemaVersion)"
                )
            }
        } catch let error as DrugIndexLoaderError {
            try? FileManager.default.removeItem(at: dbURL)
            throw error
        } catch {
            try? FileManager.default.removeItem(at: dbURL)
            throw DrugIndexLoaderError.invalidIndex("open failed: \(error)")
        }
        return dbURL
    }
}
