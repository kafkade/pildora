import Foundation

/// A configurable fake ``BiometricAuthenticating`` for tests and previews.
public struct StubBiometrics: BiometricAuthenticating {
    private let kind: BiometricKind
    private let authResult: Bool

    public init(kind: BiometricKind = .faceID, authResult: Bool = true) {
        self.kind = kind
        self.authResult = authResult
    }

    public func availableBiometric() -> BiometricKind { kind }
    public func authenticate(reason: String) async -> Bool { authResult }
}

#if canImport(LocalAuthentication)
import LocalAuthentication

/// The production ``BiometricAuthenticating`` backed by `LAContext`.
///
/// A fresh `LAContext` is created per query so cached evaluation state never
/// leaks between the availability check and the authentication prompt.
public struct LocalAuthenticationBiometrics: BiometricAuthenticating {
    public init() {}

    public func availableBiometric() -> BiometricKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
#endif
