import Foundation

/// Formats 32-byte recovery-key material into the human-readable string shown to
/// the user and printed on the recovery PDF.
///
/// This mirrors the canonical Rust implementation
/// (`pildora_crypto::key_hierarchy::RecoveryKey::to_display_string`): Crockford
/// Base32 (no ambiguous `I`/`L`/`O`/`U`), dash-separated groups of five, with a
/// two-character checksum suffix derived from a hash of the key.
///
/// In the app the recovery string always comes from the crypto FFI so there is a
/// single source of truth. This Swift port exists so tests and SwiftUI previews
/// can render realistic keys without linking the FFI, and so the format itself
/// is unit-testable. A parity test pins the two implementations together at the
/// FFI boundary.
enum RecoveryKeyFormatting {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".utf8)

    /// Encode 32 bytes as the grouped, checksummed recovery string.
    ///
    /// - Parameters:
    ///   - key: The raw key bytes (expected 32).
    ///   - checksum: A closure producing at least two bytes of hash over `key`.
    ///     Injected so the real BLAKE2b hash (via FFI) can be supplied in the
    ///     app while tests use a deterministic stand-in.
    static func displayString(for key: [UInt8], checksum: ([UInt8]) -> [UInt8]) -> String {
        var chars: [UInt8] = []
        chars.reserveCapacity(56)
        var buffer: UInt64 = 0
        var bits = 0

        for byte in key {
            buffer = (buffer << 8) | UInt64(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                let idx = Int((buffer >> UInt64(bits)) & 0x1F)
                chars.append(alphabet[idx])
            }
        }
        if bits > 0 {
            let idx = Int((buffer << UInt64(5 - bits)) & 0x1F)
            chars.append(alphabet[idx])
        }

        let hash = checksum(key)
        let h0 = UInt16(hash.count > 0 ? hash[0] : 0)
        let h1 = UInt16(hash.count > 1 ? hash[1] : 0)
        let checkVal = (h0 << 2) | (h1 >> 6)
        chars.append(alphabet[Int((checkVal >> 5) & 0x1F)])
        chars.append(alphabet[Int(checkVal & 0x1F)])

        let grouped = stride(from: 0, to: chars.count, by: 5).map { start -> String in
            let end = min(start + 5, chars.count)
            return String(decoding: chars[start..<end], as: UTF8.self)
        }
        return grouped.joined(separator: "-")
    }
}
