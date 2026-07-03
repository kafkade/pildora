import SwiftUI

/// Step 2 — Master password creation, with a live strength meter, a requirement
/// checklist, and a confirmation field. Deriving keys (Argon2id) happens on
/// "Continue" and shows a progress state.
struct PasswordStepView: View {
    @ObservedObject var model: OnboardingFlowModel
    @FocusState private var focus: Field?

    private enum Field { case password, confirm }

    var body: some View {
        OnboardingScaffold(
            icon: "key.fill",
            title: "Create your master password",
            subtitle: "This unlocks your vault. Choose something strong you'll remember — it's the one password Pildora can never reset."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    PildoraTextField(
                        "Master password",
                        text: $model.password,
                        placeholder: "Enter a strong password",
                        systemImage: "lock.fill",
                        isSecure: true
                    )
                    .focused($focus, equals: .password)
                    .submitLabel(.next)
                    .onSubmit { focus = .confirm }

                    PasswordStrengthMeter(strength: model.strength, isActive: !model.password.isEmpty)
                }

                PildoraTextField(
                    "Confirm password",
                    text: $model.confirmation,
                    placeholder: "Re-enter your password",
                    systemImage: "lock.rotation",
                    isSecure: true
                )
                .focused($focus, equals: .confirm)
                .submitLabel(.done)

                requirementChecklist

                if let tip = model.strength.suggestions.first, !model.password.isEmpty {
                    Text(tip)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Colors.textSecondary)
                        .accessibilityLabel("Tip: \(tip)")
                }

                if let error = model.errorMessage {
                    OnboardingErrorBanner(message: error)
                }
            }
        } footer: {
            PildoraButton(model.isWorking ? "Securing…" : "Continue", variant: .primary) {
                focus = nil
                Task { await model.submitPassword() }
            }
            .disabled(!model.canSubmitPassword || model.isWorking)
            .opacity(model.canSubmitPassword && !model.isWorking ? 1 : 0.5)
            .overlay(alignment: .trailing) {
                if model.isWorking {
                    ProgressView().padding(.trailing, Theme.Spacing.lg)
                }
            }
            .accessibilityHint("Creates your encrypted vault from this password")
        }
    }

    private var requirementChecklist: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(model.passwordRequirements) { req in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: req.isSatisfied ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(req.isSatisfied ? Colors.success : Colors.textSecondary)
                        .accessibilityHidden(true)
                    Text(req.text)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(req.isSatisfied ? Colors.textPrimary : Colors.textSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(req.text)
                .accessibilityValue(req.isSatisfied ? "Met" : "Not met")
            }
        }
    }
}
