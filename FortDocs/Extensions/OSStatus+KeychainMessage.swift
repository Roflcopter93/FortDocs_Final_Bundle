import Foundation
import Security

/// Provides human‑readable descriptions for Keychain `OSStatus` error codes.
///
/// The system Keychain APIs return low level `OSStatus` values to indicate
/// specific failure conditions.  Presenting these raw numeric codes directly
/// to end users results in confusing and non‑actionable messages.  This
/// extension maps commonly encountered Keychain statuses to friendly,
/// descriptive phrases.  Any unknown value falls back to a generic message
/// that still includes the underlying code for troubleshooting.
extension OSStatus {
    /// Returns a user friendly error message for the current status.
    var keychainErrorMessage: String {
        switch self {
        case errSecItemNotFound:
            return "The requested item could not be found in the keychain."
        case errSecDuplicateItem:
            return "An item with the same identifier already exists in the keychain."
        case errSecAuthFailed:
            return "Authentication failed while accessing secure data."
        case errSecDecode:
            return "Unable to decode the keychain item. The data may be corrupted."
        case errSecInteractionNotAllowed:
            return "Keychain interaction is not allowed at this time."
        case errSecInvalidItemRef:
            return "The keychain item reference is invalid."
        case errSecNotAvailable:
            return "The keychain is currently unavailable."
        default:
            // Provide a generic fallback that still exposes the numeric code for
            // debugging.  This message should encourage users to retry.
            return "An unexpected error occurred while accessing secure data (code \(self)). Please try again."
        }
    }
}