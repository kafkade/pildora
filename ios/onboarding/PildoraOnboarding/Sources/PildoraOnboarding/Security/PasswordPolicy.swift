import Foundation

// MARK: - Requirement

/// A single, individually-checkable password rule, surfaced in the UI as a
/// live checklist so the user sees exactly what is still missing.
public struct PasswordRequirement: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case minLength
        case minStrength
        case matchesConfirmation
    }

    public let id: Kind
    /// The requirement text (e.g. "At least 10 characters").
    public let text: String
    /// Whether the current input satisfies this rule.
    public let isSatisfied: Bool

    public init(id: Kind, text: String, isSatisfied: Bool) {
        self.id = id
        self.text = text
        self.isSatisfied = isSatisfied
    }
}

// MARK: - Policy

/// The minimum bar a master password must clear before onboarding will accept
/// it. Enforced independently of the strength meter so a fancy-looking but short
/// password is still rejected.
public struct PasswordPolicy: Sendable {
    /// Minimum character count.
    public let minLength: Int
    /// Minimum acceptable strength level.
    public let minLevel: PasswordStrengthLevel

    public init(minLength: Int = 10, minLevel: PasswordStrengthLevel = .fair) {
        self.minLength = minLength
        self.minLevel = minLevel
    }

    /// The default policy: ≥ 10 characters and at least a `fair` rating.
    public static let standard = PasswordPolicy()

    /// Evaluate every requirement for the current password + confirmation.
    ///
    /// - Parameters:
    ///   - password: The candidate password.
    ///   - confirmation: The re-typed confirmation. Pass `nil` to omit the
    ///     match check (e.g. before the confirm field is shown).
    ///   - strength: The already-computed strength (avoids recomputing).
    public func requirements(
        password: String,
        confirmation: String?,
        strength: PasswordStrength
    ) -> [PasswordRequirement] {
        var reqs: [PasswordRequirement] = [
            PasswordRequirement(
                id: .minLength,
                text: "At least \(minLength) characters",
                isSatisfied: password.count >= minLength
            ),
            PasswordRequirement(
                id: .minStrength,
                text: "Strength: \(minLevel.label) or better",
                isSatisfied: !password.isEmpty && strength.level >= minLevel
            ),
        ]
        if let confirmation {
            reqs.append(
                PasswordRequirement(
                    id: .matchesConfirmation,
                    text: "Both entries match",
                    isSatisfied: !confirmation.isEmpty && password == confirmation
                )
            )
        }
        return reqs
    }

    /// Whether `password` (and, when provided, its `confirmation`) satisfies
    /// every requirement.
    public func isAcceptable(
        password: String,
        confirmation: String?,
        strength: PasswordStrength
    ) -> Bool {
        requirements(password: password, confirmation: confirmation, strength: strength)
            .allSatisfy(\.isSatisfied)
    }
}
