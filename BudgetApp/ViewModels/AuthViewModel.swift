import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var username = ""
    @Published var email = ""
    @Published var password = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var isAuthenticated = false
    @Published var currentUser: AuthUser?
    @Published var loading = false
    @Published var errorMessage: String?

    private var auth: AuthService

    init(baseURL: URL) {
        self.auth = AuthService(baseURL: baseURL)
    }

    func updateBaseURL(_ url: URL) {
        self.auth = AuthService(baseURL: url)
    }

    func checkSession() async {
        loading = true
        isAuthenticated = (try? await auth.verify()) ?? false
        if isAuthenticated {
            do {
                let user = try await auth.getCurrentUser()
                currentUser = user
                print("✅ Session verified for user: \(user.username)")
            } catch {
                print("⚠️ Failed to get current user: \(error)")
            }
        } else {
            currentUser = nil
        }
        loading = false
    }

    func login() async {
        loading = true
        errorMessage = nil
        do {
            try await auth.login(username: username, password: password)
            let user = try await auth.getCurrentUser()
            currentUser = user
            isAuthenticated = true
            // Persist userId and log for debugging
            UserDefaults.standard.set(user.id, forKey: "auth.userId")
            print("✅ User \(user.username) logged in successfully with ID: \(user.id)")
        } catch {
            errorMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    func register() async {
        loading = true
        errorMessage = nil
        do {
            try await auth.register(
                username: username,
                email: email,
                password: password,
                firstName: firstName.isEmpty ? nil : firstName,
                lastName: lastName.isEmpty ? nil : lastName
            )
            let user = try await auth.getCurrentUser()
            currentUser = user
            isAuthenticated = true
            // Persist userId and log for debugging
            UserDefaults.standard.set(user.id, forKey: "auth.userId")
            print("✅ User \(user.username) registered and logged in successfully with ID: \(user.id)")
        } catch {
            errorMessage = (error as? APIError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    func logout() {
        auth.logout()
        isAuthenticated = false
        currentUser = nil
        // Clear persisted user data
        UserDefaults.standard.removeObject(forKey: "auth.userId")
        UserDefaults.standard.removeObject(forKey: "app.selectedCashFlowId")
        print("✅ User logged out successfully")
    }

    // Retrieve stored userId
    func getUserId() -> String? {
        return UserDefaults.standard.string(forKey: "auth.userId")
    }

    // Retrieve stored selected cashFlowId
    func getSelectedCashFlowId() -> String? {
        return UserDefaults.standard.string(forKey: "app.selectedCashFlowId")
    }
}
