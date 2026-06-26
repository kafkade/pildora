import Foundation

// MARK: - App Settings

/// User-configurable app settings surfaced on the profile screen.
public struct AppSettings: Codable, Hashable, Sendable {
    /// Default low-stock threshold applied to new medications.
    public var defaultRefillThreshold: Int
    /// Whether refill reminder notifications are enabled app-wide.
    public var refillRemindersEnabled: Bool
    /// Preferred appearance. `nil` follows the system setting.
    public var preferredAppearance: Appearance

    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case system
        case light
        case dark

        public var displayName: String { rawValue.capitalized }
    }

    public init(
        defaultRefillThreshold: Int = 7,
        refillRemindersEnabled: Bool = true,
        preferredAppearance: Appearance = .system
    ) {
        self.defaultRefillThreshold = defaultRefillThreshold
        self.refillRemindersEnabled = refillRemindersEnabled
        self.preferredAppearance = preferredAppearance
    }

    public static let `default` = AppSettings()
}
