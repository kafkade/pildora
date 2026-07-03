import Foundation
import SwiftUI

/// The observable state machine that drives the onboarding flow.
///
/// It owns all step state (password + strength, generated recovery material,
/// opt-in choices, first-medication draft), performs the cryptographic vault
/// setup through the injected ``OnboardingCrypto`` seam, and persists resume
/// progress so a closed-and-reopened app returns the user to a safe point.
///
/// Security: the master password and unwrapped key material live only in memory
/// on this object for the duration of the flow. Nothing secret is written to the
/// resume store — if the flow is interrupted after the password step, it safely
/// restarts at the password step and regenerates fresh keys (nothing was
/// committed yet).
@MainActor
public final class OnboardingFlowModel: ObservableObject {

    // MARK: Injected dependencies

    private let crypto: OnboardingCrypto
    private let store: OnboardingStateStore
    private let biometrics: BiometricAuthenticating
    private let policy: PasswordPolicy
    private let vaultID: String
    private let vaultName: String
    /// The app's commit hook: store the vault key in the Keychain, open the
    /// vault, and seed the first medication. Throwing so failures surface.
    private let onComplete: (OnboardingResult) async throws -> Void
    /// Called when the user leaves the success screen to enter the app.
    private let onDismiss: () -> Void

    // MARK: Published flow state

    @Published public private(set) var step: OnboardingStep
    @Published public private(set) var isWorking = false
    @Published public var errorMessage: String?

    // Password step
    @Published public var password = "" { didSet { recomputeStrength() } }
    @Published public var confirmation = "" { didSet { recomputeStrength() } }
    @Published public private(set) var strength: PasswordStrength = .empty

    // Recovery step
    @Published public private(set) var recoveryDocument: RecoveryDocument?
    @Published public private(set) var didExportRecoveryKey = false
    @Published public var confirmedRecoverySaved = false

    // Warning step
    @Published public var acknowledgedDataLoss = false

    // Biometrics step
    @Published public private(set) var biometricKind: BiometricKind = .none
    @Published public private(set) var biometricUnlockEnabled = false

    // iCloud backup step
    @Published public var iCloudKeychainBackupEnabled = false

    // First medication step
    @Published public var firstMedication = FirstMedicationDraft(name: "")

    /// The unwrapped vault setup, held only in memory once the password step
    /// completes.
    private var vaultSetup: VaultSetup?

    // MARK: Init

    public init(
        crypto: OnboardingCrypto,
        store: OnboardingStateStore,
        biometrics: BiometricAuthenticating,
        policy: PasswordPolicy = .standard,
        vaultID: String,
        vaultName: String = "Me",
        onComplete: @escaping (OnboardingResult) async throws -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.crypto = crypto
        self.store = store
        self.biometrics = biometrics
        self.policy = policy
        self.vaultID = vaultID
        self.vaultName = vaultName
        self.onComplete = onComplete
        self.onDismiss = onDismiss

        // Resume: we can only restore up to the password step, because no secret
        // material is ever persisted. A saved progress past `welcome` therefore
        // resumes at `password` (the user re-enters it) while remembering their
        // opt-in choices as defaults.
        let saved = store.loadProgress()
        self.step = (saved?.step ?? .welcome) == .welcome ? .welcome : .password
        self.biometricUnlockEnabled = saved?.biometricUnlockEnabled ?? false
        self.iCloudKeychainBackupEnabled = saved?.iCloudKeychainBackupEnabled ?? false
        self.biometricKind = biometrics.availableBiometric()
    }

    // MARK: Derived UI state

    /// The live requirement checklist for the password step.
    public var passwordRequirements: [PasswordRequirement] {
        policy.requirements(password: password, confirmation: confirmation, strength: strength)
    }

    /// Whether the password step may advance.
    public var canSubmitPassword: Bool {
        policy.isAcceptable(password: password, confirmation: confirmation, strength: strength)
    }

    /// Whether the recovery step may advance (user confirmed they saved it).
    public var canLeaveRecovery: Bool { confirmedRecoverySaved }

