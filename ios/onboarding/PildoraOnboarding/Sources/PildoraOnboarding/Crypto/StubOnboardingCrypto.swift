import Foundation

/// A deterministic, dependency-free ``OnboardingCrypto`` for tests and SwiftUI
/// previews.
///
/// It performs **no real cryptography** — it derives stable, well-formed byte
/// blobs from the password so the onboarding flow can be exercised end-to-end
/// under `swift test` and in previews without linking the Rust FFI or paying the
/// Argon2id cost. Never use it in production.
public struct StubOnboardingCrypto: OnboardingCrypto {
    /// If set, `createVault` throws this error — lets tests drive the failure
    /// path (e.g. surfacing a crypto error in the UI).
    private let failure: OnboardingCryptoError?

    public init(failure: OnboardingCryptoError? = nil) {
        self.failure = failure
    }

    public func createVault(
        password: String,
        vaultID: String,
        vaultName: String
    ) throws -> VaultSetup {
        if let failure { throw failure }

        let seed = Array("pildora-stub::\(password)".utf8)
        let salt = Data(fill(32, seed: seed, tag: 0x01))
        let vaultKey = Data(fill(32, seed: seed, tag: 0x02))
        let wrappedVaultKey = Data(fill(60, seed: seed, tag: 0x03))
        let recoveryWrappedMek = Data(fill(60, seed: seed, tag: 0x04))
        let recoveryKeyBytes = fill(32, seed: seed, tag: 0x05)

        let display = RecoveryKeyFormatting.displayString(for: recoveryKeyBytes) { bytes in
            // Deterministic 2-byte "checksum" stand-in for previews/tests.
            [bytes.reduce(0, &+), bytes.reversed().reduce(0, &+)]
        }

        let config = VaultConfig(
            vaultID: vaultID,
            vaultName: vaultName,
            salt: salt,
            wrappedVaultKey: wrappedVaultKey,
            recoveryWrappedMek: recoveryWrappedMek
        )
        return VaultSetup(config: config, vaultKey: vaultKey, recoveryKeyDisplay: display)
    }

    /// Produce `count` deterministic bytes from a seed + tag (a tiny LCG). Not
    /// secure — only stable and well-distributed enough for realistic fixtures.
    private func fill(_ count: Int, seed: [UInt8], tag: UInt8) -> [UInt8] {
        var state: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in seed { state = (state ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
        state ^= UInt64(tag) &* 0x9E37_79B9_7F4A_7C15
        var out = [UInt8]()
        out.reserveCapacity(count)
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            out.append(UInt8((state >> 33) & 0xFF))
        }
        return out
    }
}
