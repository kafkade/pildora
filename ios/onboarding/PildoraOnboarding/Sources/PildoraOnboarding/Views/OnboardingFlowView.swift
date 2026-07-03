import SwiftUI

/// The root onboarding view. Renders a slim progress bar and the current step,
/// switching content as the ``OnboardingFlowModel`` advances.
///
/// The app presents this as the root view on first run and dismisses it (via the
/// model's `onDismiss`) once the user finishes.
public struct OnboardingFlowView: View {
    @ObservedObject private var model: OnboardingFlowModel

    public init(model: OnboardingFlowModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            progressBar
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome:
            WelcomeStepView(model: model)
        case .password:
            PasswordStepView(model: model)
        case .recoveryKey:
            RecoveryKeyStepView(model: model)
        case .warning:
            WarningStepView(model: model)
        case .biometrics:
            BiometricStepView(model: model)
        case .iCloudBackup:
            ICloudBackupStepView(model: model)
        case .firstMedication:
            FirstMedicationStepView(model: model)
        case .done:
            CompletionStepView(model: model)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Colors.separator.opacity(0.4))
                Capsule()
                    .fill(Colors.primary)
                    .frame(width: max(0, geo.size.width * model.progressFraction))
                    .animation(.easeInOut(duration: 0.25), value: model.progressFraction)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
        .accessibilityElement()
        .accessibilityLabel("Setup progress")
        .accessibilityValue("\(Int((model.progressFraction * 100).rounded())) percent")
    }
}
