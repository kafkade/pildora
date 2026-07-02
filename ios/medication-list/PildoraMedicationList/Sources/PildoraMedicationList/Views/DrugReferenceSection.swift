import SwiftUI
import PildoraDesignSystem

// MARK: - Drug Reference Section

/// Displays basic, plaintext drug reference data for a medication: drug class,
/// common side effects, **source + date attribution**, and the required
/// informational-only disclaimer.
///
/// Risk: 🟡 Informational. Presents published reference data only — never
/// dosing or diagnostic guidance.
struct DrugReferenceSection: View {
    let reference: DrugReference?

    var body: some View {
        Section {
            if let reference {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    labeledRow(label: "Drug class", value: reference.drugClass)

                    if !reference.commonSideEffects.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Common side effects")
                                .font(Typography.caption.weight(.semibold))
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(reference.commonSideEffects.joined(separator: ", "))
                                .font(Typography.body)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    SourceTag(reference.attribution())

                    Text(DrugReference.disclaimer)
                        .font(Typography.caption)
                        .italic()
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, Theme.Spacing.xxs)
            } else {
                Text("No reference information available for this item.")
                    .font(Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        } header: {
            Text("Reference")
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func labeledRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(value)
                .font(Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
