// SecureBytes.swift — Move-only wrapper that zeroizes key material on release.
//
// Issue #40 / ADR-007: UniFFI manages allocation across the Rust -> Swift
// boundary, but Swift `Data` and `[UInt8]` are NOT guaranteed to be zeroized
// when their storage is freed. Sensitive key material (master key, vault key,
// MEK, auth key) that crosses into Swift memory can therefore linger in
// deallocated pages.
//
// `SecureBytes` is the Swift counterpart to the Rust `zeroize::ZeroizeOnDrop`
// types in `crypto/src/keys.rs`. It:
//   * owns a heap-allocated mutable byte buffer,
//   * securely wipes that buffer on `deinit` (see `secureZero`), and
//   * is a move-only (`~Copyable`) type, so the compiler forbids the silent
//     copies that would otherwise scatter key material across memory.
//
// This is defense-in-depth. iOS already provides hardware memory encryption
// (Secure Enclave) and per-app address-space isolation; this wrapper shortens
// the lifetime of plaintext key material within the app's own address space.

#if canImport(Foundation)
import Foundation
#endif

/// A move-only container for sensitive bytes that is securely zeroized when it
/// goes out of scope.
///
/// Because the type is `~Copyable`, values are *moved* rather than copied. To
/// read or mutate the contents, use ``withUnsafeBytes(_:)`` or
/// ``withUnsafeMutableBytes(_:)`` — these provide scoped access without
/// duplicating the underlying storage.
///
/// ```swift
/// // Wrap key material returned from the FFI bridge immediately.
/// var vaultKey = SecureBytes(generateVaultKey())   // [UInt8] -> SecureBytes
/// vaultKey.withUnsafeBytes { raw in
///     // pass `raw` straight back into a crypto call …
/// }
/// // `vaultKey` is wiped from memory when it leaves scope.
/// ```
public struct SecureBytes: ~Copyable {
    /// Heap-allocated, owned storage. Never exposed directly.
    private let buffer: UnsafeMutableBufferPointer<UInt8>

    // MARK: - Creation

    /// Creates a zero-filled buffer of the given length.
    ///
    /// - Parameter count: The number of bytes to allocate. Must be `>= 0`.
    public init(count: Int) {
        precondition(count >= 0, "SecureBytes count must be non-negative")
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        buffer.initialize(repeating: 0)
        self.buffer = buffer
    }

    /// Creates a buffer of `count` bytes and fills it in place.
    ///
    /// The buffer is handed to `body` already zero-initialized so the caller can
    /// write key material directly into the secured storage without first
    /// materializing it in an unmanaged `[UInt8]` or `Data`.
    ///
    /// - Parameters:
    ///   - count: The number of bytes to allocate. Must be `>= 0`.
    ///   - body: A closure that populates the buffer.
    public init(count: Int, initializingWith body: (UnsafeMutableBufferPointer<UInt8>) -> Void) {
        precondition(count >= 0, "SecureBytes count must be non-negative")
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        buffer.initialize(repeating: 0)
        body(buffer)
        self.buffer = buffer
    }

    /// Copies the given bytes into freshly allocated secured storage.
    ///
    /// - Note: The source array is *not* (and cannot be) wiped by this
    ///   initializer. Prefer ``init(count:initializingWith:)`` when you control
    ///   how the bytes are produced.
    public init(_ bytes: [UInt8]) {
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bytes.count)
        buffer.initialize(repeating: 0)
        bytes.withUnsafeBufferPointer { source in
            if let src = source.baseAddress, let dst = buffer.baseAddress {
                dst.update(from: src, count: bytes.count)
            }
        }
        self.buffer = buffer
    }

    #if canImport(Foundation)
    /// Copies the given `Data` into freshly allocated secured storage.
    ///
    /// - Note: The source `Data` is not wiped by this initializer.
    public init(_ data: Data) {
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: data.count)
        buffer.initialize(repeating: 0)
        if let dst = buffer.baseAddress, !data.isEmpty {
            data.copyBytes(to: dst, count: data.count)
        }
        self.buffer = buffer
    }
    #endif

    // MARK: - Lifecycle

    deinit {
        secureZero(buffer)
        buffer.deallocate()
    }

    // MARK: - Inspection

    /// The number of bytes held.
    public var count: Int { buffer.count }

    /// Whether the buffer is empty.
    public var isEmpty: Bool { buffer.count == 0 }

    /// A redacted description that never reveals the contents.
    ///
    /// `SecureBytes` deliberately does not conform to `CustomStringConvertible`
    /// (the contents must never be interpolated), but this property is available
    /// for logging the size only.
    public var redactedDescription: String {
        "SecureBytes(\(buffer.count) bytes, [REDACTED])"
    }

    // MARK: - Scoped access

    /// Provides scoped, read-only access to the raw bytes.
    ///
    /// The pointer is valid only for the duration of `body`; do not escape it.
    public borrowing func withUnsafeBytes<R>(
        _ body: (UnsafeRawBufferPointer) throws -> R
    ) rethrows -> R {
        try body(UnsafeRawBufferPointer(buffer))
    }

    /// Provides scoped, mutable access to the bytes for in-place operations.
    ///
    /// The pointer is valid only for the duration of `body`; do not escape it.
    public mutating func withUnsafeMutableBytes<R>(
        _ body: (UnsafeMutableBufferPointer<UInt8>) throws -> R
    ) rethrows -> R {
        try body(buffer)
    }

    // MARK: - Manual wiping

    /// Overwrites the contents with zeros immediately, without releasing the
    /// storage.
    ///
    /// `deinit` performs the same wipe automatically; call this only when you
    /// want to clear key material before the value would otherwise go out of
    /// scope. The operation is idempotent.
    public mutating func zeroize() {
        secureZero(buffer)
    }
}
