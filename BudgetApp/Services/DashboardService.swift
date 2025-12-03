import Foundation

struct DashboardSummary: Codable {
    let total_income: Double?
    let total_expenses: Double?
    let net_balance: Double?
}

struct DashboardCategory: Codable, Hashable {
    let name: String
    let type: String?
    let amount: Double?
    let count: Int?
    let is_shared_category: Bool?
    let shared_category: String?
    let weekly_display: Bool?
    let monthly_target: Double?
    let use_shared_target: Bool?
    let display_order: Int?
    // Added to mirror server payload for shared categories
    let spent: Double?
    let sub_categories: [String: DashboardSubCategory]?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case amount
        case count
        case is_shared_category
        case shared_category
        case weekly_display
        case monthly_target
        case use_shared_target
        case display_order
        case spent
        case sub_categories
    }
}

// Sub-category payload under a shared category
struct DashboardSubCategory: Codable, Hashable {
    let name: String?
    let amount: Double?
    let count: Int?
    let spent: Double?
    let transactions: [Transaction]?
    let display_order: Int?
    let weekly_display: Bool?
    let monthly_target: Double?
    let use_shared_target: Bool?

    // Required for Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(amount)
        hasher.combine(count)
        hasher.combine(spent)
        hasher.combine(transactions)
        hasher.combine(display_order)
        hasher.combine(weekly_display)
        hasher.combine(monthly_target)
        hasher.combine(use_shared_target)
    }

    // Required for Equatable conformance (needed for Hashable)
    static func == (lhs: DashboardSubCategory, rhs: DashboardSubCategory) -> Bool {
        return lhs.name == rhs.name &&
               lhs.amount == rhs.amount &&
               lhs.count == rhs.count &&
               lhs.spent == rhs.spent &&
               lhs.transactions == rhs.transactions &&
               lhs.display_order == rhs.display_order &&
               lhs.weekly_display == rhs.weekly_display &&
               lhs.monthly_target == rhs.monthly_target &&
               lhs.use_shared_target == rhs.use_shared_target
    }
}

struct DashboardData: Codable {
    let summary: DashboardSummary?
    let transaction_count: Int?
    let flow_month: String?
    let current_cash_flow_id: String?
    let all_time: Bool?
    let orderedCategories: [DashboardCategory]?
    let category_breakdown: [DashboardCategory]?
    let monthly_goal: DashboardMonthlyGoal?

    enum CodingKeys: String, CodingKey {
        case summary
        case transaction_count
        case flow_month
        case current_cash_flow_id
        case all_time
        case orderedCategories
        case category_breakdown
        case monthly_goal
    }
}

struct DashboardMonthlyGoal: Codable {
    let id: String?
    let cash_flow_id: String?
    let month_key: String?
    let target_amount: Double?
}

final class DashboardService {
    private let apiClient: AppAPIClient
    init(apiClient: AppAPIClient) { self.apiClient = apiClient }

    func fetchDashboard(year: Int, month: Int, cashFlowId: String, allTime: Bool) async throws -> DashboardData {
        let queryItems = [
            URLQueryItem(name: "year", value: String(year)),
            URLQueryItem(name: "month", value: String(month)),
            URLQueryItem(name: "cash_flow", value: cashFlowId),
            URLQueryItem(name: "all_time", value: allTime ? "1" : "0"),
            URLQueryItem(name: "format", value: "json")
        ]
        return try await apiClient.get("dashboard", query: queryItems)
    }
}
