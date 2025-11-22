import Foundation

struct CashFlow: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let is_default: Bool
    let created_at: Date?
    let updated_at: Date?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case is_default = "is_default"
        case created_at, updated_at
        case currency
    }

    init(
        id: String = UUID().uuidString,
        name: String = "",
        is_default: Bool = false,
        created_at: Date? = nil,
        updated_at: Date? = nil,
        currency: String? = nil
    ) {
        self.id = id
        self.name = name
        self.is_default = is_default
        self.created_at = created_at
        self.updated_at = updated_at
        self.currency = currency
    }

    // Custom decoding to handle ISO 8601 date strings
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        is_default = try container.decode(Bool.self, forKey: .is_default)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)

        // Decode dates with flexible ISO 8601 parsing
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let createdAtStr = try container.decodeIfPresent(String.self, forKey: .created_at) {
            // Try ISO 8601 with fractional seconds first
            if let date = dateFormatter.date(from: createdAtStr) {
                created_at = date
            } else {
                // Fallback: try without fractional seconds
                let altFormatter = ISO8601DateFormatter()
                altFormatter.formatOptions = [.withInternetDateTime]
                created_at = altFormatter.date(from: createdAtStr)
            }
        } else {
            created_at = nil
        }

        if let updatedAtStr = try container.decodeIfPresent(String.self, forKey: .updated_at) {
            // Try ISO 8601 with fractional seconds first
            if let date = dateFormatter.date(from: updatedAtStr) {
                updated_at = date
            } else {
                // Fallback: try without fractional seconds
                let altFormatter = ISO8601DateFormatter()
                altFormatter.formatOptions = [.withInternetDateTime]
                updated_at = altFormatter.date(from: updatedAtStr)
            }
        } else {
            updated_at = nil
        }
    }

    // Custom encoding for symmetry
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(is_default, forKey: .is_default)
        try container.encodeIfPresent(currency, forKey: .currency)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let createdAt = created_at {
            try container.encode(dateFormatter.string(from: createdAt), forKey: .created_at)
        }
        if let updatedAt = updated_at {
            try container.encode(dateFormatter.string(from: updatedAt), forKey: .updated_at)
        }
    }

    // Required for Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Required for Equatable
    static func == (lhs: CashFlow, rhs: CashFlow) -> Bool {
        return lhs.id == rhs.id
    }
}