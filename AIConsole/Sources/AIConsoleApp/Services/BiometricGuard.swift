import Foundation
import LocalAuthentication

@MainActor
public final class BiometricGuard {
    public static let shared = BiometricGuard()
    
    private init() {}
    
    /// Checks if device supports biometric authentication (Touch ID)
    public var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Requests biometric authentication with fallback to device passcode
    /// Returns true if authentication succeeds or if biometrics is not available/supported.
    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.localizedFallbackTitle = "使用系统密码"
        
        var error: NSError?
        // First try biometrics
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: reason
                )
            } catch {
                // If biometrics failed or user chose fallback, try device owner authentication
                if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                    do {
                        return try await context.evaluatePolicy(
                            .deviceOwnerAuthentication,
                            localizedReason: reason
                        )
                    } catch {
                        return false
                    }
                }
                return false
            }
        }
        
        // If device has no Touch ID, allow device owner passcode authentication
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            do {
                return try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason
                )
            } catch {
                return false
            }
        }
        
        // If system authentication not configured, pass through
        return true
    }
}
