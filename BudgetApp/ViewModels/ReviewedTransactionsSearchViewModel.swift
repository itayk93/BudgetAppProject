import Combine
import Foundation
import SwiftUI

@MainActor
final class ReviewedTransactionsSearchViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var loading = false
    @Published var processingReversion = false
    @Published var selectedTransactionIDs: Set<String> = []
    @Published var errorMessage: String?
    @Published var actionMessage: String?

    private let service: SupabaseTransactionsReviewService?
    private var lastSuccessfulQuery: String?

    init(service: SupabaseTransactionsReviewService? = nil) {
        self.service = service ?? SupabaseTransactionsReviewService()
        if self.service == nil {
            errorMessage = SupabaseServiceError.missingCredentials.errorDescription
        }
    }

    func search(for query: String?) async {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count >= 3 else {
            transactions = []
            lastSuccessfulQuery = nil
            errorMessage = nil
            return
        }
        guard let service else {
            errorMessage = SupabaseServiceError.missingCredentials.errorDescription
            return
        }
        guard let userID = resolvedUserID() else {
            errorMessage = "לא נמצא user.id. התחבר מחדש כדי לגשת לעסקאות."
            return
        }
        loading = true
        errorMessage = nil
        do {
            let rows = try await service.fetchReviewedTransactions(for: userID, businessName: trimmed)
            transactions = rows
            selectedTransactionIDs.removeAll()
            lastSuccessfulQuery = trimmed
            if rows.isEmpty {
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func refreshLastSearch() async {
        await search(for: lastSuccessfulQuery)
    }

    func revertSelected() async {
        guard !selectedTransactionIDs.isEmpty else { return }
        guard let service else {
            errorMessage = SupabaseServiceError.missingCredentials.errorDescription
            return
        }
        processingReversion = true
        errorMessage = nil
        do {
            try await service.revertTransactionsToPending(transactionIDs: Array(selectedTransactionIDs))
            let count = selectedTransactionIDs.count
            actionMessage = "העברנו \(count) עסקאות חזרה ל־pending"
            selectedTransactionIDs.removeAll()
            await refreshLastSearch()
        } catch {
            errorMessage = error.localizedDescription
        }
        processingReversion = false
    }

    private func resolvedUserID() -> String? {
        let rawValue = KeychainStore.get("user.id")
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
