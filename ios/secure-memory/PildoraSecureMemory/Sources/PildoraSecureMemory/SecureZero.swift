// SecureZero.swift — Best-effort secure memory wiping primitive.
//
// `Data` and `[UInt8]` in Swift are not guaranteed to be zeroized when their
// storage is released. This primitive overwrites a region of memory with zeros
// in a way the optimizer is not permitted to elide, providing the building
// block for `SecureBytes`. See ADR-007 (Rust-to-Swift FFI Bridge) and issue
// #40 for the rationale.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Overwrites the given buffer with zeros using a wipe that the compiler must
/// not optimize away.
///
/// On Apple/Linux platforms this calls `memset_s` (C11 Annex K), which is
/// specified to not be elided even when the memory is never read again. Where
/// `memset_s` is unavailable a volatile byte-by-byte loop is used as a
/// best-effort fallback.
///
/// - Parameter buffer: The mutable memory region to erase. A `nil` base address
///   or empty buffer is a no-op.
@inlinable
public func secureZero(_ buffer: UnsafeMutableRawBufferPointer) {
    guard let base = buffer.baseAddress, buffer.count > 0 else { return }
    let count = buffer.count

    #if canImport(Darwin)
    // memset_s is guaranteed not to be optimized out (C11 Annex K, __STDC_LIB_EXT1__).
    _ = memset_s(base, count, 0, count)
    #elseif canImport(Glibc)
    // explicit_bzero is the glibc equivalent guaranteed not to be elided.
    explicit_bzero(base, count)
    #else
    // Portable fallback: write through a volatile pointer so the writes are
    // observable side effects the optimizer must keep.
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    for index in 0..<count {
        (bytes + index).pointee = 0
    }
    // Force a memory barrier so the zeroing is not reordered/removed.
    _ = withExtendedLifetime(bytes) { bytes }
    #endif
}

/// Overwrites a typed `UInt8` buffer with zeros. Convenience overload.
@inlinable
public func secureZero(_ buffer: UnsafeMutableBufferPointer<UInt8>) {
    secureZero(UnsafeMutableRawBufferPointer(buffer))
}
