import Foundation

// TransactionCategory is defined in Models/Transaction.swift - will be available across the target

public struct BusinessCategoryDefault: Decodable {
    public let id: String
    public let user_id: String
    public let business_name: String
    public let category_name: String
}


struct SupabaseCredentials {
    let restURL: URL
    let apiKey: String

    static func current() -> SupabaseCredentials? {
        guard
            let rawURL = SupabaseCredentials.value(for: "SUPABASE_URL"),
            let baseURL = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            AppLogger.log("❌ [SUPABASE CREDS] No SUPABASE_URL found")
            return nil
        }
        if SupabaseCredentials.isPlaceholderURL(rawURL) {
            AppLogger.log("❌ [SUPABASE CREDS] SUPABASE_URL is still a placeholder (\(rawURL)). Please set the real project URL.")
            return nil
        }
        let rest = baseURL.appendingPathComponent("rest/v1")

        let secret  = SupabaseCredentials.value(for: "SUPABASE_SECRET")
                    ?? SupabaseCredentials.value(for: "SUPABASE_SECRET_KEY")  // Alternative name to match your scheme
        let service = SupabaseCredentials.value(for: "SUPABASE_SERVICE_ROLE_KEY")
        let anon    = SupabaseCredentials.value(for: "SUPABASE_ANON_KEY")

        // Prefer the first non-placeholder key in this order: SECRET -> SERVICE_ROLE -> ANON
        let candidates = [secret, service, anon]
        let key = candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !SupabaseCredentials.isPlaceholderKey($0) }

        guard let key, !key.isEmpty else {
            AppLogger.log("❌ [SUPABASE CREDS] No API key found (SECRET / SERVICE_ROLE / ANON all missing)")
            return nil
        }

        let keySource: String
        if let secret, !SupabaseCredentials.isPlaceholderKey(secret) {
            keySource = "SECRET"
        } else if let service, !SupabaseCredentials.isPlaceholderKey(service) {
            keySource = "SERVICE_ROLE"
        } else if let anon, !SupabaseCredentials.isPlaceholderKey(anon) {
            keySource = "ANON"
        } else {
            keySource = "UNKNOWN"
        }
        AppLogger.log("🔐 [SUPABASE CREDS] Using key from \(keySource), prefix=\(key.prefix(8))")

        return SupabaseCredentials(restURL: rest, apiKey: key)
    }

    private static func value(for key: String) -> String? {
        // Highest priority: process env
        if let env = ProcessInfo.processInfo.environment[key],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env
        }

        // Next: .env (if bundled or copied in)
        if let dotenv = DotEnv.shared.get(key),
           !dotenv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return dotenv
        }

        // Finally: Info.plist, but ignore known placeholders
        if let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if key == "SUPABASE_URL", SupabaseCredentials.isPlaceholderURL(trimmed) {
                return nil
            }
            if key.hasPrefix("SUPABASE_"), SupabaseCredentials.isPlaceholderKey(trimmed) {
                return nil
            }
            return trimmed
        }

        return nil
    }
}

private extension SupabaseCredentials {
    static func isPlaceholderURL(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.contains("your-project.supabase.co") || lower.contains("your_project") || lower.contains("your-project")
    }

    static func isPlaceholderKey(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("your_") || trimmed.contains("service_role_or_secret_key_here") || trimmed.contains("public_anon_key_here")
    }
}

enum SupabaseServiceError: LocalizedError {
    case missingCredentials
    case invalidURL
    case invalidResponse
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "חסרים פרטי התחברות ל-Supabase. ודא שהגדרת SUPABASE_URL ו-SUPABASE_SECRET בסביבת ההרצה."
        case .invalidURL:
            return "קישור Supabase לא תקין."
        case .invalidResponse:
            return "התשובה מהשרת לא תקינה."
        case .server(let message):
            return "שגיאה מ-Supabase: \(message)"
        }
    }
}

final class SupabaseTransactionsReviewService {
    private let credentials: SupabaseCredentials
    private let session: URLSession
    private let decoder: JSONDecoder
    private let isoFormatter: ISO8601DateFormatter

