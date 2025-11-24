import Foundation

/// In-memory cache that keeps transaction snapshots per month for each cash flow / base URL scope.
/// This lets the dashboard reuse already fetched months when gliding between periods instead of
/// asking the server for the full 5000-transaction payload every time.
final class CashFlowTransactionStore {

    struct ScopeKey: Hashable {
        let cashFlowID: String
        let baseURL: URL
    }

    private struct MonthBucket {
        var items: [String: Transaction] = [:] // transaction.id -> Transaction

        mutating func upsert(_ transaction: Transaction) {
            items[transaction.id] = transaction
        }

        mutating func remove(_ id: String) {
            items.removeValue(forKey: id)
        }
    }

    private var storage: [ScopeKey: [String: MonthBucket]] = [:] // monthKey -> bucket

    func reset(scope: ScopeKey) {
        storage[scope] = [:]
    }

    func hasMonths(scope: ScopeKey, monthKeys: [String]) -> Bool {
        guard let monthMap = storage[scope] else { return false }
        for key in monthKeys {
            if monthMap[key] == nil { return false }
        }
        return true
    }

    func missingMonths(scope: ScopeKey, monthKeys: [String]) -> [String] {
        guard let monthMap = storage[scope] else { return monthKeys }
        return monthKeys.filter { monthMap[$0] == nil }
    }

    func cache(_ transactions: [Transaction], scope: ScopeKey) {
        guard !transactions.isEmpty else { return }
        var monthMap = storage[scope] ?? [:]
        for tx in transactions {
            guard let key = tx.flowMonthKey else { continue }
            var bucket = monthMap[key] ?? MonthBucket()
            bucket.upsert(tx)
            monthMap[key] = bucket
        }
        storage[scope] = monthMap
    }

    func mark(scope: ScopeKey, monthKeys: [String]) {
        guard !monthKeys.isEmpty else { return }
        var monthMap = storage[scope] ?? [:]
        for key in monthKeys {
            if monthMap[key] == nil {
                monthMap[key] = MonthBucket()
            }
        }
        storage[scope] = monthMap
    }

    func collect(scope: ScopeKey, monthKeys: [String]) -> [Transaction] {
        guard let monthMap = storage[scope] else { return [] }
        var result: [Transaction] = []
        for key in monthKeys {
            if let bucket = monthMap[key] {
                result.append(contentsOf: bucket.items.values)
            }
        }
        return result.sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
    }

    func remove(_ transaction: Transaction, scope: ScopeKey) {
        guard let key = transaction.flowMonthKey else { return }
        guard var monthMap = storage[scope] else { return }
        guard var bucket = monthMap[key] else { return }
        bucket.remove(transaction.id)
        monthMap[key] = bucket
        storage[scope] = monthMap
    }

    func upsert(_ transaction: Transaction, scope: ScopeKey) {
        guard let key = transaction.flowMonthKey else { return }
        var monthMap = storage[scope] ?? [:]
        var bucket = monthMap[key] ?? MonthBucket()
        bucket.upsert(transaction)
        monthMap[key] = bucket
        storage[scope] = monthMap
    }
}
