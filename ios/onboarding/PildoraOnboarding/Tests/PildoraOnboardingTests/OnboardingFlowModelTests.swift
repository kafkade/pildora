import XCTest
@testable import PildoraOnboarding

@MainActor
final class OnboardingFlowModelTests: XCTestCase {

    private let strongPassword = "Xk9!vBw2#qLmZ7$r"

    /// Records the completion result and lets a test force a failure.
    private final class CompletionRecorder {
        var result: OnboardingResult?
        var shouldThrow = false
        var dismissed = false
    }

    private func makeModel(
        store: OnboardingStateStore = InMemoryOnboardingStateStore(),
        biometric: BiometricKind = .faceID,
        authResult: Bool = true,
        cryptoFailure: OnboardingCryptoError? = nil,
        recorder: CompletionRecorder = CompletionRecorder()
    ) -> (OnboardingFlowModel, CompletionRecorder) {
        let model = OnboardingFlowModel(
            crypto: StubOnboardingCrypto(failure: cryptoFailure),
            store: store,
            biometrics: StubBiometrics(kind: biometric, authResult: authResult),
            vaultID: "vault-1",
            vaultName: "Me",
            onComplete: { result in
                if recorder.shouldThrow {
                    throw OnboardingCryptoError.cryptoFailure("boom")
                }
                recorder.result = result
            },
            onDismiss: { recorder.dismissed = true }
        )
        return (model, recorder)
    }

    // MARK: Start / resume

    func testStartsAtWelcomeWithNoProgress() {
        let (model, _) = makeModel()
        XCTAssertEqual(model.step, .welcome)
    }

    func testResumeClampsToPasswordStep() {
        // No secret material is persisted, so any progress past welcome resumes
        // at the password step.
        let store = InMemoryOnboardingStateStore(
            progress: OnboardingProgress(step: .biometrics, biometricUnlockEnabled: true)
        )
        let (model, _) = makeModel(store: store)
        XCTAssertEqual(model.step, .password)
        XCTAssertTrue(model.biometricUnlockEnabled, "opt-in choices are restored as defaults")
    }

    // MARK: Password step

    func testPasswordStepRejectsWeakOrMismatched() {
        let (model, _) = makeModel()
        model.password = "short"
        model.confirmation = "short"
        XCTAssertFalse(model.canSubmitPassword)

        model.password = strongPassword
        model.confirmation = "different"
        XCTAssertFalse(model.canSubmitPassword)

        model.confirmation = strongPassword
        XCTAssertTrue(model.canSubmitPassword)
    }

    func testSubmitPasswordBuildsRecoveryAndAdvances() async {
        let (model, _) = makeModel()
        model.password = strongPassword
        model.confirmation = strongPassword
        await model.submitPassword()

        XCTAssertEqual(model.step, .recoveryKey)
        XCTAssertNotNil(model.recoveryDocument)
        XCTAssertFalse(model.recoveryDocument?.recoveryKey.isEmpty ?? true)
        XCTAssertNil(model.errorMessage)
    }

    func testSubmitPasswordSurfacesCryptoFailure() async {
        let (model, _) = makeModel(cryptoFailure: .cryptoFailure("nope"))
        model.password = strongPassword
        model.confirmation = strongPassword
        await model.submitPassword()

        XCTAssertNotEqual(model.step, .recoveryKey, "must not advance on crypto failure")
        XCTAssertNotNil(model.errorMessage)
    }

    // MARK: Gates

    func testRecoveryStepGatedOnConfirmation() async {
        let (model, _) = await advanceToRecovery()
        XCTAssertFalse(model.canLeaveRecovery)
        model.confirmedRecoverySaved = true
        XCTAssertTrue(model.canLeaveRecovery)
    }