    init?(session: URLSession = .shared) {
        guard let creds = SupabaseCredentials.current() else { return nil }
        self.credentials = creds
        self.session = session
        self.decoder = JSONDecoder()
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    init(credentials: SupabaseCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
        self.decoder = JSONDecoder()
        self.isoFormatter = ISO8601DateFormatter()
        self.isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func fetchPendingTransactions(for userID: String, hoursBack: Double = 168) async throws -> [Transaction] {
        AppLogger.log("🔍 [DEBUG] Fetching pending transactions for user_id: \(userID), looking back \(hoursBack) hours")
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-(hoursBack * 3600))

        // Format the cutoff date for database query
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cutoffDateString = dateFormatter.string(from: cutoffDate)

        AppLogger.log("🔍 [DEBUG] Current time: \(dateFormatter.string(from: now)), Cutoff time: \(cutoffDateString)")

        // Query with user_id, status, and created_at filters
        let query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "status", value: "eq.pending"),
            URLQueryItem(name: "reviewed_at", value: "is.null"),
            URLQueryItem(name: "created_at", value: "gte.\(cutoffDateString)"), // Filter for last week at database level
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "200")
        ]

        AppLogger.log("🔍 [DEBUG] Fetching with query: \(query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: ", "))")

        AppLogger.log("🔍 [DEBUG] Querying 'bank_scraper_pending_transactions' table directly")
        let data = try await request(path: "bank_scraper_pending_transactions", queryItems: query)
        AppLogger.log("🔍 [DEBUG] Raw response data length: \(data.count) bytes")
        if let jsonString = String(data: data, encoding: .utf8) {
            AppLogger.log("🔍 [DEBUG] Raw JSON response (first 300 chars): \(jsonString.prefix(300))")
        }

        let rows = try decoder.decode([Transaction].self, from: data)
        AppLogger.log("🔍 [DEBUG] Raw decode returned \(rows.count) transactions")
        let filteredRows = filterAutomatedTransactions(rows)
        return filteredRows
    }

    func fetchCategoryOptions(for userID: String) async throws -> [TransactionCategory] {
        AppLogger.log("🔍 [DEBUG] Fetching category options for user_id: \(userID)")
        struct CategoryOrderRow: Decodable {
            let id: String
            let category_name: String?
            let display_order: Int?
        }

        let query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id,category_name,display_order"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "order", value: "display_order.asc"),
            URLQueryItem(name: "limit", value: "1000")
        ]
        AppLogger.log("🔍 [DEBUG] Fetching categories with query: \(query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: ", "))")

        let supabaseCategories: [TransactionCategory]
        do {
            let data = try await request(path: "category_order", queryItems: query)
            let rows = try decoder.decode([CategoryOrderRow].self, from: data)
            AppLogger.log("🔍 [DEBUG] Raw category decode returned \(rows.count) rows")
            supabaseCategories = rows.compactMap { row -> TransactionCategory? in
                guard let name = row.category_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                    return nil
                }
                let displayOrder = row.display_order ?? Int.max
                return TransactionCategory(id: row.id, name: name, displayOrder: displayOrder)
            }
        } catch {
            AppLogger.log("❌ [DEBUG] Failed to fetch categories from Supabase: \(error). Trying backend fallback.")
            let fallback = await fetchCategoriesFromBackend()
            if !fallback.isEmpty {
                return fallback
            }
            throw error
        }

        let sortedSupabase = sortCategories(supabaseCategories)
        AppLogger.log("🔍 [DEBUG] Supabase categories count after sorting: \(sortedSupabase.count)")

        // If Supabase returned only a handful of categories, merge with backend list
        if sortedSupabase.count < 3 {
            AppLogger.log("⚠️ [DEBUG] Supabase returned few categories (\(sortedSupabase.count)). Fetching fallback from backend.")
            let fallback = await fetchCategoriesFromBackend()
            guard !fallback.isEmpty else {
                return sortedSupabase
            }
            let existingNames = Set(sortedSupabase.map { $0.name })
            let merged = sortedSupabase + fallback.filter { !existingNames.contains($0.name) }
            let finalList = sortCategories(merged)
            AppLogger.log("✅ [DEBUG] Returning merged category list: \(finalList.count) total")
            return finalList
        }

        return sortedSupabase
    }

    func fetchReviewedTransactions(
        for userID: String,
        businessName searchTerm: String?,
        limit: Int = 1_000_000,
        flowMonthFrom: String? = nil,
        flowMonthTo: String? = nil
    ) async throws -> [Transaction] {
        AppLogger.log("🔍 [DEBUG] Fetching reviewed transactions for user_id: \(userID)")
        var query: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "status", value: "eq.reviewed"),
            URLQueryItem(name: "order", value: "payment_date.desc"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]

        if let from = flowMonthFrom {
            query.append(URLQueryItem(name: "flow_month", value: "gte.\(from)"))
        }
        if let to = flowMonthTo {
            query.append(URLQueryItem(name: "flow_month", value: "lte.\(to)"))
        }

        if let term = searchTerm?.trimmingCharacters(in: .whitespacesAndNewlines), !term.isEmpty {
            let ilike = "ilike.*\(term)*"
            query.append(URLQueryItem(name: "business_name", value: ilike))
            AppLogger.log("🔍 [DEBUG] Applying business_name filter: \(ilike)")
        }

        AppLogger.log("🔍 [DEBUG] Fetching with query: \(query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: ", "))")

        let pendingData = try await request(path: "bank_scraper_pending_transactions", queryItems: query)
        let pendingRows = try decoder.decode([Transaction].self, from: pendingData)
        AppLogger.log("🔍 [DEBUG] Raw decode returned \(pendingRows.count) reviewed transactions from 'bank_scraper_pending_transactions'")

        var combinedRows = pendingRows
        do {
            let transactionsData = try await request(path: "transactions", queryItems: query)
            let transactionsRows = try decoder.decode([Transaction].self, from: transactionsData)
            AppLogger.log("🔍 [DEBUG] Also fetched \(transactionsRows.count) rows from 'transactions' table")
            combinedRows.append(contentsOf: transactionsRows)
        } catch {
            AppLogger.log("⚠️ [DEBUG] Failed to fetch reviewed rows from 'transactions' table: \(error.localizedDescription)")
        }

        let filtered = filterAutomatedTransactions(combinedRows)
        return filtered.sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
    }

    func revertTransactionsToPending(transactionIDs: [String]) async throws {
        guard !transactionIDs.isEmpty else { return }
        AppLogger.log("⚙️ [DEBUG] Reverting \(transactionIDs.count) transactions to pending")
        let payload = TransactionUpdatePayload(
            category_name: nil,
            effective_category_name: nil,
            status: "pending",
            reviewed_at: nil,
            notes: nil,
            flow_month: nil
        )
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        for id in transactionIDs {
            let query = [URLQueryItem(name: "id", value: "eq.\(id)")]
            let table = tableName(for: id)
            _ = try await request(
                path: table,
                method: "PATCH",
                queryItems: query,
                body: body,
                prefer: "return=minimal"
            )
        }
    }

    func markReviewed(transaction: Transaction, categoryName: String? = nil, note: String? = nil, cashFlowID: String) async throws {
        let rawCategory = categoryName ?? transaction.effectiveCategoryName
        let trimmedCategory = rawCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCategory = trimmedCategory.isEmpty ? nil : trimmedCategory

        let existingIDs = try await fetchExistingTransactionIDs(for: transaction)
        if existingIDs.isEmpty {
            AppLogger.log("⚠️ [REVIEW] No existing transactions row found for tx \(transaction.id). Inserting fallback row.")
            try await insertToTransactions(
                transaction: transaction,
                categoryName: finalCategory,
                note: note,
                cashFlowID: cashFlowID
            )
        } else {
            AppLogger.log("✅ [REVIEW] Updating \(existingIDs.count) existing transaction row(s) for tx \(transaction.id).")
            for id in existingIDs {
                try await update(
                    transactionID: id,
                    categoryName: finalCategory,
                    effectiveCategoryName: finalCategory,
                    note: note,
                    markReviewed: true,
                    flowMonth: transaction.flow_month
                )
            }
        }

        // Mark as reviewed in 'bank_scraper_pending_transactions'
        try await update(
            transactionID: transaction.id,
            categoryName: finalCategory,
            effectiveCategoryName: finalCategory,
            note: note,
            markReviewed: true
        )
    }

    private func insertToTransactions(transaction: Transaction, categoryName: String?, note: String?, cashFlowID: String) async throws {
        let categorySource = categoryName ?? transaction.effectiveCategoryName
        let trimmedCategory = categorySource.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalCategory = trimmedCategory.isEmpty ? nil : trimmedCategory
        let finalNote = sanitize(note ?? transaction.notes)
        
        let payload = TransactionInsertPayload(
            user_id: transaction.user_id,
            business_name: transaction.business_name,
            amount: transaction.absoluteAmount,
            currency: transaction.currency,
            date: transaction.date,
            payment_date: transaction.payment_date,
            category_name: finalCategory,
            notes: finalNote,
            status: "reviewed",
            payment_method: transaction.payment_method,
            payment_identifier: transaction.payment_identifier,
            transaction_hash: transaction.transaction_hash,
            bank_scraper_source_id: transaction.bank_scraper_source_id,
            flow_month: transaction.flow_month,

            created_at: isoFormatter.string(from: Date()),
            source_type: transaction.source_type ?? "manual_approval",
            reviewed_at: isoFormatter.string(from: Date()),
            cash_flow_id: cashFlowID
        )
        
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        
        AppLogger.log("📤 [INSERT] Inserting approved transaction to 'transactions' table: \(transaction.business_name ?? "Unknown")")
        
        _ = try await request(
            path: "transactions",
            method: "POST",
            body: body,
            prefer: "return=minimal"
        )
    }

    func updateCategory(transactionID: String, categoryName: String, note: String? = nil) async throws {
        try await update(
            transactionID: transactionID,
            categoryName: categoryName,
            effectiveCategoryName: categoryName,
            note: note,
            markReviewed: false
        )
    }


    func updateFlowMonth(transactionID: String, flowMonth: String) async throws {
        let trimmed = flowMonth.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SupabaseServiceError.server(message: "חודש תזרים לא תקין")
        }
        try await update(
            transactionID: transactionID,
            categoryName: nil,
            note: nil,
            markReviewed: false,
            flowMonth: trimmed
        )
    }
    
    func delete(transactionID: String) async throws {
        // For delete, we'll set suppress_from_automation = true and mark as reviewed
        try await updateFlags(
            transactionID: transactionID,
            suppressFromAutomation: true,
            manualSplitApplied: nil,
            markReviewed: true
        )
    }

    func updateNoteOnly(transactionID: String, note: String?) async throws {
        AppLogger.log("[DEBUG] updateNoteOnly() tx=\(transactionID), note=\(note ?? "nil")")

        var payload: [String: Any] = [:]
        if let note, !note.isEmpty {
            payload["notes"] = note
        } else {
            payload["notes"] = NSNull()
        }

        AppLogger.log("[DEBUG] about to encode JSON body: \(payload)")
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let query = [URLQueryItem(name: "id", value: "eq.\(transactionID)")]

        AppLogger.log("[DEBUG] sending PATCH for tx \(transactionID)")
        let table = tableName(for: transactionID)
        _ = try await request(
            path: table,
            method: "PATCH",
            queryItems: query,
            body: body,
            prefer: "return=minimal"
        )
        AppLogger.log("[DEBUG] updateNoteOnly() finished for tx \(transactionID)")
    }

    func saveDefaultCategory(for userID: String, businessName: String, categoryName: String) async throws {
        let payload = BusinessCategoryDefaultPayload(
            user_id: userID,
            business_name: businessName,
            category_name: categoryName
        )
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        let query = [URLQueryItem(name: "on_conflict", value: "user_id,business_name")]
        _ = try await request(
            path: "business_category_defaults",
            method: "POST",
            queryItems: query,
            body: body,
            prefer: "resolution=merge-duplicates"
        )
    }

    func fetchBusinessCategoryDefaults(for userID: String) async throws -> [BusinessCategoryDefault] {
        let query = [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "select", value: "*")
        ]
        let data = try await request(path: "business_category_defaults", queryItems: query)
        let defaults = try decoder.decode([BusinessCategoryDefault].self, from: data)
        return defaults
    }


    func hideBusiness(for userID: String, businessName: String, reason: String) async throws {
        let payload = HiddenBusinessPayload(
            user_id: userID,
            business_name: businessName,
            reason: reason,
            is_active: true
        )
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        do {
            _ = try await request(
                path: "hidden_business_names",
                method: "POST",
                body: body,
                prefer: "return=representation"
            )
        } catch SupabaseServiceError.server(let message) {
            if message.contains("duplicate key value") {
                AppLogger.log("ℹ️ [SUPABASE] Hidden business already exists for \(businessName)")
            } else {
                throw SupabaseServiceError.server(message: message)
            }
        }
    }

    // MARK: - Private helpers
    private func fetchCategoriesFromBackend() async -> [TransactionCategory] {
        do {
            let apiClient = AppAPIClient(baseURL: AppConfig.baseURL)
            let orders = try await CategoryOrderService(apiClient: apiClient).getCategoryOrders()
            let mapped = orders.compactMap { order -> TransactionCategory? in
                let name = order.categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return TransactionCategory(
                    id: order.id ?? UUID().uuidString,
                    name: name,
                    displayOrder: order.displayOrder ?? Int.max
                )
            }
            AppLogger.log("✅ [DEBUG] Backend fallback returned \(mapped.count) categories")
            return sortCategories(mapped)
        } catch {
            AppLogger.log("❌ [DEBUG] Backend category fallback failed: \(error)")
            return []
        }
    }

    private func sortCategories(_ categories: [TransactionCategory]) -> [TransactionCategory] {
        categories.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.name < $1.name
            }
            return $0.displayOrder < $1.displayOrder
        }
    }

    private func fetchExistingTransactionIDs(for transaction: Transaction) async throws -> [String] {
        guard let userID = normalizedQueryValue(transaction.user_id) else {
            AppLogger.log("⚠️ [REVIEW] Missing user_id for tx \(transaction.id); skipping lookup.")
            return []
        }
        guard let query = buildExistingTransactionQuery(for: transaction, userID: userID) else {
            AppLogger.log("⚠️ [REVIEW] Missing lookup keys for tx \(transaction.id); skipping lookup.")
            return []
        }

        let data = try await request(path: "transactions", queryItems: query)
        let rows = try decoder.decode([TransactionIDRow].self, from: data)
        return rows.map { $0.id }
    }

    private func buildExistingTransactionQuery(for transaction: Transaction, userID: String) -> [URLQueryItem]? {
        let base: [URLQueryItem] = [
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "limit", value: "5")
        ]

        if let hash = normalizedQueryValue(transaction.transaction_hash) {
            return base + [URLQueryItem(name: "transaction_hash", value: "eq.\(hash)")]
        }

        if let sourceID = transaction.bank_scraper_source_id {
            return base + [URLQueryItem(name: "bank_scraper_source_id", value: "eq.\(sourceID)")]
        }

        if let identifier = normalizedQueryValue(transaction.payment_identifier) {
            var query = base + [URLQueryItem(name: "payment_identifier", value: "eq.\(identifier)")]
            if let method = normalizedQueryValue(transaction.payment_method) {
                query.append(URLQueryItem(name: "payment_method", value: "eq.\(method)"))
            }
            if let paymentDate = normalizedQueryValue(transaction.payment_date) {
                query.append(URLQueryItem(name: "payment_date", value: "eq.\(paymentDate)"))
            }
            return query
        }

        if let businessName = normalizedQueryValue(transaction.business_name),
           let paymentDate = normalizedQueryValue(transaction.payment_date) {
            var query = base
            query.append(URLQueryItem(name: "business_name", value: "eq.\(businessName)"))
            query.append(URLQueryItem(name: "payment_date", value: "eq.\(paymentDate)"))
            query.append(URLQueryItem(name: "amount", value: "eq.\(formatAmountForQuery(transaction.absoluteAmount))"))
            return query
        }

        return nil
    }

    private func normalizedQueryValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func formatAmountForQuery(_ amount: Double) -> String {
        if amount.rounded(.towardZero) == amount {
            return String(Int64(amount))
        }
        return String(amount)
    }

    private func tableName(for transactionID: String) -> String {
        let trimmed = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int64(trimmed) != nil ? "bank_scraper_pending_transactions" : "transactions"
    }

    private func update(
        transactionID: String,
        categoryName: String?,
        effectiveCategoryName: String? = nil,
        note: String?,
        markReviewed: Bool,
        flowMonth: String? = nil
    ) async throws {
        let cleanedNote = sanitize(note)
        let payload = TransactionUpdatePayload(
            category_name: categoryName,
            effective_category_name: effectiveCategoryName,
            status: markReviewed ? "reviewed" : nil,
            reviewed_at: markReviewed ? isoFormatter.string(from: Date()) : nil,
            notes: cleanedNote,
            flow_month: flowMonth
        )
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        let query = [URLQueryItem(name: "id", value: "eq.\(transactionID)")]
        let table = tableName(for: transactionID)
        _ = try await request(
            path: table,
            method: "PATCH",
            queryItems: query,
            body: body,
            prefer: "return=minimal"
        )
    }

    private func sanitize(_ note: String?) -> String? {
        guard let note = note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func applySplit(originalTransaction: Transaction, splits: [SplitTransactionEntry], cashFlowID: String) async throws {
        AppLogger.log("✂️ [SPLIT] Applying client-side split for tx \(originalTransaction.id) with \(splits.count) entries, cashFlowID: \(cashFlowID)")
        
        // 1. Create new transactions for each split
        for split in splits {
            // Determine date - use paymentDate or original date
            // split.paymentDate is a String, likely YYYY-MM-DD
            
            let payload = TransactionInsertPayload(
                user_id: originalTransaction.user_id,
                business_name: split.businessName,
                amount: split.amount, // Amount is signed based on logic in SplitTransactionSheet
                currency: split.currency,
                date: originalTransaction.date, // Preserve original date
                payment_date: split.paymentDate,
                category_name: split.category,
                notes: split.description,
                status: "reviewed",
                payment_method: originalTransaction.payment_method,
                payment_identifier: nil,
                transaction_hash: nil,
                bank_scraper_source_id: nil,
                flow_month: split.flowMonth,
                created_at: isoFormatter.string(from: Date()),
                source_type: "manual_split",
                reviewed_at: isoFormatter.string(from: Date()),
                cash_flow_id: cashFlowID // Use provided cashFlowID
            )
            
            let encoder = JSONEncoder()
            let body = try encoder.encode(payload)
            
            AppLogger.log("📤 [INSERT] Inserting split part: \(split.businessName) - \(split.amount)")
            
            _ = try await request(
                path: "transactions",
                method: "POST",
                body: body,
                prefer: "return=minimal"
            )
        }
        
        // 2. Mark original transaction as reviewed and split
        try await updateFlags(
            transactionID: originalTransaction.id,
            suppressFromAutomation: nil,
            manualSplitApplied: true,
            markReviewed: true
        )
        
        AppLogger.log("✅ [SPLIT] Successfully applied split for \(originalTransaction.id)")
    }

    private func updateFlags(
        transactionID: String,
        suppressFromAutomation: Bool?,
        manualSplitApplied: Bool?,
        markReviewed: Bool
    ) async throws {
        let payload = TransactionFlagUpdatePayload(
            suppress_from_automation: suppressFromAutomation,
            manual_split_applied: manualSplitApplied,
            status: markReviewed ? "reviewed" : nil, // Changed to update status if reviewed
            reviewed_at: markReviewed ? isoFormatter.string(from: Date()) : nil
        )
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        let query = [URLQueryItem(name: "id", value: "eq.\(transactionID)")]
        let table = tableName(for: transactionID)
        _ = try await request(path: table, method: "PATCH", queryItems: query, body: body, prefer: "return=minimal")
    }

    private func filterAutomatedTransactions(_ rows: [Transaction]) -> [Transaction] {
        AppLogger.log("🔍 [DEBUG] About to filter \(rows.count) transactions for final cleanup")
        let filteredRows = rows.filter { tx in
            let isSuppressed = tx.suppress_from_automation ?? false
            let wasSplit = tx.manual_split_applied ?? false

            let trimmedCurrency = tx.currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isUSD = trimmedCurrency == "USD" || trimmedCurrency == "$" || trimmedCurrency?.contains("DOLLAR") == true

            guard !isSuppressed && !wasSplit && !isUSD else {
                if isSuppressed {
                    AppLogger.log("🔍 [DEBUG] Filtering out tx \(tx.id) – suppressed: \(isSuppressed)")
                } else if wasSplit {
                    AppLogger.log("🔍 [DEBUG] Filtering out tx \(tx.id) – split: \(wasSplit)")
                } else if isUSD {
                    AppLogger.log("🔍 [DEBUG] Filtering out tx \(tx.id) – currency is USD: \(tx.currency ?? "N/A")")
                }
                return false
            }

            return true
        }
        AppLogger.log("🔍 [DEBUG] Filtered from \(rows.count) to \(filteredRows.count) transactions")
        for tx in filteredRows.prefix(3) {
            AppLogger.log("✅ [DEBUG] Keeping tx id=\(tx.id), business_name=\(tx.business_name ?? "N/A"), status=\(tx.status ?? "N/A")")
        }
        return filteredRows
    }

    private func request(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        guard var components = URLComponents(url: credentials.restURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SupabaseServiceError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw SupabaseServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.apiKey, forHTTPHeaderField: "apikey")

        if let userToken = SupabaseAuthTokenProvider.currentAccessToken() {
            // Production mode - user is authenticated
            request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        } else {
            // Fallback to dev mode (not recommended for production)
            request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        }

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? "<binary \(data.count)b>"
            throw SupabaseServiceError.server(message: snippet)
        }
        return data
    }
}

