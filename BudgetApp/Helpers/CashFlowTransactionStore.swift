import Foundation

/// In-memory cache that keeps transaction snapshots per month for each cash flow/base URL scope.
/// Also persists month snapshots to disk so warm starts can reuse previously fetched months.
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
    private let diskEncoder: JSONEncoder
    private let diskDecoder: JSONDecoder
    private let cacheDirectory: URL

    init() {
        diskEncoder = JSONEncoder()
        diskEncoder.keyEncodingStrategy = .useDefaultKeys
        diskDecoder = JSONDecoder()
        diskDecoder.keyDecodingStrategy = .useDefaultKeys
        let manager = FileManager.default
        if let base = try? manager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
            cacheDirectory = base.appendingPathComponent("CashFlowTransactionStore", isDirectory: true)
            try? manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
        } else {
            cacheDirectory = manager.temporaryDirectory
        }
    }

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
        persistBuckets(monthMap, scope: scope)
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
        persistBuckets(monthMap, scope: scope)
    }

    func upsert(_ transaction: Transaction, scope: ScopeKey) {
        guard let key = transaction.flowMonthKey else { return }
        var monthMap = storage[scope] ?? [:]
        var bucket = monthMap[key] ?? MonthBucket()
        bucket.upsert(transaction)
        monthMap[key] = bucket
        storage[scope] = monthMap
        persistBuckets(monthMap, scope: scope)
    }

    func hydrateFromDisk(scope: ScopeKey, monthKeys: [String]) {
        let missing = missingMonths(scope: scope, monthKeys: monthKeys)
        guard !missing.isEmpty else { return }
        var monthMap = storage[scope] ?? [:]

        for key in missing {
            guard let cached = loadFromDisk(scope: scope, monthKey: key), !cached.isEmpty else { continue }
            var bucket = monthMap[key] ?? MonthBucket()
            for tx in cached {
                bucket.upsert(tx)
            }
            monthMap[key] = bucket
            AppLogger.log("💾 [DISK CACHE] Loaded \(cached.count) transactions for \(key)", force: true)
        }

        storage[scope] = monthMap
    }

    // MARK: - Disk Persistence

    private func persistBuckets(_ monthMap: [String: MonthBucket], scope: ScopeKey) {
        for (monthKey, bucket) in monthMap {
            let url = diskURL(scope: scope, monthKey: monthKey)
            guard !bucket.items.isEmpty else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            do {
                let txs = Array(bucket.items.values)
                let data = try diskEncoder.encode(txs)
                try data.write(to: url, options: .atomic)
            } catch {
                // ignore write failures for now
            }
        }
    }

    private func loadFromDisk(scope: ScopeKey, monthKey: String) -> [Transaction]? {
        let url = diskURL(scope: scope, monthKey: monthKey)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? diskDecoder.decode([Transaction].self, from: data)
    }

    private func diskURL(scope: ScopeKey, monthKey: String) -> URL {
        return scopeDirectory(scope).appendingPathComponent("\(monthKey).json")
    }

    private func scopeDirectory(_ scope: ScopeKey) -> URL {
        let identifier = scopeIdentifier(scope)
        let url = cacheDirectory.appendingPathComponent(identifier, isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
        return url
    }

    private func scopeIdentifier(_ scope: ScopeKey) -> String {
        var components = scope.baseURL.absoluteString
        components.reserveCapacity(scope.cashFlowID.count + components.count + 1)
        components = "\(scope.cashFlowID)|\(components)"
        let encoded = Data(components.utf8).base64EncodedString()
        return encoded.replacingOccurrences(of: "/", with: "_")
    }
}
