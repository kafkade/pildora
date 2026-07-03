import SwiftUI

/// Step 7 — Guided first medication entry. Optional and skippable: a gentle
/// first-use nudge to add one medication or supplement. Only the name is
/// required; dosage and schedule are free-text hints refined later in the app.
struct FirstMedicationStepView: View {
    @ObservedObject var model: OnboardingFlowModel
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingScaffold(
            icon: "pills.fill",
            title: "Add your first medication",
            subtitle: "Track a prescription, over-the-counter medicine, or supplement. You can skip this and add things later."
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PildoraTextField(
                    "Name",
                    text: $model.firstMedication.name,
                    placeholder: "e.g. Vitamin D, Ibuprofen",
                    systemImage: "pills"
                )
                .focused($focused)

                PildoraTextField(
                    "Dosage (optional)",
                    text: $model.firstMedication.dosage,
                    placeholder: "e.g. 1000 IU, 200 mg",
                    systemImage: "scalemass"
                )

                PildoraTextField(
                    "Schedule (optional)",
                    text: $model.firstMedication.schedule,
                    placeholder: "e.g. Once daily with breakfast",
                    systemImage: "clock"
                )

                Text("This is a tracking tool, not medical advice. Always follow your healthcare provider's instructions.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Colors.textSecondary)

                if let error = model.errorMessage {
                    OnboardingErrorBanner(message: error)
                }
            }
        } footer: {
            PildoraButton(model.isWorking ? "Finishing…" : "Add & Finish", variant: .primary) {
                focused = false
                model.next()
            }
            .disabled(!model.firstMedication.isSaveable || model.isWorking)
            .opacity(model.firstMedication.isSaveable && !model.isWorking ? 1 : 0.5)

            PildoraButton("Skip for now", variant: .secondary) {
                focused = false
                model.skipFirstMedication()
            }
            .disabled(model.isWorking)
        }
    }
}