    /// Progress across the flow, 0…1, for a progress indicator.
    public var progressFraction: Double {
        let total = Double(OnboardingStep.allCases.count - 1)
        return total > 0 ? Double(step.rawValue) / total : 0
    }

    // MARK: Step: password

    /// Derive keys and build the vault, then advance to the recovery step.
    public func submitPassword() async {
        guard canSubmitPassword, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let capturedPassword = password
        let id = vaultID
        let name = vaultName
        let cryptoRef = crypto
        do {
            // Argon2id is deliberately slow — run it off the main actor.
            let setup = try await Task.detached(priority: .userInitiated) {
                try cryptoRef.createVault(password: capturedPassword, vaultID: id, vaultName: name)
            }.value
            vaultSetup = setup
            recoveryDocument = RecoveryDocument.standard(
                vaultName: name,
                recoveryKey: setup.recoveryKeyDisplay
            )
            advance(to: .recoveryKey)
        } catch let error as OnboardingCryptoError {
            errorMessage = message(for: error)
        } catch {
            errorMessage = "Couldn't set up your vault. Please try again."
        }
    }

    private func recomputeStrength() {
        strength = PasswordStrengthEvaluator.evaluate(password)
    }

    // MARK: Step: recovery

    /// Render the recovery kit to shareable PDF bytes and mark it exported.
    public func makeRecoveryPDF() -> Data? {
        guard let recoveryDocument else { return nil }
        didExportRecoveryKey = true
        return RecoveryKitPDFRenderer.render(recoveryDocument)
    }

    // MARK: Step: biometrics

    /// Prompt for biometric authentication to confirm the opt-in.
    public func enableBiometrics() async {
        guard biometricKind.isAvailable, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let ok = await biometrics.authenticate(
            reason: "Enable \(biometricKind.displayName) to unlock Pildora"
        )
        biometricUnlockEnabled = ok
        if !ok {
            errorMessage = "\(biometricKind.displayName) wasn't enabled. You can turn it on later in Settings."
        }
    }

    /// Explicitly decline biometric unlock.
    public func skipBiometrics() {
        biometricUnlockEnabled = false
    }

    // MARK: Navigation

    /// Advance to the next step (or run the final commit from the last input
    /// step). Persists resume progress.
    public func next() {
        switch step {
        case .firstMedication:
            Task { await finish() }
        case .done:
            onDismiss()
        default:
            if let next = step.next { advance(to: next) }
        }
    }

    /// Go back one step where that is meaningful.
    public func back() {
        guard let previous = step.previous, step != .done else { return }
        // Never step back into the password from a state that holds generated
        // keys; re-deriving on resubmit keeps things consistent.
        advance(to: previous)
    }

    /// Skip the optional first-medication entry and finish.
    public func skipFirstMedication() {
        firstMedication = FirstMedicationDraft(name: "")
        Task { await finish() }
    }

    private func advance(to newStep: OnboardingStep) {
        step = newStep
        persistProgress()
    }

    private func persistProgress() {
        // Only persist non-secret progress. Steps that depend on in-memory keys
        // are collapsed to `password` on resume by the initializer.
        store.saveProgress(
            OnboardingProgress(
                step: step,
                biometricUnlockEnabled: biometricUnlockEnabled,
                iCloudKeychainBackupEnabled: iCloudKeychainBackupEnabled
            )
        )
    }

    // MARK: Finish

    private func finish() async {
        guard let setup = vaultSetup, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let result = OnboardingResult(
            config: setup.config,
            vaultKey: setup.vaultKey,
            biometricUnlockEnabled: biometricUnlockEnabled,
            iCloudKeychainBackupEnabled: iCloudKeychainBackupEnabled,
            firstMedication: firstMedication.isSaveable ? firstMedication : nil
        )
        do {
            try await onComplete(result)
            store.completeOnboarding(config: setup.config)
            // Drop the live key reference now that it is safely stored.
            vaultSetup = nil
            step = .done
        } catch {
            errorMessage = "Couldn't finish setting up your vault. Please try again."
        }
    }

    private func message(for error: OnboardingCryptoError) -> String {
        switch error {
        case .cryptoFailure:
            return "Couldn't set up your vault's encryption. Please try again."
        }
    }
}
