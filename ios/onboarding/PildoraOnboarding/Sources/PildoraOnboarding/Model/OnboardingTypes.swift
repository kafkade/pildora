import Foundation

// MARK: - Step

/// The ordered steps of first-run onboarding. The raw `Int` order is used to
/// persist and resume progress if the app is closed mid-flow.
public enum OnboardingStep: Int, CaseIterable, Codable, Comparable, Sendable {
    /// Welcome + zero-knowledge explainer.
    case welcome = 0
    /// Master password creation (with strength meter + requirements).
    case password = 1
    /// Recovery key reveal + PDF export.
    case recoveryKey = 2
    /// Explicit acknowledgement that data is unrecoverable without the key.
    case warning = 3
    /// Biometric unlock opt-in (Face ID / Touch ID).
    case biometrics = 4
    /// Optional iCloud Keychain backup of the device unlock key.
    case iCloudBackup = 5
    /// Guided (skippable) first medication entry.
    case firstMedication = 6
    /// Success / hand-off to the app.
    case done = 7

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The next step, or `nil` if this is the last one.
    public var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    /// The previous step, or `nil` if this is the first one.
    public var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

// MARK: - First medication draft

/// The minimal medication captured during the optional guided first entry.
///
/// Onboarding keeps this deliberately light (no persistence dependency): the app
/// maps it into a real `Medication` in the encrypted store once the vault is
/// open. "Medication" here means prescription/OTC drugs *and* supplements.
public struct FirstMedicationDraft: Equatable, Sendable {
    /// Product name (required).
    public var name: String
    /// Free-text dosage/strength, e.g. "500 mg" (optional).
    public var dosage: String
    /// Free-text schedule note, e.g. "Once daily" (optional).
    public var schedule: String

    public init(name: String, dosage: String = "", schedule: String = "") {
        self.name = name
        self.dosage = dosage
        self.schedule = schedule
    }

    /// Whether the draft has enough to be worth saving (a non-blank name).
    public var isSaveable: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Result

/// Everything the app needs once onboarding finishes, handed to the completion
/// callback. The app is responsible for storing `vaultKey` securely (Keychain,
/// gated by biometrics when `biometricUnlockEnabled` is true), persisting
/// `config`, opening the vault, and saving `firstMedication` if present.
public struct OnboardingResult {
    /// Non-secret material to persist so the vault can be reopened + recovered.
    public let config: VaultConfig
    /// Live vault key — store in the Keychain only.
    public let vaultKey: Data
    /// Whether the user opted into biometric unlock.
    public let biometricUnlockEnabled: Bool
    /// Whether the user opted into iCloud Keychain backup of the unlock key.
    public let iCloudKeychainBackupEnabled: Bool
    /// The optional first medication to seed the vault with.
    public let firstMedication: FirstMedicationDraft?

    public init(
        config: VaultConfig,
        vaultKey: Data,
        biometricUnlockEnabled: Bool,
        iCloudKeychainBackupEnabled: Bool,
        firstMedication: FirstMedicationDraft?
    ) {
        self.config = config
        self.vaultKey = vaultKey
        self.biometricUnlockEnabled = biometricUnlockEnabled
        self.iCloudKeychainBackupEnabled = iCloudKeychainBackupEnabled
        self.firstMedication = firstMedication
    }
}
