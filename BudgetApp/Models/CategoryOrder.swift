import Foundation

struct CategoryOrder: Codable, Hashable {
    let id: String?
    let categoryName: String
    let displayOrder: Int?
    let weeklyDisplay: Bool?
    let monthlyTarget: String?        // ← חובה String כי בטבלה זה text!
    let sharedCategory: String?
    let useSharedTarget: Bool?

    // הוסף init מלא כדי שה-Codable יתעלם משדות מיותרים
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        categoryName = try container.decode(String.self, forKey: .categoryName)
        displayOrder = try container.decodeIfPresent(Int.self, forKey: .displayOrder)
        weeklyDisplay = try container.decodeIfPresent(Bool.self, forKey: .weeklyDisplay)
        monthlyTarget = try container.decodeIfPresent(String.self, forKey: .monthlyTarget)
        sharedCategory = try container.decodeIfPresent(String.self, forKey: .sharedCategory)
        useSharedTarget = try container.decodeIfPresent(Bool.self, forKey: .useSharedTarget)
    }

    // Convenience initializer to restore the memberwise initializer functionality
    init(id: String?, categoryName: String, displayOrder: Int?, weeklyDisplay: Bool?, monthlyTarget: String?, sharedCategory: String?, useSharedTarget: Bool?) {
        self.id = id
        self.categoryName = categoryName
        self.displayOrder = displayOrder
        self.weeklyDisplay = weeklyDisplay
        self.monthlyTarget = monthlyTarget
        self.sharedCategory = sharedCategory
        self.useSharedTarget = useSharedTarget
    }

    enum CodingKeys: String, CodingKey {
        case id
        case categoryName = "category_name"
        case displayOrder = "display_order"
        case weeklyDisplay = "weekly_display"
        case monthlyTarget = "monthly_target"
        case sharedCategory = "shared_category"
        case useSharedTarget = "use_shared_target"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(categoryName)
    }

    static func == (lhs: CategoryOrder, rhs: CategoryOrder) -> Bool {
        lhs.id == rhs.id && lhs.categoryName == rhs.categoryName
    }

    var stableId: String {
        id ?? categoryName
    }
}
