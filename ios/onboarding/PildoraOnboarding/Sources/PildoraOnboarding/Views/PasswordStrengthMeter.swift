import SwiftUI

/// A segmented strength meter plus a text rating, driven by a
/// ``PasswordStrength``. Uses icon + text + color (never color alone) so it
/// meets the design system's accessibility rule and reads under VoiceOver.
struct PasswordStrengthMeter: View {
    let strength: PasswordStrength
    /// Whether the user has typed anything yet (hides the meter when empty).
    let isActive: Bool

    private var level: PasswordStrengthLevel { strength.level }

    private var tint: Color {
        switch level {
        case .veryWeak, .weak: return Colors.error
        case .fair: return Colors.warning
        case .strong, .veryStrong: return Colors.success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<PasswordStrengthLevel.allCases.count, id: \.self) { index in
                    Capsule()
                        .fill(isActive && index <= level.rawValue ? tint : Colors.separator.opacity(0.4))
                        .frame(height: 6)
                }
            }
            if isActive {
                Text(level.label)
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password strength")
        .accessibilityValue(isActive ? level.label : "No password entered")
    }
}
