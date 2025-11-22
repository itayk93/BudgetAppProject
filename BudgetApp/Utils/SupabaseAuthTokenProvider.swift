import Foundation

enum SupabaseAuthTokenProvider {
    static func currentAccessToken() -> String? {
        return KeychainStore
            .get("user.access_token")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func setCurrentAccessToken(_ token: String) -> Bool {
        return KeychainStore.set(token, for: "user.access_token")
    }
    
    static func clearAccessToken() {
        KeychainStore.remove("user.access_token")
    }
}