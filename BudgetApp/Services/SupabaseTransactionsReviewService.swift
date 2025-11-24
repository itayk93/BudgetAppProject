import Foundation

// TransactionCategory is defined in Models/Transaction.swift - will be available across the target

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

        AppLogger.log("🔍 [DEBUG] About to filter \(rows.count) transactions for final cleanup")

        // Additional local filtering – by suppress/split and currency only (date already filtered in DB)
        let filteredRows = rows.filter { tx in
            let isSuppressed = tx.suppress_from_automation ?? false
            let wasSplit = tx.manual_split_applied ?? false

            // Filter out USD transactions (only ILS should be shown)
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
        let data = try await request(path: "category_order", queryItems: query)
        let rows = try decoder.decode([CategoryOrderRow].self, from: data)
        AppLogger.log("🔍 [DEBUG] Raw category decode returned \(rows.count) rows")
        let categories = rows.compactMap { row -> TransactionCategory? in
            guard let name = row.category_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            let displayOrder = row.display_order ?? Int.max
            return TransactionCategory(id: row.id, name: name, displayOrder: displayOrder)
        }
        AppLogger.log("🔍 [DEBUG] Final categories count: \(categories.count)")
        return categories.sorted { $0.displayOrder < $1.displayOrder }
    }

    func markReviewed(transactionID: String, note: String? = nil) async throws {
        try await update(
            transactionID: transactionID,
            categoryName: nil,
            note: note,
            markReviewed: true
        )
    }

    func updateCategory(transactionID: String, categoryName: String, note: String? = nil) async throws {
        try await update(
            transactionID: transactionID,
            categoryName: categoryName,
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
        _ = try await request(
            path: "bank_scraper_pending_transactions",
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

    private func update(
        transactionID: String,
        categoryName: String?,
        note: String?,
        markReviewed: Bool,
        flowMonth: String? = nil
    ) async throws {
        let cleanedNote = sanitize(note)
        let payload = TransactionUpdatePayload(
            category_name: categoryName,
            status: markReviewed ? "reviewed" : nil,
            reviewed_at: markReviewed ? isoFormatter.string(from: Date()) : nil,
            notes: cleanedNote,
            flow_month: flowMonth
        )
        let encoder = JSONEncoder()
        let body = try encoder.encode(payload)
        let query = [URLQueryItem(name: "id", value: "eq.\(transactionID)")]
        // Update the correct table - should be the same as the fetch table
        _ = try await request(path: "bank_scraper_pending_transactions", method: "PATCH", queryItems: query, body: body, prefer: "return=minimal")
    }

    private func sanitize(_ note: String?) -> String? {
        guard let note = note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        _ = try await request(
            path: "bank_scraper_pending_transactions",
            method: "PATCH",
            queryItems: query,
            body: body,
            prefer: "return=minimal"
        )
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

private struct TransactionUpdatePayload: Encodable {
    let category_name: String?
    let status: String?
    let reviewed_at: String?
    let notes: String?
    let flow_month: String?

    enum CodingKeys: String, CodingKey {
        case category_name
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
