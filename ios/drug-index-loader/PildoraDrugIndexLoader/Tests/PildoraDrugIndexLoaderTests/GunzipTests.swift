import Foundation
import XCTest

@testable import PildoraDrugIndexLoader

final class GunzipTests: XCTestCase {

    func testRoundTripSmall() throws {
        let original = Data("the quick brown fox jumps over the lazy dog".utf8)
        let gz = TestGzip.compress(original)
        XCTAssertNotEqual(gz, original)
        let out = try Gunzip.decompress(gz)
        XCTAssertEqual(out, original)
    }

    func testRoundTripLargeBinary() throws {
        var original = Data(count: 0)
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<(300 * 1024) { original.append(UInt8.random(in: 0...255, using: &rng)) }
        let gz = TestGzip.compress(original)
        let out = try Gunzip.decompress(gz)
        XCTAssertEqual(out.count, original.count)
        XCTAssertEqual(out, original)
    }

    func testDecompressFileMatchesInMemory() throws {
        let original = Data("hello gzip file path".utf8)
        let gz = TestGzip.compress(original)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gz-\(UUID().uuidString).gz")
        try gz.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Gunzip.decompressFile(at: url), original)
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try Gunzip.decompress(Data())) { error in
            guard case DrugIndexLoaderError.decompressionFailed = error else {
                return XCTFail("expected decompressionFailed, got \(error)")
            }
        }
    }

    func testCorruptInputThrows() {
        let garbage = Data([0x1f, 0x8b, 0x08, 0x00, 0xde, 0xad, 0xbe, 0xef, 0x00, 0x01, 0x02])
        XCTAssertThrowsError(try Gunzip.decompress(garbage)) { error in
            guard case DrugIndexLoaderError.decompressionFailed = error else {
                return XCTFail("expected decompressionFailed, got \(error)")
            }
        }
    }
}
