import Foundation

// MARK: - Progress (resume) state

/// Persisted onboarding progress so the flow can resume if the app is closed
/// mid-way. Deliberately holds **no** secret material — only which step the user
/// reached and their non-sensitive choices. The password, keys, and recovery
/// material are never written here; if the user quits before finishing, they
/// simply re-enter the password.
public struct OnboardingProgress: Codable, Equatable, Sendable {
    /// The furthest step the user has reached.
    public var step: OnboardingStep
    /// Whether biometric unlock was opted into (captured on the biometrics step).
    public var biometricUnlockEnabled: Bool
    /// Whether iCloud Keychain backup was opted into.
    public var iCloudKeychainBackupEnabled: Bool

    public init(
        step: OnboardingStep = .welcome,
        biometricUnlockEnabled: Bool = false,
        iCloudKeychainBackupEnabled: Bool = false
    ) {
        self.step = step
        self.biometricUnlockEnabled = biometricUnlockEnabled
        self.iCloudKeychainBackupEnabled = iCloudKeychainBackupEnabled
    }
}

// MARK: - Store seam

/// Persists onboarding progress (for resume) and the completed vault config.
///
/// Split behind a protocol so the flow is testable with an in-memory fake and so
/// the app can back it with `UserDefaults` (config + progress are non-secret).
public protocol OnboardingStateStore: AnyObject {
    /// The saved resume progress, or `nil` if onboarding hasn't started.
    func loadProgress() -> OnboardingProgress?
    /// Persist the latest resume progress.
    func saveProgress(_ progress: OnboardingProgress)
    /// The completed vault config, or `nil` if onboarding isn't finished.
    func loadVaultConfig() -> VaultConfig?
    /// Persist the vault config and mark onboarding complete. Also clears any
    /// resume progress.
    func completeOnboarding(config: VaultConfig)
    /// Whether onboarding has been completed (a vault config exists).
    var isOnboardingComplete: Bool { get }
    /// Remove all onboarding state (used by tests and "reset app" flows).
    func reset()
}

public extension OnboardingStateStore {
    var isOnboardingComplete: Bool { loadVaultConfig() != nil }
}

// MARK: - UserDefaults-backed store

/// A `UserDefaults`-backed ``OnboardingStateStore``. Stores only non-secret
/// JSON (progress + wrapped-key config). The live vault key lives in the
/// Keychain, managed by the app — never here.
public final class UserDefaultsOnboardingStateStore: OnboardingStateStore {
    private let defaults: UserDefaults
    private let progressKey = "com.kafkade.pildora.onboarding.progress"
    private let configKey = "com.kafkade.pildora.onboarding.vaultConfig"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadProgress() -> OnboardingProgress? {
        decode(OnboardingProgress.self, forKey: progressKey)
    }

    public func saveProgress(_ progress: OnboardingProgress) {
        encode(progress, forKey: progressKey)
    }

    public func loadVaultConfig() -> VaultConfig? {
        decode(VaultConfig.self, forKey: configKey)
    }

    public func completeOnboarding(config: VaultConfig) {
        encode(config, forKey: configKey)
        defaults.removeObject(forKey: progressKey)
    }

    public func reset() {
        defaults.removeObject(forKey: progressKey)
        defaults.removeObject(forKey: configKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

// MARK: - In-memory store (tests/previews)

/// A non-persistent ``OnboardingStateStore`` for tests and previews.
public final class InMemoryOnboardingStateStore: OnboardingStateStore {
    private var progress: OnboardingProgress?
    private var config: VaultConfig?

    public init(progress: OnboardingProgress? = nil, config: VaultConfig? = nil) {
        self.progress = progress
        self.config = config
    }

    public func loadProgress() -> OnboardingProgress? { progress }
    public func saveProgress(_ progress: OnboardingProgress) { self.progress = progress }
    public func loadVaultConfig() -> VaultConfig? { config }
    public func completeOnboarding(config: VaultConfig) {
        self.config = config
        progress = nil
    }
    public func reset() {
        progress = nil
        config = nil
    }
}
