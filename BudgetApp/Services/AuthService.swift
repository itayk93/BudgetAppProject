// AuthService.swift
import Foundation

struct AuthUser: Codable {
    let id: String
    let username: String
    let email: String
    let firstName: String?
    let lastName: String?
}

final class AuthService {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func login(username: String, password: String) async throws {
        let url = baseURL.appendingPathComponent("auth/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["username": username, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Login failed"
            throw APIError(message: msg)
        }
        struct LoginResponse: Decodable { let token: String }
        let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
        _ = KeychainStore.set(decoded.token, for: "auth.token")
        NotificationCenter.default.post(name: .authChanged, object: nil)
    }

    func register(username: String, email: String, password: String, firstName: String?, lastName: String?) async throws {
        let url = baseURL.appendingPathComponent("auth/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "username": username,
            "email": email,
            "password": password
        ]
        if let firstName { body["firstName"] = firstName }
        if let lastName { body["lastName"] = lastName }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Register failed"
            throw APIError(message: msg)
        }

        struct RegisterResponse: Decodable { let token: String? }
        let decoded = try JSONDecoder().decode(RegisterResponse.self, from: data)
        if let token = decoded.token {
            _ = KeychainStore.set(token, for: "auth.token")
            NotificationCenter.default.post(name: .authChanged, object: nil)
        }
    }

    func verify() async throws -> Bool {
        guard let token = KeychainStore.get("auth.token") else { return false }
        let url = baseURL.appendingPathComponent("auth/verify")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    func updateSupabaseToken(_ token: String) {
        _ = SupabaseAuthTokenProvider.setCurrentAccessToken(token)
    }

    func logout() {
        KeychainStore.remove("auth.token")
        SupabaseAuthTokenProvider.clearAccessToken()
        NotificationCenter.default.post(name: .authChanged, object: nil)
    }

    func getCurrentUser() async throws -> AuthUser {
        guard let token = KeychainStore.get("auth.token") else {
            throw APIError(message: "No authentication token found")
        }

        let url = baseURL.appendingPathComponent("users/me")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError(message: "No response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Get user failed"
            throw APIError(message: msg)
        }

        return try JSONDecoder().decode(AuthUser.self, from: data)
    }
}
