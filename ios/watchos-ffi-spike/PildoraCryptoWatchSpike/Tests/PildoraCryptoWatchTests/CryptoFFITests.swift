// CryptoFFITests.swift — watchOS FFI validation (issue #42).
//
// Exercises the pildora-crypto-ffi UniFFI bridge on the watchOS simulator to
// prove the Rust static library links and runs correctly on watchOS. Mirrors
// the iOS spike (ios/ffi-spike) so behaviour can be compared across platforms.
//
// The generated UniFFI bindings (pildora_crypto_ffi.swift) are compiled into
// the PildoraCryptoWatchKit library target — copied in by run-watchos-tests.sh,
// so its public free functions (deriveMasterKey, itemEncrypt, ...) are imported
// here. UniFFI maps Rust `Vec<u8>` to Swift `Data`.
//
// NOTE on Argon2id: the simulator runs on host RAM, so timing here does NOT
// validate the real Apple Watch memory ceiling. See README.md — on-device
// profiling is required before shipping, and a reduced-parameter fallback via
// deriveMasterKeyWithParams(...) is available for constrained watches.

import XCTest
import PildoraCryptoWatchKit

final class CryptoFFITests: XCTestCase {

    private let password = Data("watch-spike-password".utf8)

    // MARK: Key derivation

    func testDeriveMasterKeyIsDeterministic() throws {
        let salt = generateSalt()
        XCTAssertEqual(salt.count, 16, "salt should be 16 bytes")

        let mk1 = try deriveMasterKey(password: password, salt: salt)
        let mk2 = try deriveMasterKey(password: password, salt: salt)

        XCTAssertEqual(mk1.count, 32, "master key must be 32 bytes")
        XCTAssertEqual(mk1, mk2, "same password + salt must derive the same key")
    }

    func testDeriveSubKeys() throws {
        let mk = try deriveMasterKey(password: password, salt: generateSalt())
        let sub = try deriveSubKeys(masterKey: mk)
        XCTAssertEqual(sub.authKey.count, 32, "auth key must be 32 bytes")
        XCTAssertEqual(sub.mek.count, 32, "MEK must be 32 bytes")
        XCTAssertNotEqual(sub.authKey, sub.mek, "auth key and MEK must differ")
    }

    // MARK: Vault key wrap / unwrap

    func testVaultKeyWrapUnwrapRoundtrip() throws {
        let mk = try deriveMasterKey(password: password, salt: generateSalt())
        let sub = try deriveSubKeys(masterKey: mk)

        let vaultKey = generateVaultKey()
        XCTAssertEqual(vaultKey.count, 32)

        let wrapped = try wrapVaultKey(vaultKey: vaultKey, mek: sub.mek)
        let unwrapped = try unwrapVaultKey(wrappedVk: wrapped, mek: sub.mek)
        XCTAssertEqual(unwrapped, vaultKey, "unwrapped vault key must match original")
    }

    // MARK: Item encrypt / decrypt — the core spike question

    func testEncryptDecryptRoundtripVariousSizes() throws {
        let vaultKey = generateVaultKey()
        let cases: [(String, Data)] = [
            ("empty", Data()),
            ("small", Data("hello from Apple Watch!".utf8)),
            ("medium-1KB", Data(repeating: 0xAB, count: 1024)),
            ("large-32KB", Data(repeating: 0xCD, count: 32 * 1024)),
        ]
        for (label, plaintext) in cases {
            let blob = try itemEncrypt(plaintext: plaintext, vaultKey: vaultKey)
            let decrypted = try itemDecrypt(blobBytes: blob, vaultKey: vaultKey)
            XCTAssertEqual(decrypted, plaintext, "roundtrip failed for \(label)")
        }
    }

    func testJsonEncryptDecryptRoundtrip() throws {
        let vaultKey = generateVaultKey()
        let json = #"{"name":"Vitamin D","dosage":"2000 IU","frequency":"daily"}"#
        let blob = try encryptJson(jsonString: json, vaultKey: vaultKey)
        let decrypted = try decryptJson(blobBytes: blob, vaultKey: vaultKey)
        XCTAssertEqual(decrypted, json, "JSON roundtrip must be identical")
    }

    func testWrongKeyFailsToDecrypt() throws {
        let vk1 = generateVaultKey()
        let vk2 = generateVaultKey()
        let blob = try itemEncrypt(plaintext: Data("secret".utf8), vaultKey: vk1)
        XCTAssertThrowsError(
            try itemDecrypt(blobBytes: blob, vaultKey: vk2),
            "decrypting with the wrong vault key must fail"
        )
    }

    // MARK: SQLCipher key + hashing

    func testDeriveSqlcipherKey() throws {
        let vaultKey = generateVaultKey()
        let k1 = try deriveSqlcipherKey(vaultKey: vaultKey)
        let k2 = try deriveSqlcipherKey(vaultKey: vaultKey)
        XCTAssertEqual(k1.count, 32)
        XCTAssertEqual(k1, k2, "sqlcipher key derivation must be deterministic")
        XCTAssertNotEqual(k1, vaultKey, "db key must not be the raw vault key")
    }

    func testBlake2bDeterministic() throws {
        let data = Data("test data".utf8)
        XCTAssertEqual(blake2bHash(data: data), blake2bHash(data: data))
        XCTAssertEqual(blake2bHash(data: data).count, 32)
    }

    // MARK: Argon2id parameter behaviour on watchOS

    /// Reduced Argon2id parameters must still derive a valid, deterministic
    /// 32-byte key. These are the kind of constrained parameters the watch app
    /// may adopt if the 64 MiB default proves too heavy on-device. The exact
    /// parameters used MUST be persisted in vault metadata (see README.md).
    func testReducedArgon2idParamsDeriveValidKey() throws {
        let salt = generateSalt()
        // 16 MiB, 3 iterations, parallelism 1 — a plausible constrained profile.
        let k1 = try deriveMasterKeyWithParams(
            password: password, salt: salt,
            memoryKib: 16 * 1024, iterations: 3, parallelism: 1
        )
        let k2 = try deriveMasterKeyWithParams(
            password: password, salt: salt,
            memoryKib: 16 * 1024, iterations: 3, parallelism: 1
        )
        XCTAssertEqual(k1.count, 32)
        XCTAssertEqual(k1, k2, "reduced-param derivation must be deterministic")

        // Different parameters must produce a different key for the same
        // password — this is why parameters must be stored with the vault.
        let kDefault = try deriveMasterKey(password: password, salt: salt)
        XCTAssertNotEqual(k1, kDefault, "changing params must change the key")
    }

    /// Records a timing sample for the *default* 64 MiB Argon2id derivation so
    /// reviewers can eyeball simulator cost. This is informational only — it
    /// does NOT validate the real device memory ceiling.
    func testDefaultArgon2idTimingSample() throws {
        let salt = generateSalt()
        let start = Date()
        _ = try deriveMasterKey(password: password, salt: salt)
        let ms = Date().timeIntervalSince(start) * 1000.0
        print("ℹ️ Argon2id default (64 MiB, 3 iters) on watchOS simulator: \(String(format: "%.1f", ms)) ms (host RAM — NOT a device memory test)")
    }
}
