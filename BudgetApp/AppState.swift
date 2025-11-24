import Foundation
import Combine
import SwiftUI

final class AppState: ObservableObject {
    @Published var baseURL: URL
    var apiClient: AppAPIClient
    var cashFlowDashboardVM: CashFlowDashboardViewModel
    var pendingTransactionsVM: PendingTransactionsReviewViewModel
    private let defaultsKey = "api.baseURL"

    init() {
        let initialBaseURL = AppConfig.baseURL
        self.baseURL = initialBaseURL
        AppLogger.log("AppAPIClient initialized with baseURL: \(initialBaseURL.absoluteString)")
        self.apiClient = AppAPIClient(baseURL: initialBaseURL)
        self.cashFlowDashboardVM = CashFlowDashboardViewModel(apiClient: self.apiClient)
        self.pendingTransactionsVM = PendingTransactionsReviewViewModel()
    }

    func setBaseURL(_ url: URL) {
        baseURL = url
        UserDefaults.standard.set(url.absoluteString, forKey: defaultsKey)
        // Re-initialize apiClient and cashFlowDashboardVM with the new baseURL
        self.apiClient = AppAPIClient(baseURL: url)
        self.cashFlowDashboardVM = CashFlowDashboardViewModel(apiClient: self.apiClient)
        self.pendingTransactionsVM = PendingTransactionsReviewViewModel()
        NotificationCenter.default.post(name: .authChanged, object: nil) // nudge listeners
    }

    @discardableResult
    func autodetectLocalhostPort() async -> URL? {
        // Try :5001 then :4000
        let candidates = [
            URL(string: "http://localhost:5001/api")!,
            URL(string: "http://localhost:4000/api")!
        ]
        for url in candidates {
            if await isHealthy(base: url) {
                if url != baseURL { setBaseURL(url) }
                return url
            }
        }
        return nil
    }

    private func isHealthy(base: URL) async -> Bool {
        var req = URLRequest(url: base.appendingPathComponent("health"))
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 2.0
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse { return (200..<300).contains(http.statusCode) }
            return false
        } catch { return false }
    }
}