import Foundation

// Shared responses and request models
struct CategoryOrderResponse: Decodable {
    let categories: [CategoryOrder]
}

struct EmptyResponse: Decodable {}

struct UpdateSharedCategoryRequest: Encodable {
    let categoryId: String?
    let sharedCategoryName: String?

    enum CodingKeys: String, CodingKey {
        case categoryId
        case sharedCategoryName
    }
}

struct ReorderCategoryRequest: Encodable {
    let id: String?
    let displayOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case displayOrder = "display_order"
    }
}

struct ReorderCategoriesPayload: Encodable {
    let categoryOrders: [ReorderCategoryRequest]
}

struct WeeklyDisplayRequest: Encodable {
    let categoryId: String?
    let showInWeeklyView: Bool

    enum CodingKeys: String, CodingKey {
        case categoryId
        case showInWeeklyView = "showInWeeklyView"
    }
}

final class CategoryOrderService {
    private let apiClient: AppAPIClient

    init(apiClient: AppAPIClient) {
        self.apiClient = apiClient
    }

    func getCategoryOrders() async throws -> [CategoryOrder] {
        print("🚚 [CategoryOrderService] Fetching via AppAPIClient from endpoint: /categories/order")
        
        // Use the generic 'get' method from AppAPIClient.
        // The client is already configured with the base URL and auth.
        do {
            let response: CategoryOrderResponse = try await apiClient.get("/categories/order")
            print("✅ [CategoryOrderService] Successfully fetched \(response.categories.count) category orders via backend.")
            return response.categories
        } catch {
            print("❌ [CategoryOrderService] Failed to fetch or decode category orders via backend: \(error)")
            // Return an empty array on failure to prevent crashes, consistent with original behavior.
            return []
        }
    }

    func updateSharedCategory(categoryId: String?, sharedCategoryName: String?) async throws {
        print("🚚 [CategoryOrderService] Updating shared category for ID \(categoryId ?? "nil") to '\(sharedCategoryName ?? "nil")'")

        let requestBody = UpdateSharedCategoryRequest(
            categoryId: categoryId,
            sharedCategoryName: sharedCategoryName
        )

        // Use the generic 'post' method from AppAPIClient.
        // We explicitly tell the compiler to expect an EmptyResponse, as the server
        // may not return any meaningful content on a successful POST.
        let _: EmptyResponse = try await apiClient.post("/categories/update-shared-category", body: requestBody)
        
        print("✅ [CategoryOrderService] Successfully updated shared category.")
    }

    func reorderCategories(orderData: [CategoryOrder]) async throws {
        let payload = ReorderCategoriesPayload(categoryOrders: orderData.map {
            ReorderCategoryRequest(id: $0.id, displayOrder: $0.displayOrder)
        })

        print("🚚 [CategoryOrderService] Saving order for \(payload.categoryOrders.count) categories")
        let _: EmptyResponse = try await apiClient.post("/categories/reorder", body: payload)
        print("✅ [CategoryOrderService] Reorder persisted")
    }

    func updateWeeklyDisplay(categoryId: String?, showInWeeklyView: Bool) async throws {
        let payload = WeeklyDisplayRequest(categoryId: categoryId, showInWeeklyView: showInWeeklyView)
        print("🚚 [CategoryOrderService] Toggling weekly display for \(categoryId ?? "nil") to \(showInWeeklyView)")
        let _: EmptyResponse = try await apiClient.post("/categories/update-weekly-display", body: payload)
        print("✅ [CategoryOrderService] Weekly display updated")
    }
}
