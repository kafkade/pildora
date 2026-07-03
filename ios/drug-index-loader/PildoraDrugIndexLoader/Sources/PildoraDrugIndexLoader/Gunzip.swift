import Czlib
import Foundation

// MARK: - Gunzip

/// Minimal gzip decompressor built on the system zlib.
///
/// The downloaded full index ships as a gzip (`.gz`) file. Apple's `Compression`
/// framework only handles the raw DEFLATE stream (not the gzip container), so we
/// drive zlib's `inflate` with automatic gzip/zlib header detection — which also
/// validates the gzip CRC-32 and length trailer for us.
enum Gunzip {

    /// Hard cap on the decompressed size to bound memory for a hostile/corrupt
    /// input. The full index target is `< 150 MB`; 512 MB leaves ample headroom.
    static let maxOutputBytes = 512 * 1024 * 1024

    /// Decompress gzip `input` into memory.
    ///
    /// - Throws: ``DrugIndexLoaderError/decompressionFailed(_:)`` on corrupt or
    ///   truncated data, or if the output would exceed ``maxOutputBytes``.
    static func decompress(_ input: Data) throws -> Data {
        guard !input.isEmpty else {
            throw DrugIndexLoaderError.decompressionFailed("empty input")
        }

        var stream = z_stream()
        // windowBits 15 + 32 → max window, auto-detect gzip *or* zlib headers.
        let initStatus = inflateInit2_(
            &stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw DrugIndexLoaderError.decompressionFailed("inflateInit2 failed (\(initStatus))")
        }
        defer { inflateEnd(&stream) }

        let chunkSize = 256 * 1024
        var output = Data()
        var outBuffer = [UInt8](repeating: 0, count: chunkSize)

        var status: Int32 = Z_OK
        do {
            try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let base = raw.bindMemory(to: UInt8.self).baseAddress!
                stream.next_in = UnsafeMutablePointer(mutating: base)
                stream.avail_in = uInt(input.count)

                repeat {
                    status = outBuffer.withUnsafeMutableBufferPointer { out -> Int32 in
                        stream.next_out = out.baseAddress
                        stream.avail_out = uInt(chunkSize)
                        return inflate(&stream, Z_NO_FLUSH)
                    }

                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw DrugIndexLoaderError.decompressionFailed("inflate failed (\(status))")
                    }

                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0 {
                        output.append(contentsOf: outBuffer[0..<produced])
                    }
                    guard output.count <= maxOutputBytes else {
                        throw DrugIndexLoaderError.decompressionFailed("output exceeds cap")
                    }
                } while status != Z_STREAM_END
            }
        }

        guard status == Z_STREAM_END else {
            throw DrugIndexLoaderError.decompressionFailed("truncated stream")
        }
        return output
    }

    /// Decompress a gzip file on disk into memory.
    static func decompressFile(at url: URL) throws -> Data {
        try decompress(try Data(contentsOf: url, options: .mappedIfSafe))
    }
}
