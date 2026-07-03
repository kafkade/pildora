import Foundation

// MARK: - Biometric availability

/// The kind of biometric the current device offers, so the UI can use the right
/// name and icon ("Face ID" vs "Touch ID").
public enum BiometricKind: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    case none

    /// The user-facing name.
    public var displayName: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return "Biometric unlock"
        }
    }

    /// An SF Symbol representing this biometric.
    public var systemImage: String {
        switch self {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock"
        }
    }

    /// Whether any biometric is available.
    public var isAvailable: Bool { self != .none }
}

// MARK: - Seam

/// Abstracts `LocalAuthentication` so the flow can be tested without biometric
/// hardware or entitlements. The production conformer
/// (``LocalAuthenticationBiometrics``) wraps `LAContext`; tests use a fake.
public protocol BiometricAuthenticating: Sendable {
    /// What biometric, if any, is available and enrolled on this device.
    func availableBiometric() -> BiometricKind
    /// Prompt the user to authenticate, to confirm enrolment during onboarding.
    /// Returns `true` on success. Throwing/`false` should leave the opt-in off.
    func authenticate(reason: String) async -> Bool
}
