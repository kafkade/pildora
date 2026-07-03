import XCTest
@testable import PildoraOnboarding

final class OnboardingStateStoreTests: XCTestCase {

    func testInMemoryStoreRoundTripsProgress() {
        let store = InMemoryOnboardingStateStore()
        XCTAssertNil(store.loadProgress())
        let progress = OnboardingProgress(step: .warning, biometricUnlockEnabled: true)
        store.saveProgress(progress)
        XCTAssertEqual(store.loadProgress(), progress)
    }

    func testCompleteOnboardingPersistsConfigAndClearsProgress() {
        let store = InMemoryOnboardingStateStore()
        store.saveProgress(OnboardingProgress(step: .password))
        XCTAssertFalse(store.isOnboardingComplete)

        let config = Self.sampleConfig
        store.completeOnboarding(config: config)
        XCTAssertTrue(store.isOnboardingComplete)
        XCTAssertEqual(store.loadVaultConfig(), config)
        XCTAssertNil(store.loadProgress(), "resume progress should be cleared on completion")
    }

    func testResetClearsEverything() {
        let store = InMemoryOnboardingStateStore()
        store.saveProgress(OnboardingProgress(step: .password))
        store.completeOnboarding(config: Self.sampleConfig)
        store.reset()
        XCTAssertFalse(store.isOnboardingComplete)
        XCTAssertNil(store.loadProgress())
        XCTAssertNil(store.loadVaultConfig())
    }

    func testUserDefaultsStorePersistsAcrossInstances() throws {
        let suiteName = "pildora.onboarding.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsOnboardingStateStore(defaults: defaults)
        store.saveProgress(OnboardingProgress(step: .biometrics, iCloudKeychainBackupEnabled: true))
        store.completeOnboarding(config: Self.sampleConfig)

        // A fresh instance over the same suite reads the persisted config.
        let reopened = UserDefaultsOnboardingStateStore(defaults: defaults)
        XCTAssertTrue(reopened.isOnboardingComplete)
        XCTAssertEqual(reopened.loadVaultConfig(), Self.sampleConfig)
        XCTAssertNil(reopened.loadProgress())
    }

    private static var sampleConfig: VaultConfig {
        VaultConfig(
            vaultID: "v1",
            vaultName: "Me",
            salt: Data(repeating: 1, count: 16),
            wrappedVaultKey: Data(repeating: 2, count: 60),
            recoveryWrappedMek: Data(repeating: 3, count: 60)
        )
    }
}
