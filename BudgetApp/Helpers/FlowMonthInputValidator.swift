import Foundation

struct FlowMonthInputValidator {
    static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static func sanitizeFlowMonthInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        let cleaned = String(digits.prefix(6))
        if cleaned.count <= 4 { return cleaned }
        let year = String(cleaned.prefix(4))
        var month = String(cleaned.dropFirst(4))
        if month.count > 2 {
            month = String(month.prefix(2))
        }
        if month.count == 2 {
            var intVal = Int(month) ?? 1
            intVal = min(max(intVal, 1), 12)
            month = String(format: "%02d", intVal)
        }
        return "\(year)-\(month)"
    }

    static func isValidFlowMonth(_ value: String) -> Bool {
        let trimmed = sanitizeFlowMonthInput(value)
        guard trimmed.count == 7 else { return false }
        guard let date = monthFormatter.date(from: trimmed) else { return false }
        return monthFormatter.string(from: date) == trimmed
    }
}
