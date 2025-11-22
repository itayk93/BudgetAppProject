import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isAuthenticated: Bool = (KeychainStore.get("auth.token") != nil)

    var body: some View {
        Group {
            if isAuthenticated {
                CashflowCardsView()
            } else {
                LoginView()
            }
        }
        .task { await verifyTokenAndRedirectIfNeeded() }
        .onChange(of: appState.baseURL) { _, _ in
            Task { await verifyTokenAndRedirectIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .authChanged)) { _ in
            // Update auth state when notifications fire (login/logout/session changes)
            let hasToken = KeychainStore.get("auth.token") != nil
            if hasToken != isAuthenticated {
                isAuthenticated = hasToken
            }
        }
    }
    
    private func verifyTokenAndRedirectIfNeeded() async {
        guard KeychainStore.get("auth.token") != nil else { 
            await MainActor.run { isAuthenticated = false }
            return 
        }
        do {
            let ok = try await AuthService(baseURL: appState.baseURL).verify()
            await MainActor.run { isAuthenticated = ok }
        } catch {
            KeychainStore.remove("auth.token")
            await MainActor.run { isAuthenticated = false }
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}