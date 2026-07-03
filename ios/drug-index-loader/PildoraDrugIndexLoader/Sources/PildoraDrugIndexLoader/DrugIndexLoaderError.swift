import Foundation

// MARK: - DrugIndexLoaderError

/// Errors raised while resolving, downloading, verifying, or installing the
/// full drug index. Any of these leaves the bundled **core** index in place —
/// autocomplete keeps working offline.
public enum DrugIndexLoaderError: Error, Equatable, Sendable {
    /// The manifest advertised a schema the app cannot read.
    case unsupportedSchema(found: String, expected: String)
    /// A downloaded artifact's hash did not match the manifest.
    case integrityMismatch(kind: IntegrityKind, expected: String, actual: String)
    /// A downloaded artifact's size did not match the manifest.
    case sizeMismatch(expected: Int, actual: Int)
    /// gunzip failed (corrupt or truncated `.gz`).
    case decompressionFailed(String)
    /// The downloaded file was not a valid, readable index.
    case invalidIndex(String)
    /// The download failed after exhausting all retry attempts.
    case downloadFailed(String)
    /// A misconfiguration, e.g. no download endpoint was provided.
    case notConfigured

    public enum IntegrityKind: String, Sendable, Equatable {
        case compressed
        case decompressed
    }
}
