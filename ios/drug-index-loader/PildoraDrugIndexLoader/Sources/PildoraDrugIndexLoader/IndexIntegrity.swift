import CryptoKit
import Foundation

// MARK: - IndexIntegrity

/// SHA-256 helpers for verifying downloaded index artifacts against the
/// manifest. File hashing is streamed so a 150 MB index never has to be fully
/// resident in memory just to hash it.
enum IndexIntegrity {

    /// Hex-encoded SHA-256 of an in-memory buffer.
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    /// Hex-encoded SHA-256 of a file, read in bounded chunks.
    static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()  // 1 MiB
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }

    /// Throw if `actual` differs from `expected`.
    static func verify(
        _ kind: DrugIndexLoaderError.IntegrityKind,
        expected: String,
        actual: String
    ) throws {
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw DrugIndexLoaderError.integrityMismatch(
                kind: kind, expected: expected, actual: actual
            )
        }
    }
}

extension Sequence where Element == UInt8 {
    /// Lowercase hex encoding of a byte sequence (e.g. a digest).
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
