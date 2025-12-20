import Foundation

struct TransactionCategory: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let displayOrder: Int

    init(id: String, name: String, displayOrder: Int = Int.max) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayOrder = displayOrder
    }

    // For backward compatibility - init from name only
    init(name: String) {
        self.id = UUID().uuidString
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayOrder = Int.max
    }
}

struct Transaction: Identifiable, Codable, Hashable {
    let id: String
    let effectiveCategoryName: String
    let isIncome: Bool
    let business_name: String?
    let payment_method: String?
    var parsedDate: Date? {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        if let s = payment_date, let d = df.date(from: s) { return d }
        if let s = date, let d = df.date(from: s) { return d }
        // Try yyyy-MM-dd
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        if let s = payment_date, let d = f.date(from: s) { return d }
        if let s = date, let d = f.date(from: s) { return d }
        return nil
    }

    var flowMonthKey: String? {
        if let flow = flow_month, !flow.isEmpty { return flow }
        guard let date = parsedDate else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return nil }
        return String(format: "%04d-%02d", year, month)
    }

    let createdAtDate: Date?
    let currency: String?
    let absoluteAmount: Double
    var notes: String?
    let normalizedAmount: Double
    let excluded_from_flow: Bool?
    let category_name: String?
    let category: TransactionCategory?
    let status: String?
    let user_id: String?
    let suppress_from_automation: Bool?
    let manual_split_applied: Bool?
    let reviewed_at: String?
    let source_type: String?
    let date: String?
    let payment_date: String?
    let flow_month: String?

    enum CodingKeys: String, CodingKey {
        case id
        case effectiveCategoryName = "effective_category_name"
        case isIncome = "is_income"
        case business_name
        case payment_method
        case createdAtDate = "created_at"
        case currency
        case absoluteAmount = "amount"
        case notes
        // normalizedAmount removed from CodingKeys to prevent decoding/encoding from DB
        case excluded_from_flow
        case category_name
        case category
        case status
        case user_id
        case suppress_from_automation
        case manual_split_applied
        case reviewed_at
        case source_type
        case date = "date"  // Use the exact field name
        case payment_date = "payment_date"  // Use the exact field name
        case flow_month = "flow_month"  // Use the exact field name
    }

    init(
        id: String,
        effectiveCategoryName: String = "",
        isIncome: Bool = false,
        business_name: String? = nil,
        payment_method: String? = nil,
        createdAtDate: Date? = nil,
        currency: String? = nil,
        absoluteAmount: Double = 0.0,
        notes: String? = nil,
        normalizedAmount: Double = 0.0,
        excluded_from_flow: Bool? = nil,
        category_name: String? = nil,
        category: TransactionCategory? = nil,
        status: String? = nil,
        user_id: String? = nil,
        suppress_from_automation: Bool? = nil,
        manual_split_applied: Bool? = nil,
        reviewed_at: String? = nil,
        source_type: String? = nil,
        date: String? = nil,
        payment_date: String? = nil,
        flow_month: String? = nil
    ) {
        self.id = id
        self.effectiveCategoryName = effectiveCategoryName
        self.isIncome = isIncome
        self.business_name = business_name
        self.payment_method = payment_method
        self.createdAtDate = createdAtDate
        self.currency = currency
        self.absoluteAmount = absoluteAmount
        self.notes = notes
        self.normalizedAmount = normalizedAmount
        self.excluded_from_flow = excluded_from_flow
        self.category_name = category_name
        self.category = category
        self.status = status
        self.user_id = user_id
        self.suppress_from_automation = suppress_from_automation
        self.manual_split_applied = manual_split_applied
        self.reviewed_at = reviewed_at
        self.source_type = source_type
        self.date = date
        self.payment_date = payment_date
        self.flow_month = flow_month
    }

    // Custom decoding to handle ISO 8601 date strings
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle both String and Int64 id types for compatibility with bigint in database
        if let s = try? container.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? container.decode(Int64.self, forKey: .id) {
            id = String(n)
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Unsupported id type for Transaction.id"
            )
        }

        // effectiveCategoryName: קודם מה־effective, אם אין – מה־category_name
        let rawEffectiveCategoryName = try container.decodeIfPresent(String.self, forKey: .effectiveCategoryName)
        let rawCategoryName = try container.decodeIfPresent(String.self, forKey: .category_name)
        effectiveCategoryName = rawEffectiveCategoryName ?? rawCategoryName ?? ""

        business_name = try container.decodeIfPresent(String.self, forKey: .business_name)
        payment_method = try container.decodeIfPresent(String.self, forKey: .payment_method)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        excluded_from_flow = try container.decodeIfPresent(Bool.self, forKey: .excluded_from_flow)
        category_name = rawCategoryName
        category = try container.decodeIfPresent(TransactionCategory.self, forKey: .category)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        user_id = try container.decodeIfPresent(String.self, forKey: .user_id)
        suppress_from_automation = try container.decodeIfPresent(Bool.self, forKey: .suppress_from_automation)
        manual_split_applied = try container.decodeIfPresent(Bool.self, forKey: .manual_split_applied)
        reviewed_at = try container.decodeIfPresent(String.self, forKey: .reviewed_at)
        source_type = try container.decodeIfPresent(String.self, forKey: .source_type)
        date = try container.decodeIfPresent(String.self, forKey: .date)
        payment_date = try container.decodeIfPresent(String.self, forKey: .payment_date)
        flow_month = try container.decodeIfPresent(String.self, forKey: .flow_month)

        // ---- amount: קודם Double, אם נכשל – String, הכל עם try? כדי לא להפיל את ה-decoder ----
        let parsedAmount: Double? = {
            if let d = try? container.decode(Double.self, forKey: .absoluteAmount) {
                return d
            }
            if let s = try? container.decode(String.self, forKey: .absoluteAmount) {
                // להגן גם על מחרוזות עם פסיק במקרה שיום אחד יופיע
                let cleaned = s.replacingOccurrences(of: ",", with: "")
                return Double(cleaned)
            }
            return nil
        }()

        absoluteAmount = parsedAmount ?? 0.0

        // ---- normalized_amount: Always duplicate absoluteAmount to avoid missing column issues ----
        normalizedAmount = absoluteAmount

        // ---- isIncome: אם הגיע מה-API – להשתמש בו; אחרת לחשב לפי amount ----
        if let incomeFlag = try? container.decode(Bool.self, forKey: .isIncome) {
            isIncome = incomeFlag
        } else if let amount = parsedAmount {
            // אצלך: חיובי = הכנסה, שלילי = הוצאה
            isIncome = amount > 0
        } else {
            isIncome = false
        }

        if let createdAtStr = try container.decodeIfPresent(String.self, forKey: .createdAtDate) {
            createdAtDate = Self.parseFlexibleDate(from: createdAtStr)
        } else {
            createdAtDate = nil
        }
    }

    // Helper function to parse dates in multiple formats
    private static func parseFlexibleDate(from dateString: String) -> Date? {
        // Try ISO8601 with fractional seconds: "2025-07-18T05:17:18.441+00:00"
        let isoFormatterWithFractional = ISO8601DateFormatter()
        isoFormatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatterWithFractional.date(from: dateString) {
            return date
        }

        // Try ISO8601 without fractional seconds: "2025-07-18T05:17:18+00:00"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: dateString) {
            return date
        }

        // Try simple date: "2023-03-01"
        let simpleDateFormatter = DateFormatter()
        simpleDateFormatter.dateFormat = "yyyy-MM-dd"
        simpleDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        simpleDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = simpleDateFormatter.date(from: dateString) {
            return date
        }

        // Try timestamp format: "2023-03-01 00:00:00 +0000"
        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = timestampFormatter.date(from: dateString) {
            return date
        }

        // If all formats fail, return nil
        return nil
    }

    // Custom encoding for symmetry
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(effectiveCategoryName, forKey: .effectiveCategoryName)
        try container.encode(isIncome, forKey: .isIncome)
        try container.encodeIfPresent(business_name, forKey: .business_name)
        try container.encodeIfPresent(payment_method, forKey: .payment_method)
        try container.encodeIfPresent(currency, forKey: .currency)
        try container.encode(absoluteAmount, forKey: .absoluteAmount)
        try container.encodeIfPresent(notes, forKey: .notes)
        // normalizedAmount is purely internal/computed now, do not encode to DB
        // try container.encode(normalizedAmount, forKey: .normalizedAmount)
        try container.encodeIfPresent(excluded_from_flow, forKey: .excluded_from_flow)
        try container.encodeIfPresent(category_name, forKey: .category_name)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(user_id, forKey: .user_id)
        try container.encodeIfPresent(suppress_from_automation, forKey: .suppress_from_automation)
        try container.encodeIfPresent(manual_split_applied, forKey: .manual_split_applied)
        try container.encodeIfPresent(reviewed_at, forKey: .reviewed_at)
        try container.encodeIfPresent(source_type, forKey: .source_type)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(payment_date, forKey: .payment_date)
        try container.encodeIfPresent(flow_month, forKey: .flow_month)

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let createdAtDate = createdAtDate {
            try container.encode(dateFormatter.string(from: createdAtDate), forKey: .createdAtDate)
        }
    }

    // Required for Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(effectiveCategoryName)
        hasher.combine(isIncome)
        hasher.combine(business_name)
        hasher.combine(payment_method)
        hasher.combine(parsedDate)
        hasher.combine(createdAtDate)
        hasher.combine(currency)
        hasher.combine(absoluteAmount)
        hasher.combine(notes)
        hasher.combine(normalizedAmount)
        hasher.combine(flowMonthKey)
        hasher.combine(excluded_from_flow)
        hasher.combine(category_name)
        hasher.combine(category)
        hasher.combine(status)
        hasher.combine(user_id)
        hasher.combine(suppress_from_automation)
        hasher.combine(manual_split_applied)
        hasher.combine(reviewed_at)
        hasher.combine(source_type)
        hasher.combine(date)
        hasher.combine(payment_date)
        hasher.combine(flow_month)
    }

    // Required for Equatable conformance (needed for Hashable)
    static func == (lhs: Transaction, rhs: Transaction) -> Bool {
        return lhs.id == rhs.id &&
               lhs.effectiveCategoryName == rhs.effectiveCategoryName &&
               lhs.isIncome == rhs.isIncome &&
               lhs.business_name == rhs.business_name &&
               lhs.payment_method == rhs.payment_method &&
               lhs.parsedDate == rhs.parsedDate &&
               lhs.createdAtDate == rhs.createdAtDate &&
               lhs.currency == rhs.currency &&
               lhs.absoluteAmount == rhs.absoluteAmount &&
               lhs.notes == rhs.notes &&
               lhs.normalizedAmount == rhs.normalizedAmount &&
               lhs.excluded_from_flow == rhs.excluded_from_flow &&
               lhs.category_name == rhs.category_name &&
               lhs.category == rhs.category &&
               lhs.status == rhs.status &&
               lhs.user_id == rhs.user_id &&
               lhs.suppress_from_automation == rhs.suppress_from_automation &&
               lhs.manual_split_applied == rhs.manual_split_applied &&
               lhs.reviewed_at == rhs.reviewed_at &&
               lhs.source_type == rhs.source_type &&
               lhs.date == rhs.date &&
               lhs.payment_date == rhs.payment_date &&
               lhs.flow_month == rhs.flow_month
    }
}

extension Transaction {
    var accountDisplayName: String {
        let raw = payment_method?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "עו\"ש ראשי" : raw
    }
}
