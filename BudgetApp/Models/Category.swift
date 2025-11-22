import Foundation

struct Category: Identifiable, Codable, Hashable {
    // Server may not provide id in all responses
    var id: Int? { rawID }
    let rawID: Int?
    var name: String?
    var category_type: String?

    enum CodingKeys: String, CodingKey {
        case rawID = "id"
        case name
        case category_type
    }
}