private struct TransactionIDRow: Decodable {
    let id: String

    enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? container.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? container.decode(Int64.self, forKey: .id) {
            id = String(n)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Unsupported id type for TransactionIDRow.id"
            )
        }
    }
}

private struct TransactionUpdatePayload: Encodable {
    let category_name: String?
    let effective_category_name: String?
    let status: String?
    let reviewed_at: String?
    let notes: String?
    let flow_month: String?

    enum CodingKeys: String, CodingKey {
        case category_name
        case effective_category_name
        case status
        case reviewed_at
        case notes
        case flow_month
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let category_name {
            try container.encode(category_name, forKey: .category_name)
        }
        if let effective_category_name {
            try container.encode(effective_category_name, forKey: .effective_category_name)
        }
        if let status {
            try container.encode(status, forKey: .status)
        }
        if let reviewed_at {
            try container.encode(reviewed_at, forKey: .reviewed_at)
        }
        if let notes {
            try container.encode(notes, forKey: .notes)
        }
        if let flow_month {
            try container.encode(flow_month, forKey: .flow_month)
        }
    }
}

private struct BusinessCategoryDefaultPayload: Encodable {
    let user_id: String
    let business_name: String
    let category_name: String
}

private struct HiddenBusinessPayload: Encodable {
    let user_id: String
    let business_name: String
    let reason: String
    let is_active: Bool
}

