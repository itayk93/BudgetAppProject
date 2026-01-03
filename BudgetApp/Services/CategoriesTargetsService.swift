import Foundation

final class CategoriesTargetsService {
    private let base: URL
    init(baseURL: URL) { self.base = baseURL }

    private func auth(_ req: inout URLRequest) {
        if let t = KeychainStore.get("auth.token") {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
    }

    func calculateMonthlyTarget(categoryName: String, months: Int = 6) async throws -> Double {
        let url = base.appendingPathComponent("categories/calculate-monthly-target")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        auth(&req)
        let body: [String: Any] = ["categoryName": categoryName, "months": months]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "calc target failed")
        }
        struct Resp: Decodable { let suggested_target: Double?; let monthly_target: Double? }
        let decoded = try JSONDecoder().decode(Resp.self, from: data)
        return decoded.monthly_target ?? decoded.suggested_target ?? 0
    }

    func updateMonthlyTarget(categoryName: String, target: Double) async throws {
        let url = base.appendingPathComponent("categories/update-monthly-target")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        auth(&req)
        let body: [String: Any] = ["categoryName": categoryName, "target": target]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "update target failed")
        }
    }

    func updateSharedTarget(sharedCategoryName: String, target: Double) async throws {
        let url = base.appendingPathComponent("categories/update-shared-target")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        auth(&req)
        let body: [String: Any] = ["sharedCategoryName": sharedCategoryName, "target": target]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "update shared target failed")
        }
    }

    func getSpendingHistory(categoryName: String, months: Int = 12) async throws -> [(String, Double)] {
        var comps = URLComponents(
            url: base.appendingPathComponent(
                "categories/spending-history/\(categoryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? categoryName)"
            ),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "months", value: String(months))]
        var req = URLRequest(url: comps.url!)
        auth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        struct Item: Decodable { let monthName: String; let amount: Double }
        struct Resp: Decodable { let spending_history: [Item]? }
        let decoded = try? JSONDecoder().decode(Resp.self, from: data)
        return (decoded?.spending_history ?? []).map { ($0.monthName, $0.amount) }
    }

    func getSharedTarget(sharedCategoryName: String) async throws -> Double? {
        let url = base.appendingPathComponent(
            "categories/shared-target/\(sharedCategoryName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sharedCategoryName)"
        )
        var req = URLRequest(url: url)
        auth(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }

        // Endpoint sometimes returns target as a raw number and sometimes as an object
        // with `monthly_target`. Parse both shapes defensively.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let direct = json["target"] as? Double {
            return direct
        }

        if let targetDict = json["target"] as? [String: Any], let monthly = targetDict["monthly_target"] as? Double {
            return monthly
        }

        if let monthly = json["monthly_target"] as? Double {
            return monthly
        }

        return nil
    }

    func setUseSharedTarget(categoryName: String, useShared: Bool, sharedCategoryName: String?) async throws {
        let url = base.appendingPathComponent("categories/set-use-shared-target")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        auth(&req)
        var body: [String: Any] = ["categoryName": categoryName, "useSharedTarget": useShared]
        if let sharedCategoryName { body["sharedCategoryName"] = sharedCategoryName }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "set shared failed")
        }
    }

    func calculateSharedTargets(force: Bool = true) async throws {
        let url = base.appendingPathComponent("categories/calculate-shared-targets")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        auth(&req)
        let body: [String: Any] = ["force": force]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError(message: "calculate shared targets failed")
        }
    }
}
