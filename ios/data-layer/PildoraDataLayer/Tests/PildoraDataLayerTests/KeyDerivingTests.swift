import XCTest
@testable import PildoraDataLayer

/// Locks the SQLCipher key derivation to the same output the Rust FFI
/// (`deriveSqlcipherKey`) produces, and verifies the passphrase contract.
final class KeyDerivingTests: XCTestCase {
    /// The shared known-answer vector: HKDF-SHA256(ikm = 32×0x01, salt = None,
    /// info = "pildora-sqlcipher-db-key", L = 32). Must match the Rust unit
    /// test `ffi_derive_sqlcipher_key_known_answer` byte-for-byte.
    private let knownAnswerHex =
        "4932fed991ba6253e6a091a2cc54189cb2eb43df515ad977691d2781d70ec392"

    func testDeriverMatchesRustKnownAnswerVector() throws {
        let vaultKey = Data(repeating: 0x01, count: 32)
        let derived = try HKDFTestKeyDeriver().deriveDatabaseKey(vaultKey: vaultKey)
        XCTAssertEqual(derived.map { String(format: "%02x", $0) }.joined(), knownAnswerHex)
    }

    func testDerivationIsDeterministicAndDomainSeparated() throws {
        let deriver = HKDFTestKeyDeriver()
        let vaultKey = TestFixtures.vaultKey(byte: 0x2a)
        let a = try deriver.deriveDatabaseKey(vaultKey: vaultKey)
        let b = try deriver.deriveDatabaseKey(vaultKey: vaultKey)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
        XCTAssertNotEqual(a, vaultKey, "database key must not equal the vault key")
    }

    func testDifferentVaultKeysProduceDifferentDatabaseKeys() throws {
        let deriver = HKDFTestKeyDeriver()
        let a = try deriver.deriveDatabaseKey(vaultKey: TestFixtures.vaultKey(byte: 0x01))
        let b = try deriver.deriveDatabaseKey(vaultKey: TestFixtures.vaultKey(byte: 0x02))
        XCTAssertNotEqual(a, b)
    }

    func testPassphraseIsLowercaseHexOf32Bytes() throws {
        let passphrase = try HKDFTestKeyDeriver().databasePassphrase(vaultKey: TestFixtures.vaultKey())
        XCTAssertEqual(passphrase.count, 64)
        XCTAssertEqual(passphrase, knownAnswerHex)
        XCTAssertTrue(passphrase.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testInvalidVaultKeyLengthThrows() {
        XCTAssertThrowsError(try HKDFTestKeyDeriver().deriveDatabaseKey(vaultKey: Data(repeating: 0, count: 16))) {
            XCTAssertEqual($0 as? DataLayerError, .invalidVaultKeyLength(16))
        }
    }

    func testOpeningWithWrongLengthVaultKeyThrows() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pildora-badkey-\(UUID().uuidString).db")
        defer { TestFixtures.remove(at: url) }
        XCTAssertThrowsError(
            try AppDatabase.open(
                at: url.path,
                vaultKey: Data(repeating: 0, count: 31),
                keyDeriver: HKDFTestKeyDeriver(),
                fileProtection: false
            )
        ) {
            XCTAssertEqual($0 as? DataLayerError, .invalidVaultKeyLength(31))
        }
    }
}
