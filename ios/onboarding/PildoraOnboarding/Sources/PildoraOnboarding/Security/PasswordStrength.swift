import Foundation

// MARK: - Strength level

/// A five-step strength rating for a master password, from `veryWeak` (0) to
/// `veryStrong` (4). Mirrors the zxcvbn 0–4 scale so the meter reads the way
/// users expect. Color/label mapping lives in the meter view.
public enum PasswordStrengthLevel: Int, CaseIterable, Comparable, Sendable {
    case veryWeak = 0
    case weak = 1
    case fair = 2
    case strong = 3
    case veryStrong = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// A short, user-facing label.
    public var label: String {
        switch self {
        case .veryWeak: return "Very weak"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        case .veryStrong: return "Very strong"
        }
    }
}

// MARK: - Strength result

/// The outcome of evaluating a candidate master password.
public struct PasswordStrength: Equatable, Sendable {
    /// Estimated entropy in bits after pattern penalties.
    public let entropyBits: Double
    /// The bucketed strength level derived from `entropyBits`.
    public let level: PasswordStrengthLevel
    /// Human-readable reasons the password is weak (empty when none apply).
    public let warnings: [String]
    /// Concrete, actionable ways to strengthen the password.
    public let suggestions: [String]

    public init(
        entropyBits: Double,
        level: PasswordStrengthLevel,
        warnings: [String],
        suggestions: [String]
    ) {
        self.entropyBits = entropyBits
        self.level = level
        self.warnings = warnings
        self.suggestions = suggestions
    }

    /// The empty-password baseline.
    public static let empty = PasswordStrength(
        entropyBits: 0,
        level: .veryWeak,
        warnings: [],
        suggestions: []
    )
}

// MARK: - Evaluator

/// A dependency-free, zxcvbn-style password strength estimator.
///
/// It estimates entropy from the character classes used and the length, then
/// applies penalties for the patterns that make passwords weak in practice:
/// known-common passwords, dictionary words, sequential runs (`abcd`, `1234`),
/// keyboard walks (`qwerty`), and long character repeats. The penalized entropy
/// is bucketed into a ``PasswordStrengthLevel``.
///
/// This is intentionally lighter than the full zxcvbn dataset — it ships no
/// large dictionary — but it catches the weak passwords onboarding must reject
/// and runs instantly on every keystroke. The issue calls for "zxcvbn or
/// similar"; this is the "similar".
public enum PasswordStrengthEvaluator {

    /// The most common passwords, normalized to lowercase. A match collapses the
    /// score to `veryWeak` regardless of length.
    private static let commonPasswords: Set<String> = [
        "password", "passw0rd", "password1", "123456", "12345678", "123456789",
        "qwerty", "qwertyuiop", "abc123", "111111", "123123", "letmein",
        "welcome", "admin", "iloveyou", "monkey", "dragon", "sunshine",
        "princess", "football", "baseball", "trustno1", "master", "login",
        "starwars", "hello", "whatever", "superman", "batman", "changeme",
    ]

    /// Character sequences used to detect straight runs (in either direction).
    private static let sequences = [
        "abcdefghijklmnopqrstuvwxyz",
        "0123456789",
        "qwertyuiop",
        "asdfghjkl",
        "zxcvbnm",
    ]

    /// Evaluate `password`, returning its entropy, level, warnings and tips.
    public static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return .empty }

        var warnings: [String] = []
        var suggestions: [String] = []

        let lower = password.lowercased()
        let chars = Array(password)
        let length = chars.count

        // 1. Base entropy from the character-class pool size.
        let poolSize = characterPoolSize(chars)
        var entropy = Double(length) * log2(Double(max(poolSize, 1)))

        // 2. Known-common password → collapse to near-zero.
        if commonPasswords.contains(lower) {
            warnings.append("This is one of the most common passwords.")
            suggestions.append("Use a longer, unpredictable passphrase of several unrelated words.")
            return PasswordStrength(
                entropyBits: min(entropy, 8),
                level: .veryWeak,
                warnings: warnings,
                suggestions: suggestions
            )
        }
        if commonPasswords.contains(where: { lower.contains($0) }) {
            entropy *= 0.55
            warnings.append("Contains a very common word or password.")
            suggestions.append("Avoid common words like “password” or “qwerty”.")
        }

        // 3. Long single-character repeats (aaaa, 1111).
        if let runLength = longestRepeat(chars), runLength >= 3 {
            entropy -= Double(runLength) * 2
            warnings.append("Repeats the same character several times.")
            suggestions.append("Avoid repeated characters like “aaaa”.")
        }

        // 4. Sequential runs / keyboard walks (abcd, 1234, qwerty).
        if containsSequence(lower, minRun: 4) {
            entropy -= 12
            warnings.append("Contains a predictable sequence.")
            suggestions.append("Avoid sequences like “abcd”, “1234”, or “qwerty”.")
        }

        // 5. Nudge toward variety and length.
        if length < 12 {
            suggestions.append("Use at least 12 characters — longer is stronger.")
        }
        if characterPoolSize(chars) <= 26 {
            suggestions.append("Mix upper- and lower-case letters, numbers, and symbols.")
        }

        entropy = max(entropy, 0)
        return PasswordStrength(
            entropyBits: entropy,
            level: level(forEntropy: entropy),
            warnings: warnings,
            suggestions: dedup(suggestions)
        )
    }

    // MARK: Scoring

    /// Bucket entropy into the 0–4 scale.
    static func level(forEntropy bits: Double) -> PasswordStrengthLevel {
        switch bits {
        case ..<28: return .veryWeak
        case ..<40: return .weak
        case ..<60: return .fair
        case ..<80: return .strong
        default: return .veryStrong
        }
    }

    // MARK: Helpers

    private static func characterPoolSize(_ chars: [Character]) -> Int {
        var pool = 0
        var hasLower = false, hasUpper = false, hasDigit = false, hasSymbol = false, hasOther = false
        for ch in chars {
            if ch.isLowercase { hasLower = true }
            else if ch.isUppercase { hasUpper = true }
            else if ch.isNumber { hasDigit = true }
            else if ch.isASCII { hasSymbol = true }
            else { hasOther = true }
        }
        if hasLower { pool += 26 }
        if hasUpper { pool += 26 }
        if hasDigit { pool += 10 }
        if hasSymbol { pool += 33 }
        if hasOther { pool += 40 }
        return pool
    }

    private static func longestRepeat(_ chars: [Character]) -> Int? {
        guard !chars.isEmpty else { return nil }
        var longest = 1, current = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i - 1] {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private static func containsSequence(_ lower: String, minRun: Int) -> Bool {
        let hay = Array(lower)
        guard hay.count >= minRun else { return false }
        for seq in sequences {
            let s = Array(seq)
            let reversed = Array(seq.reversed())
            if hasRun(hay, from: s, minRun: minRun) || hasRun(hay, from: reversed, minRun: minRun) {
                return true
            }
        }
        return false
    }

    private static func hasRun(_ hay: [Character], from seq: [Character], minRun: Int) -> Bool {
        guard seq.count >= minRun else { return false }
        for start in 0...(seq.count - minRun) {
            let window = String(seq[start..<start + minRun])
            if String(hay).contains(window) { return true }
        }
        return false
    }

    private static func dedup(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
