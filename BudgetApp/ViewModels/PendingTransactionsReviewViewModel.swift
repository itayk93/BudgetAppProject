import Foundation
import Combine
import SwiftUI

@MainActor
final class PendingTransactionsReviewViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var categories: [TransactionCategory] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var actionMessage: String?
    @Published var processingTransactionID: String?

    private let service: SupabaseTransactionsReviewService?
    private let transactionsService: TransactionsService
    private let lookbackHours: Double
    private let hiddenBusinessReason = "באפליקציה סומן שיהיה נסתר"

    init(
        service: SupabaseTransactionsReviewService? = nil,
        lookbackHours: Double = 168,
        transactionsService: TransactionsService? = nil
    ) {
        self.service = service ?? SupabaseTransactionsReviewService()
        self.lookbackHours = lookbackHours
        self.transactionsService = transactionsService ?? TransactionsService(baseURL: AppConfig.baseURL)
        if self.service == nil {
            self.errorMessage = SupabaseServiceError.missingCredentials.errorDescription
        }
    }

    func refresh() async {
        print("🔄 [DEBUG] Starting refresh in PendingTransactionsReviewViewModel")
        guard let service = service else {
            print("❌ [DEBUG] Service is nil")
            return
        }
        guard let userID = resolvedUserID() else {
            print("❌ [DEBUG] No user ID resolved")
            errorMessage = "לא נמצא user.id. התחבר מחדש כדי למשוך עסקאות מ-Supabase."
            return
        }
        print("🔍 [DEBUG] Using user ID: \(userID)")
        loading = true
        errorMessage = nil
        do {
            async let txs = service.fetchPendingTransactions(for: userID, hoursBack: lookbackHours)
            async let cats = service.fetchCategoryOptions(for: userID)
            let (transactions, categories) = try await (txs, cats)
            print("✅ [DEBUG] Received \(transactions.count) transactions and \(categories.count) categories")
            withAnimation(.easeInOut) {
                self.transactions = transactions
            }
            self.categories = categories
            print("📊 [DEBUG] ViewModel now has \(self.transactions.count) transactions, \(self.categories.count) categories")
        } catch {
            print("❌ [DEBUG] Error during refresh: \(error)")
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    func approve(_ transaction: Transaction) async {
        guard let service = service else { return }
        processingTransactionID = transaction.id
        let index = removeTransaction(transaction)
        do {
            try await service.markReviewed(transactionID: transaction.id)
            actionMessage = "אישרת את \(transaction.business_name ?? "העסקה")"
        } catch {
            restore(transaction, at: index)
            errorMessage = error.localizedDescription
        }
        processingTransactionID = nil
    }

    func reassign(_ transaction: Transaction, to categoryName: String, note: String?) async {
        guard let service = service else { return }
        processingTransactionID = transaction.id
        do {
            try await service.updateCategory(transactionID: transaction.id, categoryName: categoryName, note: note)
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                let trimmedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                let updated = Transaction(
                    id: transaction.id,
                    effectiveCategoryName: trimmedCategory,
                    isIncome: transaction.isIncome,
                    business_name: transaction.business_name,
                    payment_method: transaction.payment_method,
                    createdAtDate: transaction.createdAtDate,
                    currency: transaction.currency,
                    absoluteAmount: transaction.absoluteAmount,
                    notes: note ?? transaction.notes,
                    normalizedAmount: transaction.normalizedAmount,
                    excluded_from_flow: transaction.excluded_from_flow,
                    category_name: trimmedCategory,
                    category: transaction.category,
                    status: transaction.status,
                    user_id: transaction.user_id,
                    suppress_from_automation: transaction.suppress_from_automation,
                    manual_split_applied: transaction.manual_split_applied,
                    reviewed_at: transaction.reviewed_at,
                    source_type: transaction.source_type,
                    date: transaction.date,
                    payment_date: transaction.payment_date,
                    flow_month: transaction.flow_month
                )
                transactions[index] = updated
            }
            actionMessage = "הקטגוריה שונתה ל-\(categoryName)"
        } catch {
            errorMessage = error.localizedDescription
        }
        processingTransactionID = nil
    }

    func reassignForFuture(_ transaction: Transaction, to categoryName: String, note: String?) async {
        guard let service = service else { return }
        guard let businessNameRaw = transaction.business_name?.trimmingCharacters(in: .whitespacesAndNewlines), !businessNameRaw.isEmpty else {
            errorMessage = "אין שם בית עסק לעסקה זו, לא ניתן לשמור קטגוריה קבועה."
            return
        }
        guard let userID = resolvedUserID() else {
            errorMessage = "לא נמצא user.id. התחבר מחדש כדי לשמור קטגוריות עתידיות."
            return
        }
        processingTransactionID = transaction.id
        do {
            try await service.updateCategory(transactionID: transaction.id, categoryName: categoryName, note: note)
            try await service.saveDefaultCategory(for: userID, businessName: businessNameRaw, categoryName: categoryName)
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                let trimmedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                let updated = Transaction(
                    id: transaction.id,
                    effectiveCategoryName: trimmedCategory,
                    isIncome: transaction.isIncome,
                    business_name: transaction.business_name,
                    payment_method: transaction.payment_method,
                    createdAtDate: transaction.createdAtDate,
                    currency: transaction.currency,
                    absoluteAmount: transaction.absoluteAmount,
                    notes: note ?? transaction.notes,
                    normalizedAmount: transaction.normalizedAmount,
                    excluded_from_flow: transaction.excluded_from_flow,
                    category_name: trimmedCategory,
                    category: transaction.category,
                    status: transaction.status,
                    user_id: transaction.user_id,
                    suppress_from_automation: transaction.suppress_from_automation,
                    manual_split_applied: transaction.manual_split_applied,
                    reviewed_at: transaction.reviewed_at,
                    source_type: transaction.source_type,
                    date: transaction.date,
                    payment_date: transaction.payment_date,
                    flow_month: transaction.flow_month
                )
                transactions[index] = updated
            }
            actionMessage = "הקטגוריה תשויך אוטומטית ל-\(businessNameRaw) בעתיד."
        } catch {
            errorMessage = error.localizedDescription
        }
        processingTransactionID = nil
    }

    func move(_ transaction: Transaction, toFlowMonth flowMonth: String) async throws {
        guard let service = service else { return }
        processingTransactionID = transaction.id
        defer { processingTransactionID = nil }
        do {
            try await service.updateFlowMonth(transactionID: transaction.id, flowMonth: flowMonth)
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                let updated = Transaction(
                    id: transaction.id,
                    effectiveCategoryName: transaction.effectiveCategoryName,
                    isIncome: transaction.isIncome,
                    business_name: transaction.business_name,
                    payment_method: transaction.payment_method,
                    createdAtDate: transaction.createdAtDate,
                    currency: transaction.currency,
                    absoluteAmount: transaction.absoluteAmount,
                    notes: transaction.notes,
                    normalizedAmount: transaction.normalizedAmount,
                    excluded_from_flow: transaction.excluded_from_flow,
                    category_name: transaction.category_name,
                    category: transaction.category,
                    status: transaction.status,
                    user_id: transaction.user_id,
                    suppress_from_automation: transaction.suppress_from_automation,
                    manual_split_applied: transaction.manual_split_applied,
                    reviewed_at: transaction.reviewed_at,
                    source_type: transaction.source_type,
                    date: transaction.date,
                    payment_date: transaction.payment_date,
                    flow_month: flowMonth
                )
                transactions[index] = updated
            }
            actionMessage = "העברנו את העסקה לחודש \(flowMonth)"
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func delete(_ transaction: Transaction) async {
        guard let service = service else { return }
        processingTransactionID = transaction.id
        let index = removeTransaction(transaction)
        do {
            try await service.delete(transactionID: transaction.id)
            actionMessage = "העסקה נמחקה"
        } catch {
            restore(transaction, at: index)
            errorMessage = error.localizedDescription
        }
        processingTransactionID = nil
    }

    func hideBusiness(_ transaction: Transaction) async {
        guard let service = service else { return }
        guard let businessNameRaw = transaction.business_name?.trimmingCharacters(in: .whitespacesAndNewlines), !businessNameRaw.isEmpty else {
            errorMessage = "אין שם בית עסק לעסקה זו, לא ניתן להסתיר."
            return
        }
        let transactionUserID = transaction.user_id?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedID: String?
        if let transactionUserID, !transactionUserID.isEmpty {
            resolvedID = transactionUserID
        } else {
            resolvedID = resolvedUserID()
        }
        guard let userID = resolvedID else {
            errorMessage = "לא נמצא מזהה משתמש עבור העסקה הזו. התחבר מחדש כדי להסתיר בתי עסק."
            return
        }
        processingTransactionID = transaction.id
        let index = removeTransaction(transaction)
        do {
            print("🕵️‍♂️ [HIDE-BUSINESS] user_id=\(userID), business=\(businessNameRaw)")
            try await service.hideBusiness(for: userID, businessName: businessNameRaw, reason: hiddenBusinessReason)
            try await service.delete(transactionID: transaction.id)
            actionMessage = "\(businessNameRaw) הוסתר והעסקה נמחקה מהתזרים."
        } catch {
            print("❌ [HIDE-BUSINESS] Failed to hide \(businessNameRaw). user_id=\(userID) error=\(error)")
            if error.localizedDescription.contains("duplicate key value") {
                actionMessage = "\(businessNameRaw) כבר מסומן כנסתר."
            } else if error.localizedDescription.contains("is not present in table \"users\"") {
                actionMessage = "אי אפשר להסתיר כי Supabase מכיל רשומות ישנות עם user_id שונה (6fd5...). מחק או עדכן את השלישייה הישנה ב-hidden_business_names ואז הוסף שוב."
            } else {
                restore(transaction, at: index)
                errorMessage = error.localizedDescription
            }
        }
        processingTransactionID = nil
    }

    func saveNote(_ text: String, for transactionID: String) async -> Bool {
        guard service != nil else { return false }

        let copied = String(text) // force a new backing buffer
        let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedNote: String? = trimmed.isEmpty ? nil : trimmed

        processingTransactionID = transactionID
        defer { processingTransactionID = nil }

        do {
            try await PendingTransactionNotesService.updateNoteAsync(
                transactionID: transactionID,
                note: sanitizedNote
            )

            if let index = transactions.firstIndex(where: { $0.id == transactionID }) {
                var current = transactions[index]
                current.notes = sanitizedNote
                transactions[index] = current
            }

            actionMessage = sanitizedNote == nil ? "הערה הוסרה" : "הערה נשמרה"
            return true
        } catch {
            errorMessage = error.localizedDescription
            actionMessage = "שגיאה בשמירת ההערה"
            return false
        }
    }

    // Updated function signature to accept individual parameters instead of struct
    // This prevents EXC_BAD_ACCESS memory corruption issues in async contexts
    func splitTransaction(
        _ transaction: Transaction,
        originalTransactionId: String,
        splits: [SplitTransactionEntry]
    ) async throws {
        processingTransactionID = transaction.id
        do {
            // Call the updated service method with individual parameters
            try await transactionsService.splitTransaction(
                originalTransactionId: originalTransactionId,
                splits: splits
            )
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                let updated = Transaction(
                    id: transaction.id,
                    effectiveCategoryName: transaction.effectiveCategoryName,
                    isIncome: transaction.isIncome,
                    business_name: transaction.business_name,
                    payment_method: transaction.payment_method,
                    createdAtDate: transaction.createdAtDate,
                    currency: transaction.currency,
                    absoluteAmount: transaction.absoluteAmount,
                    notes: transaction.notes,
                    normalizedAmount: transaction.normalizedAmount,
                    excluded_from_flow: transaction.excluded_from_flow,
                    category_name: transaction.category_name,
                    category: transaction.category,
                    status: transaction.status,
                    user_id: transaction.user_id,
                    suppress_from_automation: transaction.suppress_from_automation,
                    manual_split_applied: true,
                    reviewed_at: transaction.reviewed_at,
                    source_type: transaction.source_type,
                    date: transaction.date,
                    payment_date: transaction.payment_date,
                    flow_month: transaction.flow_month
                )
                transactions[index] = updated
            }
            actionMessage = "העסקה פוצלה בהצלחה"
        } catch {
            processingTransactionID = nil
            errorMessage = error.localizedDescription
            throw error
        }
        processingTransactionID = nil
    }

    private func resolvedUserID() -> String? {
        let rawValue = KeychainStore.get("user.id")
        print("🔑 [DEBUG] Keychain user.id raw value: \(rawValue ?? "nil")")
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            print("❌ [DEBUG] No valid user ID found in Keychain")
            return nil
        }
        print("✅ [DEBUG] Resolved user ID: \(value)")
        return value
    }

    @discardableResult
    private func removeTransaction(_ transaction: Transaction) -> Int? {
        guard let idx = transactions.firstIndex(where: { $0.id == transaction.id }) else { return nil }
        _ = withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            transactions.remove(at: idx)
        }
        return idx
    }

    private func restore(_ transaction: Transaction, at index: Int?) {
        guard let index else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            transactions.insert(transaction, at: index)
        }
    }

}
