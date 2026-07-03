import Foundation

// MARK: - IndexManifest

/// The distribution manifest published by the `data/` ETL alongside the index
/// artifacts (`manifest.json`). It is the contract the tiered loader relies on.
///
/// This is **public, non-sensitive metadata** about plaintext reference data —
/// it never references user health data.
public struct IndexManifest: Decodable, Equatable, Sendable {
    /// Index table schema version (must match what the app can read).
    public let schemaVersion: String
    /// Dataset version; compared against the installed full index to decide
    /// whether a newer index should be downloaded.
    public let indexVersion: String
    /// ISO-8601 build timestamp (informational).
    public let generatedAt: String?
    /// Per-tier artifact descriptors.
    public let tiers: Tiers

    public struct Tiers: Decodable, Equatable, Sendable {
        public let core: ArtifactDescriptor
        public let full: ArtifactDescriptor
    }

    /// Decode a manifest from raw JSON bytes, mapping snake_case → camelCase.
    public static func decode(from data: Data) throws -> IndexManifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(IndexManifest.self, from: data)
    }
}

// MARK: - ArtifactDescriptor

/// Describes one downloadable index artifact (the compressed `.gz`) and the
/// `.sqlite` it decompresses to, with integrity hashes for both forms.
public struct ArtifactDescriptor: Decodable, Equatable, Sendable {
    /// Filename of the compressed artifact, resolved against the base URL.
    public let filename: String
    /// SHA-256 (hex) of the **compressed** `.gz` bytes as downloaded.
    public let sha256: String
    /// Size in bytes of the compressed artifact.
    public let sizeBytes: Int
    /// SHA-256 (hex) of the **decompressed** `.sqlite` bytes.
    public let uncompressedSha256: String
    /// Size in bytes of the decompressed `.sqlite`.
    public let uncompressedSizeBytes: Int
}
