import Foundation

enum PendingNotesError: Error {
    case missingCredentials
    case invalidURL
    case badStatus(Int)
}

struct PendingTransactionNotesService {
    static func updateNote(
        transactionID: String,
        note: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let creds = SupabaseCredentials.current() else {
            completion(.failure(PendingNotesError.missingCredentials))
            return
        }

        var components = URLComponents(
            url: creds.restURL.appendingPathComponent("bank_scraper_pending_transactions"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(transactionID)")
        ]

        guard let url = components?.url else {
            completion(.failure(PendingNotesError.invalidURL))
            return
        }

        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = [:]
        if let trimmed, !trimmed.isEmpty {
            payload["notes"] = trimmed
        } else {
            payload["notes"] = NSNull()
        }

        print("[NOTES] updateNote tx=\(transactionID) payload=\(payload)")

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(creds.apiKey, forHTTPHeaderField: "apikey")
        let authToken = SupabaseAuthTokenProvider.currentAccessToken()
        request.setValue("Bearer \(authToken ?? creds.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                completion(.failure(PendingNotesError.badStatus(http.statusCode)))
                return
            }

            completion(.success(()))
        }

        task.resume()
    }

    static func updateNoteAsync(
        transactionID: String,
        note: String?
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            updateNote(transactionID: transactionID, note: note) { result in
                continuation.resume(with: result)
            }
        }
    }
}
