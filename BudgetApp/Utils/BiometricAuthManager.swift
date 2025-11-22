import Foundation
import LocalAuthentication
import Combine

enum BiometricAuthError: Error {
    case biometryNotAvailable
    case biometryNotEnrolled
    case biometryLockout
    case authenticationFailed
    case userCancel
    case userFallback
    case cancelledBySystem
    case other

    var localizedDescription: String {
        switch self {
        case .biometryNotAvailable:
            return "זיהוי ביומטרי אינו זמין במכשיר זה"
        case .biometryNotEnrolled:
            return "לא הוגדר זיהוי ביומטרי במכשיר זה"
        case .biometryLockout:
            return "ה_DEVICE נעול вследствие ניסיונות כושלים רבים. אנא השתמש בסיסמה."
        case .authenticationFailed:
            return "אימות זיהוי כושל"
        case .userCancel:
            return "המשתמש ביטל את האימות"
        case .userFallback:
            return "המשתמש בחר方式进行 חלופי"
        case .cancelledBySystem:
            return "האימות בוטל על ידי המערכת"
        case .other:
            return "שגיאה לא ידועה"
        }
    }
}

class BiometricAuthManager: ObservableObject {
    static let shared = BiometricAuthManager()

    private init() {}

    func authenticate(reason: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let context = LAContext()
            var error: NSError?

            // Check if biometry is available
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                let authError = mapLAError(nsError: error)
                continuation.resume(throwing: authError)
                return
            }

            // Perform biometric authentication
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evaluateError in
                if success {
                    continuation.resume()
                } else {
                    let authError = self.mapLAError(nsError: evaluateError as? NSError)
                    continuation.resume(throwing: authError)
                }
            }
        }
    }

    private func mapLAError(nsError: NSError?) -> BiometricAuthError {
        guard let error = nsError else {
            return .other
        }

        let code = error.code

        switch code {
        case LAError.biometryNotAvailable.rawValue:
            return .biometryNotAvailable
        case LAError.biometryNotEnrolled.rawValue:
            return .biometryNotEnrolled
        case LAError.biometryLockout.rawValue:
            return .biometryLockout
        case LAError.authenticationFailed.rawValue:
            return .authenticationFailed
        case LAError.userCancel.rawValue:
            return .userCancel
        case LAError.userFallback.rawValue:
            return .userFallback
        case LAError.systemCancel.rawValue:
            return .cancelledBySystem
        default:
            return .other
        }
    }

    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
}