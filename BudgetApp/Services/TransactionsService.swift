// BudgetApp/Services/TransactionsService.swift

import Foundation

public final class TransactionsService {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func getUniqueCategories() async throws -> [String] {
        struct Response: Decodable { let categories: [String]? }

        let url = baseURL.appendingPathComponent("transactions/unique_categories")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let token = KeychainStore.get("auth.token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "Failed unique categories")
        }

        if let arr = try? JSONDecoder().decode([String].self, from: data) { return arr }
        if let obj = try? JSONDecoder().decode(Response.self, from: data) { return obj.categories ?? [] }
        return []
    }

    func deleteAllByCashFlow(cashFlowId: String, confirmLinked: Bool) async throws {
        let url = baseURL.appendingPathComponent("transactions/delete_by_cash_flow")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainStore.get("auth.token") { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let body: [String: Any] = ["cash_flow_id": cashFlowId, "confirm_linked": confirmLinked]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "Failed delete by cash flow")
        }
    }

    func delete(transactionID: String) async throws {
        let url = baseURL.appendingPathComponent("transactions/\(transactionID)")
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = KeychainStore.get("auth.token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "Failed to delete transaction \(transactionID)")
        }
    }

    // Refactored to use individual parameters instead of struct to avoid memory corruption
    func splitTransaction(
        originalTransactionId: String,
        splits: [SplitTransactionEntry]
    ) async throws {
        
#if DEBUG
        AppLogger.log("🔍 [SplitTransaction] Starting with ID: \(originalTransactionId)")
        AppLogger.log("🔍 [SplitTransaction] Number of splits: \(splits.count)")
#endif
        
        let url = baseURL.appendingPathComponent("transactions/split")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        if let token = KeychainStore.get("auth.token") {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
#if DEBUG
            AppLogger.log("🔐 [SplitTransaction] Added Authorization header with token")
#endif
        }

#if DEBUG
        AppLogger.log("🔗 [SplitTransaction] Full URL being called: \(url.absoluteString)")
#endif

        // Validate request data
        guard !originalTransactionId.isEmpty else {
            throw APIError(message: "Original transaction ID cannot be empty")
        }

        guard !splits.isEmpty else {
            throw APIError(message: "Must have at least one split entry")
        }

        // Validate each split entry
        for (index, split) in splits.enumerated() {
            guard !split.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError(message: "Split entry \(index) must have a non-empty category")
            }
            guard !split.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError(message: "Split entry \(index) must have a non-empty business name")
            }
            guard !split.flowMonth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError(message: "Split entry \(index) must have a non-empty flow month")
            }
            guard !split.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw APIError(message: "Split entry \(index) must have a non-empty currency")
            }
        }

        // Build JSON payload manually to avoid encoding issues
        let payload: Data
        do {
            // Create dictionary structure manually for better control
            var jsonDict: [String: Any] = [:]
            jsonDict["original_transaction_id"] = originalTransactionId
            // Some environments still expect camelCase, so send both to maximize compatibility
            jsonDict["originalTransactionId"] = originalTransactionId

            // Convert splits to array of dictionaries using snake_case only
            var splitsArray: [[String: Any]] = []
            for split in splits {
                var splitDict: [String: Any] = [:]
                splitDict["amount"] = split.amount
                splitDict["category"] = split.category
                splitDict["business_name"] = split.businessName
                splitDict["flow_month"] = split.flowMonth
                splitDict["payment_date"] = split.paymentDate
                splitDict["currency"] = split.currency
                if let desc = split.description {
                    splitDict["description"] = desc
                }
                splitsArray.append(splitDict)
            }
            jsonDict["splits"] = splitsArray

            payload = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
        } catch {
#if DEBUG
            AppLogger.log("❌ [SplitTransaction] Encoding error: \(error)")
#endif
            throw APIError(message: "Failed to encode split transaction request: \(error.localizedDescription)")
        }

#if DEBUG
        if let json = String(data: payload, encoding: .utf8) {
            AppLogger.log("🚀 [SplitTransaction] Sending payload: \(json)")
        }
#endif
        
        req.httpBody = payload

        // Execute the network request
        let (data, resp) = try await session.data(for: req)
        
        // Validate response
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "Invalid HTTP response")
        }
        
        guard (200..<300).contains(http.statusCode) else {
            let serverMessage: String
            let statusCode = http.statusCode

#if DEBUG
            if let preview = String(data: data, encoding: .utf8) {
                AppLogger.log("📥 [SplitTransaction] Response body: \(preview)")
                AppLogger.log("📥 [SplitTransaction] Content-Type: \(http.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                AppLogger.log("📥 [SplitTransaction] All headers: \(http.allHeaderFields)")
            }
#endif

            // Try to extract error message from response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                serverMessage = error
            } else {
                let preview = String(data: data, encoding: .utf8) ?? "unknown error"
                serverMessage = preview
            }
            
#if DEBUG
            AppLogger.log("❌ [SplitTransaction] Failed with status \(statusCode): \(serverMessage)")
#endif
            throw APIError(message: "Splitting transaction failed: \(serverMessage)")
        }
        
#if DEBUG
        AppLogger.log("✅ [SplitTransaction] Request completed successfully for \(originalTransactionId)")
#endif
    }
}

// MARK: - Request Models

// Simple struct for split entries - no complex nesting
struct SplitTransactionEntry: Codable, Sendable {
    let amount: Double
    let category: String
    let businessName: String
    let flowMonth: String
    let paymentDate: String
    let currency: String
    let description: String?
    
    // Coding keys for snake_case conversion
    enum CodingKeys: String, CodingKey {
        case amount
        case category
        case businessName = "business_name"
        case flowMonth = "flow_month"
        case paymentDate = "payment_date"
        case currency
        case description
    }
}

// Legacy struct kept for backwards compatibility - DO NOT use as parameter
struct SplitTransactionRequest: Encodable {
    struct Entry: Encodable {
        let amount: Double
        let category: String
        let businessName: String
        let flowMonth: String
        let paymentDate: String
        let currency: String
        let description: String?

        enum CodingKeys: String, CodingKey {
            case amount
            case category
            case businessName = "business_name"
            case flowMonth = "flow_month"
            case paymentDate = "payment_date"
            case currency
            case description
        }
    }

    let originalTransactionId: String
    let splits: [Entry]

    enum CodingKeys: String, CodingKey {
        case originalTransactionId = "original_transaction_id"
        case splits
    }
}