    func testBiometricEnableAndSkip() async {
        let (model, _) = makeModel(biometric: .faceID, authResult: true)
        await model.enableBiometrics()
        XCTAssertTrue(model.biometricUnlockEnabled)

        let (failModel, _) = makeModel(biometric: .faceID, authResult: false)
        await failModel.enableBiometrics()
        XCTAssertFalse(failModel.biometricUnlockEnabled)
        XCTAssertNotNil(failModel.errorMessage)

        failModel.skipBiometrics()
        XCTAssertFalse(failModel.biometricUnlockEnabled)
    }

    // MARK: Completion

    func testFinishViaSkipCommitsWithoutMedication() async {
        let store = InMemoryOnboardingStateStore()
        let (model, recorder) = makeModel(store: store)
        await runToFirstMedication(model)

        model.skipFirstMedication()
        await settle()

        XCTAssertEqual(model.step, .done)
        XCTAssertNotNil(recorder.result)
        XCTAssertNil(recorder.result?.firstMedication)
        XCTAssertTrue(store.isOnboardingComplete)
        XCTAssertEqual(store.loadVaultConfig()?.vaultID, "vault-1")
    }

    func testFinishWithFirstMedicationIncludesIt() async {
        let (model, recorder) = makeModel()
        await runToFirstMedication(model)

        model.firstMedication = FirstMedicationDraft(name: "Vitamin D", dosage: "1000 IU", schedule: "Daily")
        model.next() // Add & Finish
        await settle()

        XCTAssertEqual(model.step, .done)
        XCTAssertEqual(recorder.result?.firstMedication?.name, "Vitamin D")
    }

    func testFinishFailureKeepsUserOnFirstMedication() async {
        let recorder = CompletionRecorder()
        recorder.shouldThrow = true
        let store = InMemoryOnboardingStateStore()
        let (model, _) = makeModel(store: store, recorder: recorder)
        await runToFirstMedication(model)

        model.skipFirstMedication()
        await settle()

        XCTAssertNotEqual(model.step, .done)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(store.isOnboardingComplete)
    }

    func testDoneStepDismisses() async {
        let (model, recorder) = makeModel()
        await runToFirstMedication(model)
        model.skipFirstMedication()
        await settle()
        XCTAssertEqual(model.step, .done)

        model.next() // Start Using Pildora
        XCTAssertTrue(recorder.dismissed)
    }

    func testResultCarriesOptInChoices() async {
        let (model, recorder) = makeModel(authResult: true)
        model.password = strongPassword
        model.confirmation = strongPassword
        await model.submitPassword()
        model.confirmedRecoverySaved = true
        model.next() // -> warning
        model.acknowledgedDataLoss = true
        model.next() // -> biometrics
        await model.enableBiometrics()
        model.next() // -> iCloud
        model.iCloudKeychainBackupEnabled = true
        model.next() // -> firstMedication
        model.skipFirstMedication()
        await settle()

        XCTAssertEqual(recorder.result?.biometricUnlockEnabled, true)
        XCTAssertEqual(recorder.result?.iCloudKeychainBackupEnabled, true)
    }

    // MARK: Helpers

    private func advanceToRecovery() async -> (OnboardingFlowModel, CompletionRecorder) {
        let (model, recorder) = makeModel()
        model.password = strongPassword
        model.confirmation = strongPassword
        await model.submitPassword()
        return (model, recorder)
    }

    /// Advance the model all the way to the first-medication step.
    private func runToFirstMedication(_ model: OnboardingFlowModel) async {
        model.password = strongPassword
        model.confirmation = strongPassword
        await model.submitPassword()          // -> recoveryKey
        model.confirmedRecoverySaved = true
        model.next()                          // -> warning
        model.acknowledgedDataLoss = true
        model.next()                          // -> biometrics
        model.skipBiometrics()
        model.next()                          // -> iCloud
        model.next()                          // -> firstMedication
        XCTAssertEqual(model.step, .firstMedication)
    }

    /// Let the `Task { await finish() }` spawned by `next()`/`skip…` complete.
    private func settle() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }
}