private struct TransactionFlagUpdatePayload: Encodable {
    let suppress_from_automation: Bool?
    let manual_split_applied: Bool?
    let status: String?
    let reviewed_at: String?

    enum CodingKeys: String, CodingKey {
        case suppress_from_automation
        case manual_split_applied
        case status
        case reviewed_at
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let suppress_from_automation {
            try container.encode(suppress_from_automation, forKey: .suppress_from_automation)
        }
        if let manual_split_applied {
            try container.encode(manual_split_applied, forKey: .manual_split_applied)
        }
        if let status {
            try container.encode(status, forKey: .status)
        }
        if let reviewed_at {
            try container.encode(reviewed_at, forKey: .reviewed_at)
        }
    }
}

private struct TransactionInsertPayload: Encodable {
    let user_id: String?
    let business_name: String?
    let amount: Double
    let currency: String?
    let date: String?
    let payment_date: String?
    let category_name: String?
    let notes: String?
    let status: String
    let payment_method: String?
    let payment_identifier: String?
    let transaction_hash: String?
    let bank_scraper_source_id: Int64?
    let flow_month: String?
    let created_at: String
    let source_type: String
    let reviewed_at: String
    let cash_flow_id: String

    enum CodingKeys: String, CodingKey {
        case user_id
        case business_name
        case amount
        case currency
        case date
        case payment_date
        case category_name
        case notes
        case status
        case payment_method
        case payment_identifier
        case transaction_hash
        case bank_scraper_source_id
        case flow_month
        case created_at
        case source_type
        case reviewed_at
        case cash_flow_id
    }
}
