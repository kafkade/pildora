import SwiftUI

/// Convenience factory for SwiftUI previews and tests: builds an
/// ``OnboardingFlowModel`` wired to the deterministic stub crypto, an in-memory
/// state store, and a fake biometric.
public enum OnboardingPreview {
    @MainActor
    public static func makeModel(
        startAt step: OnboardingStep = .welcome,
        biometric: BiometricKind = .faceID
    ) -> OnboardingFlowModel {
        let progress: OnboardingProgress? = step == .welcome ? nil : OnboardingProgress(step: step)
        let model = OnboardingFlowModel(
            crypto: StubOnboardingCrypto(),
            store: InMemoryOnboardingStateStore(progress: progress),
            biometrics: StubBiometrics(kind: biometric),
            vaultID: "preview-vault",
            vaultName: "Me",
            onComplete: { _ in },
            onDismiss: {}
        )
        return model
    }
}

#if DEBUG
#Preview("Welcome") {
    OnboardingFlowView(model: OnboardingPreview.makeModel(startAt: .welcome))
}

#Preview("Password") {
    OnboardingFlowView(model: OnboardingPreview.makeModel(startAt: .password))
}

#Preview("Warning") {
    OnboardingFlowView(model: OnboardingPreview.makeModel(startAt: .warning))
}
#endif
