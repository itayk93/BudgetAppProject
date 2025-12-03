// BudgetApp/Services/APIClient.swift
// Renamed and deconflicted to avoid clashes with other files that define `APIClient`/`EmptyResponse`.

import Foundation

// MARK: - Helpers

private struct TransactionsWrapped: Decodable {
    let transactions: [Transaction]?
    let data: [Transaction]?
}

struct APIError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct AppEmptyResponse: Decodable {} // for endpoints with no JSON body

// MARK: - Client

final class AppAPIClient {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var authTokenProvider: () -> String?

    init(
        baseURL: URL,
        session: URLSession = .shared,
        authTokenProvider: @escaping () -> String? = { KeychainStore.get("auth.token") }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .useDefaultKeys
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .useDefaultKeys
        self.authTokenProvider = authTokenProvider
    }

    // Low-level request that returns raw Data (after enforcing JSON-only)
    private func requestRaw(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem]? = nil,
        body: Encodable? = nil
    ) async throws -> Data {
        var url = baseURL.appendingPathComponent(path)
        if let query, var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = query
            if let u = comps.url { url = u }
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept") // JSON only
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }
        if let token = authTokenProvider()?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, resp) = try await session.data(for: req)
        try validateHTTP(resp, data: data, path: path)
        return data
    }

    // Generic request for all verbs (decodes into T)
    @discardableResult
    func send<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem]? = nil,
        body: Encodable? = nil
    ) async throws -> T {
        let data = try await requestRaw(path, method: method, query: query, body: body)

        if T.self == AppEmptyResponse.self {
            // swiftlint:disable:next force_cast
            return AppEmptyResponse() as! T
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            throw APIError(message: "Decoding failed for \(path). Preview: \(preview). Error: \(error)")
        }
    }

    private func validateHTTP(_ response: URLResponse?, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "No HTTP response for \(path)")
        }

        // Log statusCode and Content-Type
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "N/A"
        AppLogger.log("APIClient Response for \(path): Status Code = \(http.statusCode), Content-Type = \(contentType)")

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count)b>"
            if http.statusCode == 401 || http.statusCode == 403 {
                KeychainStore.remove("auth.token")
                NotificationCenter.default.post(name: .authChanged, object: nil)
            }
            throw APIError(message:
                "HTTP \(http.statusCode) for \(path). Body (first 400 chars): \(body.prefix(400))")
        }

        // Allow intentionally empty responses (DELETE/204 often omit headers/body)
        if data.isEmpty {
            return
        }

        // Enforce JSON ONLY for responses with content
        let ct = contentType.lowercased()
        let isJSON = ct.contains("application/json") || ct.contains("application/problem+json")
        if !isJSON {
            let head = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            throw APIError(message:
                "Non-JSON Content-Type for \(path): \(contentType). Sample: \(head)")
        }
    }

    // Convenience GET that uses `send`
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(path, method: "GET", query: query, body: Optional<Data>.none)
    }

    // Convenience verbs
    func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await send(path, method: "POST", query: nil, body: body)
    }
    func put<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await send(path, method: "PUT", query: nil, body: body)
    }
    func patch<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await send(path, method: "PATCH", query: nil, body: body)
    }

    // Encodable existential helper
    private struct AnyEncodable: Encodable {
        private let encodeFunc: (Encoder) throws -> Void
        init(_ wrapped: Encodable) { self.encodeFunc = wrapped.encode }
        func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
    }
}

// MARK: - Convenience endpoints (with JSON-only enforcement and flexible transactions decoding)

extension AppAPIClient {
    func fetchCashFlows() async throws -> [CashFlow] {
        try await get("cashflows")
    }

    /// Flexible decoder for /transactions:
    /// - Supports either a bare array `[Transaction]` OR a wrapped object `{ transactions: [...]} / { data: [...] }`
    func fetchTransactionsFlexible(query: [URLQueryItem]) async throws -> [Transaction] {
        try await fetchTransactionsFlexibleWithMetadata(query: query).transactions
    }

    /// Returns the decoded transactions plus the raw payload size for diagnostics.
    func fetchTransactionsFlexibleWithMetadata(
        query: [URLQueryItem]
    ) async throws -> (transactions: [Transaction], payloadBytes: Int) {
        let data = try await requestRaw("transactions", method: "GET", query: query, body: Optional<Data>.none)
        let transactions = try decodeTransactionsPayload(data)
        return (transactions, data.count)
    }

    private func decodeTransactionsPayload(_ data: Data) throws -> [Transaction] {
        // Try bare array first
        if let arr = try? decoder.decode([Transaction].self, from: data) {
            AppLogger.log("✅ [TRANSACTIONS] Decoded bare array successfully: \(arr.count) transactions")
            return arr
        }
        // Try wrapped object
        if let wrapped = try? decoder.decode(TransactionsWrapped.self, from: data) {
            if let a = wrapped.transactions {
                AppLogger.log("✅ [TRANSACTIONS] Decoded wrapped 'transactions' field: \(a.count) transactions")
                return a
            }
            if let a = wrapped.data {
                AppLogger.log("✅ [TRANSACTIONS] Decoded wrapped 'data' field: \(a.count) transactions")
                return a
            }
        }

        // Enhanced error logging
        let preview = String(data: data.prefix(600), encoding: .utf8) ?? "<binary>"
        AppLogger.log("❌ [TRANSACTIONS] Failed to decode. Full preview:\n\(preview)")

        // Try to decode with more detailed error information using a temporary decoder
        let tempDecoder = JSONDecoder()
        tempDecoder.keyDecodingStrategy = .useDefaultKeys

        do {
            _ = try tempDecoder.decode([Transaction].self, from: data)
        } catch let decodingError {
            AppLogger.log("❌ [TRANSACTIONS] Decoding error: \(decodingError)")
        }

        throw APIError(message: "Could not decode transactions payload. Preview: \(preview)")
    }

    /// Backwards compatible helper (keeps existing call sites working)
    func fetchTransactions(
        cashFlowID: String,
        showAll: Bool = true,
        perPage: Int = 1_000_000,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> [Transaction] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "cash_flow_id", value: cashFlowID),
            URLQueryItem(name: "show_all", value: showAll ? "true" : "false"),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        if let startDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            items.append(URLQueryItem(name: "start_date", value: f.string(from: startDate)))
        }
        if let endDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            items.append(URLQueryItem(name: "end_date", value: f.string(from: endDate)))
        }
        return try await fetchTransactionsFlexible(query: items)
    }

    func fetchPendingTransactions(
        cashFlowID: String,
        startDate: Date? = nil,
        endDate: Date? = nil
    ) async throws -> [Transaction] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "cash_flow_id", value: cashFlowID),
            URLQueryItem(name: "status", value: "pending"),
            URLQueryItem(name: "pending_only", value: "true"), // Add this parameter
            URLQueryItem(name: "per_page", value: "1000000") // Assuming a high limit for pending
        ]
        
        if let startDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            items.append(URLQueryItem(name: "start_date", value: f.string(from: startDate)))
        }
        if let endDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            items.append(URLQueryItem(name: "end_date", value: f.string(from: endDate)))
        }
        
        return try await fetchTransactionsFlexible(query: items)
    }

    func fetchCategories() async throws -> [Category] {
        try await get("categories")
    }
}
