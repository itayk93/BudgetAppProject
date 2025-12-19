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
    @Published var earliestLoadedMonthLabel: String?
    @Published var isLoadingOlderResults = false
    @Published var canLoadOlderResults = false

    private let service: SupabaseTransactionsReviewService?
    private var lastSuccessfulQuery: String?
    private var loadedStartMonthKey: String?
    private let calendar = Calendar(identifier: .gregorian)
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    private let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
    private let initialMonthWindow = 4
    private let olderChunkMonths = 4

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
        guard self.service != nil else {
            errorMessage = SupabaseServiceError.missingCredentials.errorDescription
            return
        }
        guard resolvedUserID() != nil else {
            errorMessage = "לא נמצא user.id. התחבר מחדש כדי לגשת לעסקאות."
            return
        }
        loading = true
        errorMessage = nil
        canLoadOlderResults = true
        let (startKey, endKey) = initialMonthRange()
        loadedStartMonthKey = startKey
        earliestLoadedMonthLabel = displayLabel(for: startKey)
        defer { loading = false }
        await loadTransactions(rangeStartKey: startKey, rangeEndKey: endKey, for: trimmed, append: false)
        lastSuccessfulQuery = trimmed
    }

    func refreshLastSearch() async {
        await search(for: lastSuccessfulQuery)
    }

    func loadOlderResults() async {
        guard !isLoadingOlderResults, canLoadOlderResults, let currentQuery = lastSuccessfulQuery, let startKey = loadedStartMonthKey else {
            return
        }
        guard let range = olderMonthRange(before: startKey) else {
            canLoadOlderResults = false
            return
        }
        isLoadingOlderResults = true
        defer { isLoadingOlderResults = false }
        await loadTransactions(rangeStartKey: range.startKey, rangeEndKey: range.endKey, for: currentQuery, append: true)
        loadedStartMonthKey = range.startKey
        earliestLoadedMonthLabel = displayLabel(for: range.startKey)
    }

    func revertSelected() async {
        guard !selectedTransactionIDs.isEmpty else { return }
        guard let service = self.service else {
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

    // MARK: - Month helpers

    private func startOfMonth(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func initialMonthRange() -> (startKey: String, endKey: String) {
        let endDate = startOfMonth(for: Date())
        let startDate = calendar.date(byAdding: .month, value: -(initialMonthWindow - 1), to: endDate)!
        return (monthFormatter.string(from: startDate), monthFormatter.string(from: endDate))
    }

    private func olderMonthRange(before key: String) -> (startKey: String, endKey: String)? {
        guard let startDate = monthFormatter.date(from: key) else { return nil }
        let previousMonthEnd = calendar.date(byAdding: .month, value: -1, to: startOfMonth(for: startDate))!
        let previousMonthStart = calendar.date(
            byAdding: .month,
            value: -olderChunkMonths + 1,
            to: startOfMonth(for: previousMonthEnd)
        )!
        return (monthFormatter.string(from: previousMonthStart), monthFormatter.string(from: previousMonthEnd))
    }

    private func displayLabel(for monthKey: String) -> String {
        guard let date = monthFormatter.date(from: monthKey) else { return monthKey }
        return displayFormatter.string(from: date)
    }

    private func loadTransactions(rangeStartKey: String, rangeEndKey: String, for query: String, append: Bool) async {
        guard let service = self.service else { return }
        guard let userID = resolvedUserID() else {
            errorMessage = "לא נמצא user.id. התחבר מחדש כדי לגשת לעסקאות."
            return
        }

        do {
            let rows = try await service.fetchReviewedTransactions(
                for: userID,
                businessName: query,
                limit: 5_000,
                flowMonthFrom: rangeStartKey,
                flowMonthTo: rangeEndKey
            )
            let combined = rows.sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }

            if append {
                let existingIDs = Set(transactions.map { $0.id })
                let newRows = combined.filter { !existingIDs.contains($0.id) }
                transactions.append(contentsOf: newRows)
                transactions.sort {
                    ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast)
                }
            } else {
                transactions = combined
                selectedTransactionIDs.removeAll()
            }

            if transactions.isEmpty {
                errorMessage = nil
            }
            canLoadOlderResults = !combined.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
