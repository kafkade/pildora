import SwiftUI

// MARK: - Medication Row

/// A single medication row in the list: name + dosage, form + frequency, and
/// an inventory status badge when stock is low.
struct MedicationRow: View {
    let medication: Medication
    let inventory: InventoryRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(medication.name)
                    .font(Typography.cardTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.xs)
                Text(medication.dosage)
                    .font(Typography.cardSubtitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Text("\(medication.form.displayName) · \(medication.frequency)")
                .font(Typography.cardSubtitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let generic = medication.genericName {
                Text(generic)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            if let inventory, inventory.isLow {
                StatusBadge(
                    inventory.isCritical
                        ? "Critical: \(inventory.currentCount) left"
                        : "Low: \(inventory.currentCount) left",
                    level: inventory.isCritical ? .error : .warning
                )
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view details")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityLabel: String {
        var parts = ["\(medication.name), \(medication.dosage) \(medication.form.displayName)"]
        if let generic = medication.genericName {
            parts.append("generic \(generic)")
        }
        parts.append(medication.frequency)
        if let inventory, inventory.isLow {
            let severity = inventory.isCritical ? "Critically low" : "Low"
            parts.append("\(severity), \(inventory.currentCount) remaining")
        }
        return parts.joined(separator: ". ")
    }
}
