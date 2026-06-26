import XCTest
@testable import PildoraSecureMemory

final class SecureBytesTests: XCTestCase {

    // MARK: - secureZero primitive

    func testSecureZeroClearsRawBuffer() {
        let count = 64
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0xAB)

        XCTAssertTrue(buffer.allSatisfy { $0 == 0xAB })
        secureZero(buffer)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0 }, "secureZero must overwrite every byte with 0")
    }

    func testSecureZeroOnEmptyBufferIsNoOp() {
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 0)
        defer { buffer.deallocate() }
        // Must not crash on a zero-length buffer.
        secureZero(buffer)
        XCTAssertEqual(buffer.count, 0)
    }

    // MARK: - Construction

    func testInitCountIsZeroFilled() {
        let secure = SecureBytes(count: 32)
        XCTAssertEqual(secure.count, 32)
        secure.withUnsafeBytes { raw in
            XCTAssertTrue(raw.allSatisfy { $0 == 0 })
        }
    }

    func testInitFromArrayRoundTrips() {
        let bytes: [UInt8] = Array(0..<32)
        let secure = SecureBytes(bytes)
        XCTAssertEqual(secure.count, 32)
        secure.withUnsafeBytes { raw in
            XCTAssertEqual(Array(raw), bytes)
        }
    }

    func testInitInitializingWithFillsInPlace() {
        let secure = SecureBytes(count: 16) { buffer in
            for index in buffer.indices {
                buffer[index] = UInt8(index)
            }
        }
        secure.withUnsafeBytes { raw in
            XCTAssertEqual(Array(raw), Array(0..<16).map(UInt8.init))
        }
    }

    func testEmptySecureBytes() {
        let secure = SecureBytes(count: 0)
        XCTAssertEqual(secure.count, 0)
        XCTAssertTrue(secure.isEmpty)
        secure.withUnsafeBytes { raw in
            XCTAssertEqual(raw.count, 0)
        }
    }

    // MARK: - Mutation

    func testWithUnsafeMutableBytesMutatesContents() {
        var secure = SecureBytes(count: 8)
        secure.withUnsafeMutableBytes { buffer in
            for index in buffer.indices {
                buffer[index] = 0xFF
            }
        }
        secure.withUnsafeBytes { raw in
            XCTAssertTrue(raw.allSatisfy { $0 == 0xFF })
        }
    }

    func testWithUnsafeBytesReturnsValue() {
        let secure = SecureBytes([1, 2, 3, 4])
        let sum = secure.withUnsafeBytes { raw in
            raw.reduce(0) { $0 + Int($1) }
        }
        XCTAssertEqual(sum, 10)
    }

    // MARK: - Zeroization

    func testZeroizeClearsContents() {
        var secure = SecureBytes(Array(repeating: 0xAB, count: 32))
        secure.withUnsafeBytes { raw in
            XCTAssertTrue(raw.allSatisfy { $0 == 0xAB })
        }

        secure.zeroize()

        secure.withUnsafeBytes { raw in
            XCTAssertTrue(raw.allSatisfy { $0 == 0 }, "zeroize must overwrite every byte with 0")
        }
    }

    func testZeroizeIsIdempotent() {
        var secure = SecureBytes(Array(repeating: 0x11, count: 16))
        secure.zeroize()
        secure.zeroize()
        secure.withUnsafeBytes { raw in
            XCTAssertTrue(raw.allSatisfy { $0 == 0 })
        }
    }

    // MARK: - Move-only semantics

    func testConsumingMovePreservesContents() {
        let original = SecureBytes(Array(repeating: 0x7E, count: 8))
        // Consuming `original` moves ownership into `moved`; the compiler
        // forbids any further use of `original`, which is the copy-prevention
        // guarantee this type exists to provide.
        let moved = consume original
        moved.withUnsafeBytes { raw in
            XCTAssertTrue(raw.allSatisfy { $0 == 0x7E })
        }
    }

    // MARK: - Redaction

    func testRedactedDescriptionHidesContents() {
        let secure = SecureBytes(Array(repeating: 0xAB, count: 4))
        let description = secure.redactedDescription
        XCTAssertEqual(description, "SecureBytes(4 bytes, [REDACTED])")
        XCTAssertFalse(description.lowercased().contains("ab"))
    }
}
