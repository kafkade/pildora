import SwiftUI

/// Step 5 — Biometric unlock opt-in (Face ID / Touch ID). Optional: the user can
/// enable it (which prompts for a biometric check) or skip. If no biometric is
/// available, the step auto-advances via a plain Continue.
struct BiometricStepView: View {
    @ObservedObject var model: OnboardingFlowModel

    private var kind: BiometricKind { model.biometricKind }

    var body: some View {
        OnboardingScaffold(
            icon: kind.systemImage,
            title: kind.isAvailable ? "Unlock with \(kind.displayName)" : "Set a quick unlock",
            subtitle: kind.isAvailable
                ? "Skip typing your master password every time. \(kind.displayName) unlocks your vault on this device; your password still protects your data."
                : "This device doesn't have biometric unlock set up. You'll use your master password to unlock Pildora."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if kind.isAvailable {
                    infoRow(icon: "bolt.fill", text: "Faster unlock without exposing your password.")
                    infoRow(icon: "iphone.gen3", text: "Stays on this device — never synced or shared.")

                    if model.biometricUnlockEnabled {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Colors.success)
                                .accessibilityHidden(true)
                            Text("\(kind.displayName) is on.")
                                .font(Theme.Typography.bodyEmphasized)
                                .foregroundStyle(Colors.textPrimary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                if let error = model.errorMessage {
                    OnboardingErrorBanner(message: error)
                }
            }
        } footer: {
            if kind.isAvailable && !model.biometricUnlockEnabled {
                PildoraButton("Enable \(kind.displayName)", systemImage: kind.systemImage, variant: .primary) {
                    Task { await model.enableBiometrics() }
                }
                .disabled(model.isWorking)
                PildoraButton("Not now", variant: .secondary) {
                    model.skipBiometrics()
                    model.next()
                }
            } else {
                PildoraButton("Continue", variant: .primary) { model.next() }
            }
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Colors.primary)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Typography.body)
                .foregroundStyle(Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}
