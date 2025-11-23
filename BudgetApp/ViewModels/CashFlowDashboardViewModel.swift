// BudgetApp/ViewModels/CashFlowDashboardViewModel.swift
// Full file — fetch transactions with flexible decoding & treat non-critical endpoints as optional.
// This avoids crashes when category-order / monthly-goals return HTML or error, and when
// /transactions returns a wrapped JSON object.

import Foundation
import SwiftUI
import Combine

@MainActor
final class CashFlowDashboardViewModel: ObservableObject {

    // MARK: - Public enums / models used by Views

    enum TimeRange: String, CaseIterable, Identifiable {
        case months3 = "3 חודשים"
        case months6 = "6 חודשים"
        case year1   = "שנה"
        var id: String { rawValue }
    }

    /// High-level items order for the cards screen
    enum Item: Identifiable, Hashable {
        case income
        case savings
        case nonCashflow
        case sharedGroup(GroupSummary)
        case category(CategorySummary)

        var id: String {
            switch self {
            case .income: return "income"
            case .savings: return "savings"
            case .nonCashflow: return "nonCashflow"
            case .sharedGroup(let g): return "group:\(g.title)"
            case .category(let c): return "category:\(c.name)"
            }
        }
    }

    /// Per-category data for the current month card UI
    struct CategorySummary: Identifiable, Equatable, Hashable {
        var id: String { name }
        let name: String
        let target: Double?
        let isTargetSuggested: Bool // New property
        let totalSpent: Double
        let weeksInMonth: Int
        let weekly: [Int: Double]          // week -> spent
        let weeklyExpected: Double         // per-week target if weekly mode
        let transactions: [Transaction]    // month transactions for this category

        var isFixed: Bool {
            if let t = target, t > 0 { return true }
            return false
        }

        // Required for Equatable
        static func == (lhs: CategorySummary, rhs: CategorySummary) -> Bool {
            return lhs.name == rhs.name &&
                   lhs.target == rhs.target &&
                   lhs.isTargetSuggested == rhs.isTargetSuggested &&
                   lhs.totalSpent == rhs.totalSpent &&
                   lhs.weeksInMonth == rhs.weeksInMonth &&
                   lhs.weekly == rhs.weekly &&
                   lhs.weeklyExpected == rhs.weeklyExpected
        }

        // Required for Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
            hasher.combine(target)
            hasher.combine(isTargetSuggested)
            hasher.combine(totalSpent)
            hasher.combine(weeksInMonth)
            hasher.combine(weeklyExpected)
            // For the transactions array, we'll hash the count and a few key properties
            // to avoid excessive computation
            hasher.combine(transactions.count)
            if !transactions.isEmpty {
                hasher.combine(transactions[0].id)
            }
        }
    }

    /// Aggregated group data (fixed/variable) for current month
    struct GroupSummary: Identifiable, Equatable, Hashable {
        var id: String { title }
        let title: String
        let target: Double
        let totalSpent: Double
        let weeksInMonth: Int
        let weekly: [Int: Double]
        let weeklyExpected: Double
        let transactions: [Transaction]
        let members: [CashFlowDashboardViewModel.CategorySummary]  // Added members property

        // Required for Equatable
        static func == (lhs: GroupSummary, rhs: GroupSummary) -> Bool {
            return lhs.title == rhs.title &&
                   lhs.target == rhs.target &&
                   lhs.totalSpent == rhs.totalSpent &&
                   lhs.weeksInMonth == rhs.weeksInMonth &&
                   lhs.weekly == rhs.weekly &&
                   lhs.weeklyExpected == rhs.weeklyExpected
        }

        // Required for Hashable
        func hash(into hasher: inout Hasher) {
            hasher.combine(title)
            hasher.combine(target)
            hasher.combine(totalSpent)
            hasher.combine(weeksInMonth)
            hasher.combine(weeklyExpected)
            // For the transactions array, we'll hash the count and a few key properties
            // to avoid excessive computation
            hasher.combine(transactions.count)
            if !transactions.isEmpty {
                hasher.combine(transactions[0].id)
            }
        }
    }

    // MARK: - Published state used by views

    @Published var selectedCashFlow: CashFlow?
    @Published var cashFlows: [CashFlow] = []

    @Published var timeRange: TimeRange = .months6
    @Published var currentMonthDate: Date = Date()  // drives cards screen header

    @Published var loading: Bool = false
    @Published var errorMessage: String?

    // Global stats for charts screen
    @Published var totalIncome: Double = 0
    @Published var totalExpenses: Double = 0
    @Published var transactions: [Transaction] = []

    // Charts data (multi-month)
    @Published var monthlyLabels: [String] = []
    @Published var incomeSeries: [Double] = []
    @Published var expensesSeries: [Double] = []
    @Published var netSeries: [Double] = []
    @Published var cumulativeSeries: [Double] = []
    @Published var expenseCategorySlices: [(name: String, value: Double)] = []
    @Published var goalSeries: [Double] = []

    // New: Pending transactions
    @Published var pendingTransactions: [Transaction] = []
    @Published var monthlyTargetGoal: Double?
    
    struct AccountSnapshot: Identifiable, Hashable {
        let id: String
        let accountName: String
        let balance: Double
        let pendingCharges: Double
        let lastUpdated: Date
    }


    // Cards screen aggregates (single currentMonthDate)
    @Published var orderedItems: [Item] = []
    @Published var incomeTransactions: [Transaction] = []
    @Published var incomeTotal: Double = 0
    @Published var incomeExpected: Double = 0

    @Published var savingsTransactions: [Transaction] = []
    @Published var savingsTotal: Double = 0
    @Published var savingsExpected: Double = 0

    @Published var excludedIncome: [Transaction] = []
    @Published var excludedExpense: [Transaction] = []
    @Published var excludedIncomeTotal: Double = 0
    @Published var excludedExpenseTotal: Double = 0

    @Published var sharedGroups: [String: GroupSummary] = [:]

    var accountSnapshots: [AccountSnapshot] {
        let transactionGroups = Dictionary(grouping: transactions) { $0.accountDisplayName }
        let pendingGroups = Dictionary(grouping: pendingTransactions) { $0.accountDisplayName }

        var snapshots: [AccountSnapshot] = []
        var processed = Set<String>()

        for (account, txs) in transactionGroups {
            let balance = txs.reduce(0) { $0 + $1.normalizedAmount }
            let pendingSum = pendingGroups[account]?.reduce(0) { $0 + abs($1.normalizedAmount) } ?? 0
            let lastDate = ([txs, pendingGroups[account] ?? []].flatMap { $0 }).compactMap { $0.parsedDate }.max() ?? Date()
            snapshots.append(.init(id: account, accountName: account, balance: balance, pendingCharges: pendingSum, lastUpdated: lastDate))
            processed.insert(account)
        }

        for (account, pending) in pendingGroups where !processed.contains(account) {
            let pendingSum = pending.reduce(0) { $0 + abs($1.normalizedAmount) }
            let lastDate = pending.compactMap { $0.parsedDate }.max() ?? Date()
            snapshots.append(.init(id: account, accountName: account, balance: 0, pendingCharges: pendingSum, lastUpdated: lastDate))
            processed.insert(account)
        }

        if snapshots.isEmpty {
            snapshots.append(.init(id: "עו\"ש ראשי", accountName: "עו\"ש ראשי", balance: 0, pendingCharges: 0, lastUpdated: Date()))
        }

        return snapshots.sorted { $0.balance > $1.balance }
    }

    var isCurrentMonth: Bool {
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: Date())
        let currentYear = calendar.component(.year, from: Date())
        let selectedMonth = calendar.component(.month, from: currentMonthDate)
        let selectedYear = calendar.component(.year, from: currentMonthDate)

        return currentMonth == selectedMonth && currentYear == selectedYear
    }

    // MARK: - Public

    var apiClient: AppAPIClient  // Made public so login can be accessed

    // MARK: - Private
    private var categoryOrderService: CategoryOrderService
    private var monthlyGoalsService: MonthlyGoalsService
    private var emptyCategoriesService: EmptyCategoriesService
    private var transactionsService: TransactionsService

    /// name -> config (display order, shared mapping, weekly flag, etc.)
    private var categoryOrderMap: [String: CategoryOrder] = [:]

    /// "YYYY-MM" key for the month currently shown in the cards screen
    private var currentMonthKey: String {
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: currentMonthDate)
        let m = cal.component(.month, from: currentMonthDate)
        return String(format: "%04d-%02d", y, m)
    }

    private func isTransactionInCurrentMonth(_ transaction: Transaction) -> Bool {
        guard let transactionDate = transaction.parsedDate else { return false }
        let calendar = Calendar.current
        return calendar.isDate(transactionDate, equalTo: currentMonthDate, toGranularity: .month)
    }

    // MARK: - Init

    init(apiClient: AppAPIClient) {
        self.apiClient = apiClient
        self.categoryOrderService = CategoryOrderService(apiClient: apiClient)
        self.monthlyGoalsService = MonthlyGoalsService(apiClient: apiClient)
        self.emptyCategoriesService = EmptyCategoriesService(apiClient: apiClient)
        self.transactionsService = TransactionsService(baseURL: AppConfig.baseURL)
    }

    // MARK: - Public API

    /// First load: cash flows, category order, and first data build
    func loadInitial() async {
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            print("📥 [LOAD INITIAL] Starting to fetch cash flows...")
            // Cash flows
            let fetched: [CashFlow] = try await apiClient.get("cashflows")
            print("📥 [LOAD INITIAL] Fetched \(fetched.count) cash flows from API")
            for cf in fetched {
                print("  - \(cf.name) (ID: \(cf.id), is_default: \(cf.is_default))")
            }
            cashFlows = fetched
            selectedCashFlow = fetched.first(where: { $0.is_default == true }) ?? fetched.first
            print("📥 [LOAD INITIAL] Selected cash flow: \(selectedCashFlow?.name ?? "NONE")")

            // Category order is optional (backend MUST return JSON; if not — skip)
            do {
                let orders = try await categoryOrderService.getCategoryOrders()
                categoryOrderMap = Dictionary(uniqueKeysWithValues: orders.map { ($0.categoryName, $0) })
                print("✅ [CATEGORY ORDER] Loaded \(categoryOrderMap.count) categories from API")
                for (name, order) in categoryOrderMap.prefix(5) {
                    print("  → \(name): order=\(order.displayOrder ?? -1)")
                }
            } catch {
                print("❌ [CATEGORY ORDER] Failed: \(error)")
                categoryOrderMap = [:]
            }

            // Prime charts & cards
            await refreshData()
        } catch {
            print("❌ [LOAD INITIAL] Error: \(error.localizedDescription)")
            errorMessage = "Failed to load initial data: \(error.localizedDescription)"
        }
    }

    func refreshCategoryOrders() async {
        do {
            let orders = try await categoryOrderService.getCategoryOrders()
            categoryOrderMap = Dictionary(uniqueKeysWithValues: orders.map { ($0.categoryName, $0) })
            print("✅ [CATEGORY ORDER] Refreshed \(categoryOrderMap.count) entries")
        } catch {
            print("❌ [CATEGORY ORDER] Refresh failed: \(error)")
        }
    }

    /// Refresh both multi-month charts and single-month cards
    func refreshData() async {
        print("🔍 [REFRESH DATA] selectedCashFlow is: \(selectedCashFlow?.name ?? "NIL")")
        guard let cf = selectedCashFlow else {
            print("❌ [REFRESH DATA] No cash flow selected!")
            errorMessage = "No cash flow selected."
            return
        }

        print("📊 Displaying cash flow: \(cf.name) (ID: \(cf.id))")

        loading = true
        errorMessage = nil
        defer { loading = false }

        do {
            // Calculate date range that always includes currentMonthDate
            // Expand by 1 month on each side to catch transactions with payment_date
            // outside the month but flow_month within it (e.g., payment_date in Sept but flow_month = Oct)
            let cal = Calendar(identifier: .gregorian)
            let selectedMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: currentMonthDate))!

            // Start with a range that includes the selected month with buffer
            var startDate = cal.date(byAdding: .month, value: -1, to: selectedMonthStart)!
            var endDate = cal.date(byAdding: .month, value: 2, to: selectedMonthStart)!
            endDate = cal.date(byAdding: .day, value: -1, to: endDate)!

            // Also include the timeRange window for charts, but prioritize selected month
            let (chartStart, chartEnd) = dateRange(for: timeRange)
            if chartStart < startDate {
                startDate = chartStart
            }
            if chartEnd > endDate {
                endDate = chartEnd
            }

            // Build query for transactions over a range
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            let items: [URLQueryItem] = [
                URLQueryItem(name: "cash_flow_id", value: cf.id),
                URLQueryItem(name: "show_all", value: "true"),
                URLQueryItem(name: "per_page", value: "5000"),
                URLQueryItem(name: "start_date", value: f.string(from: startDate)),
                URLQueryItem(name: "end_date", value: f.string(from: endDate))
            ]

            // Create copies for concurrent access to avoid Swift 6 capture issues
            let startDateCopy = startDate
            let endDateCopy = endDate

            // Parallel fetch: transactions (must succeed) + optional supporting services
            async let txs: [Transaction] = apiClient.fetchTransactionsFlexible(query: items)
            async let goalsMaybe: [MonthlyGoal]? = try? monthlyGoalsService.getMonthlyGoals(
                cashFlowId: cf.id, startDate: startDateCopy, endDate: endDateCopy
            )
            async let emptyMaybe: [UserEmptyCategoryDisplay]? = try? emptyCategoriesService.getEmptyCategories(
                cashFlowId: cf.id, startDate: startDateCopy, endDate: endDateCopy
            )
            async let pendingTxs: [Transaction] = apiClient.fetchPendingTransactions(
                cashFlowID: cf.id, startDate: startDateCopy, endDate: endDateCopy
            )

            let transactionsAll = try await txs
            let monthlyGoals = await goalsMaybe ?? []
            let emptyCategories = await emptyMaybe ?? []
            self.pendingTransactions = try await pendingTxs


            // Update global store
            transactions = transactionsAll

            // Compute income/expense totals over the period, excluding non-cashflow
            let flowTx = transactionsAll.filter { !isExcluded($0) }
            totalIncome = flowTx.reduce(0) { total, tx in
                if tx.isIncome {
                    return total + max(0, tx.normalizedAmount)
                } else if tx.normalizedAmount > 0 {
                    return total + tx.normalizedAmount
                }
                return total
            }
            totalExpenses = flowTx.reduce(0) { total, tx in
                if tx.normalizedAmount < 0 {
                    return total + abs(tx.normalizedAmount)
                }
                return total
            }

            // Build charts across the whole window
            buildCharts(txs: transactionsAll, goals: monthlyGoals, emptyCategories: emptyCategories)

            // Build single-month cards (currentMonthDate)
            buildCardsForCurrentMonth(all: transactionsAll, emptyCategories: emptyCategories)

        } catch {
            // Keep a friendly error and clear UI so the user can retry
            print("Decoding error in refreshData: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("Data corrupted: \(context.debugDescription)")
                    print("Coding path: \(context.codingPath)")
                case .keyNotFound(let key, let context):
                    print("Key '\(key.stringValue)' not found: \(context.debugDescription)")
                    print("Coding path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("Value of type '\(type)' not found: \(context.debugDescription)")
                    print("Coding path: \(context.codingPath)")
                case .typeMismatch(let type, let context):
                    print("Type mismatch for type '\(type)': \(context.debugDescription)")
                    print("Coding path: \(context.codingPath)")
                @unknown default:
                    print("Unknown decoding error: \(decodingError.localizedDescription)")
                }
            }
            errorMessage = "Failed to refresh data: \(error.localizedDescription)"
            clearAll()
        }
    }

    func saveMonthlyBudget(for categoryName: String, amount: Double) async {
        // This would normally save the monthly budget to a backend service
        // For now, we'll update the category order map in memory
        if let existingCategoryOrder = categoryOrderMap[categoryName] {
            let updatedCategoryOrder = CategoryOrder(
                id: existingCategoryOrder.id, // Pass existing ID
                categoryName: existingCategoryOrder.categoryName,
                displayOrder: existingCategoryOrder.displayOrder,
                weeklyDisplay: existingCategoryOrder.weeklyDisplay,
                monthlyTarget: String(amount), // Convert Double to String
                sharedCategory: existingCategoryOrder.sharedCategory,
                useSharedTarget: existingCategoryOrder.useSharedTarget
            )
            categoryOrderMap[categoryName] = updatedCategoryOrder
        } else {
            let newCategoryOrder = CategoryOrder(
                id: nil, // New category, no ID yet
                categoryName: categoryName,
                displayOrder: nil,
                weeklyDisplay: nil,
                monthlyTarget: String(amount), // Convert Double to String
                sharedCategory: nil,
                useSharedTarget: nil
            )
            categoryOrderMap[categoryName] = newCategoryOrder
        }

        // Refresh the display to show the updated budget
        await refreshData()
    }

    func deleteMonthlyBudget(for categoryName: String) async {
        // This would normally delete the monthly budget from a backend service
        // For now, we'll remove the monthly target from the category order map
        if let existingCategoryOrder = categoryOrderMap[categoryName] {
            let updatedCategoryOrder = CategoryOrder(
                id: existingCategoryOrder.id, // Pass existing ID
                categoryName: existingCategoryOrder.categoryName,
                displayOrder: existingCategoryOrder.displayOrder,
                weeklyDisplay: existingCategoryOrder.weeklyDisplay,
                monthlyTarget: nil,
                sharedCategory: existingCategoryOrder.sharedCategory,
                useSharedTarget: existingCategoryOrder.useSharedTarget
            )
            categoryOrderMap[categoryName] = updatedCategoryOrder
        }

        // Refresh the display to show the change
        await refreshData()
    }

    // Cards screen header buttons
    func previousMonth() {
        if let d = Calendar.current.date(byAdding: .month, value: -1, to: currentMonthDate) {
            currentMonthDate = d
            Task { await refreshData() }
        }
    }

    func nextMonth() {
        if let d = Calendar.current.date(byAdding: .month, value: 1, to: currentMonthDate) {
            currentMonthDate = d
            Task { await refreshData() }
        }
    }

    func updateTarget(for categoryName: String, newTarget: Double) async {
        // Update the category order map with the new target
        if let existingCategoryOrder = categoryOrderMap[categoryName] {
            let updatedCategoryOrder = CategoryOrder(
                id: existingCategoryOrder.id, // Pass existing ID
                categoryName: existingCategoryOrder.categoryName,
                displayOrder: existingCategoryOrder.displayOrder,
                weeklyDisplay: existingCategoryOrder.weeklyDisplay,
                monthlyTarget: String(newTarget), // Convert Double to String
                sharedCategory: existingCategoryOrder.sharedCategory,
                useSharedTarget: existingCategoryOrder.useSharedTarget
            )
            categoryOrderMap[categoryName] = updatedCategoryOrder
        } else {
            // Create a new category order if it doesn't exist
            let newCategoryOrder = CategoryOrder(
                id: nil, // New category, no ID yet
                categoryName: categoryName,
                displayOrder: nil,
                weeklyDisplay: nil,
                monthlyTarget: String(newTarget), // Convert Double to String
                sharedCategory: nil,
                useSharedTarget: nil
            )
            categoryOrderMap[categoryName] = newCategoryOrder
        }

        // Refresh the view to reflect the updated target
        await refreshData()
    }

    func suggestTarget(for categoryName: String) async -> Double {
        // Calculate a suggested target based on historical spending
        // This is a simple algorithm that suggests the average monthly spending over the past 3 months

        let calendar = Calendar.current
        let currentDate = Date()

        // Get transactions from the last 3 months
        var monthDates: [Date] = []
        for i in 0..<3 {
            if let monthDate = calendar.date(byAdding: .month, value: -i, to: currentDate) {
                monthDates.append(monthDate)
            }
        }

        var totalSpent: Double = 0
        var monthCount = 0

        for monthDate in monthDates {
            // Get transactions for this specific month
            let monthTransactions = transactions.filter { transaction in
                guard let transactionDate = transaction.parsedDate else { return false }
                return calendar.isDate(transactionDate, equalTo: monthDate, toGranularity: .month) &&
                       transaction.effectiveCategoryName == categoryName &&
                       transaction.normalizedAmount < 0 // Only expenses
            }

            let monthTotal = monthTransactions.reduce(0) { sum, transaction in
                sum + abs(transaction.normalizedAmount)
            }

            if monthTotal > 0 {
                totalSpent += monthCount > 0 ? monthTotal / Double(monthCount) : 0
                monthCount += 1
            }
        }

        let suggestedTarget = monthCount > 0 ? totalSpent / Double(monthCount) : 0
        return suggestedTarget
    }

    func updateMonthlyTargetGoal(to amount: Double) async {
        monthlyTargetGoal = amount
    }

    func suggestMonthlyTarget() async -> Double {
        let totals = monthlyTotals
        let base = max(500, totals.net * 0.5)
        let rounded = (base / 50).rounded() * 50
        return max(rounded, 500)
    }

    func deleteTransaction(_ transaction: Transaction) async {
        do {
            try await transactionsService.delete(transactionID: transaction.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // Exposed helpers used by view
    func isWeeklyCategory(_ name: String) -> Bool {
        // Use explicit weekly_display flag from category_order table
        if let cfg = categoryOrderMap[name], let weekly = cfg.weeklyDisplay {
            return weekly
        }
        return false
    }

    var monthlyTotals: (income: Double, expenses: Double, net: Double) {
        let monthTx = transactions.filter { $0.flowMonthKey == currentMonthKey && !isExcluded($0) }
        // Income: transactions marked as income (use normalizedAmount as-is, can be positive or negative)
        // OR transactions with positive amounts that aren't explicitly expenses
        let inc = monthTx.reduce(0) { total, tx in
            if tx.isIncome {
                return total + max(0, tx.normalizedAmount) // Only count positive income
            } else if tx.normalizedAmount > 0 && !tx.isIncome {
                return total + tx.normalizedAmount // Positive amount not marked as expense
            }
            return total
        }
        // Expenses: transactions with negative amounts (take absolute value)
        // OR transactions not marked as income with negative amounts
        let exp = monthTx.reduce(0) { total, tx in
            if tx.normalizedAmount < 0 {
                return total + abs(tx.normalizedAmount) // Negative amount = expense
            } else if !tx.isIncome && tx.normalizedAmount > 0 {
                // This shouldn't happen, but if it does, don't count as expense
                return total
            }
            return total
        }
        return (inc, exp, inc - exp)
    }

    // MARK: - Internal builders

    private func buildCharts(txs: [Transaction],
                             goals: [MonthlyGoal],
                             emptyCategories: [UserEmptyCategoryDisplay]) {

        var monthly: [String: (income: Double, expenses: Double)] = [:]
        var categoryAgg: [String: Double] = [:]
        let goalsMap = Dictionary(uniqueKeysWithValues: goals.map { ($0.monthKey, $0.targetAmount) })

        let flowTx = txs.filter { !isExcluded($0) }

        for t in flowTx {
            guard let key = t.flowMonthKey else { continue }
            if monthly[key] == nil { monthly[key] = (0, 0) }
            if t.isIncome || t.normalizedAmount > 0 {
                monthly[key]!.income += max(0, t.normalizedAmount)
            }
            if t.normalizedAmount < 0 {
                let expenseAmount = abs(t.normalizedAmount)
                monthly[key]!.expenses += expenseAmount
                categoryAgg[t.effectiveCategoryName, default: 0] += expenseAmount
            }
        }



        let sortedKeys = monthly.keys.sorted()
        monthlyLabels = sortedKeys.map { monthLabel($0) }
        incomeSeries = sortedKeys.map { monthly[$0]?.income ?? 0 }
        expensesSeries = sortedKeys.map { monthly[$0]?.expenses ?? 0 }
        netSeries = zip(incomeSeries, expensesSeries).map { $0 - $1 }
        goalSeries = sortedKeys.map { goalsMap[$0] ?? 0 }

        var cum = 0.0
        cumulativeSeries = netSeries.map { cum += $0; return cum }

        expenseCategorySlices = categoryAgg.map { ($0.key, $0.value) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(10)
            .map { ($0.0, $0.1) }
    }

    private func _buildCategorySummariesForTransactions(
        transactions: [Transaction],
        isIncome: Bool, // To distinguish income from expense calculations
        isSavings: Bool,
        isNonCashflow: Bool,
        emptyCategories: [UserEmptyCategoryDisplay]
    ) -> [CategorySummary] {
        let cal = Calendar(identifier: .gregorian)
        let weeksInMonth = Self.numberOfWeeks(in: currentMonthDate, calendar: cal)

        var summaries: [CategorySummary] = []

        // Group transactions by their effective category name
        let groupedTransactions = Dictionary(grouping: transactions) { $0.effectiveCategoryName }

        for (name, txs) in groupedTransactions {
            let cfg = categoryOrderMap[name]
            var target = cfg?.monthlyTarget.flatMap { Double($0) }
            var isSuggested = false

            // Suggest target based on historical data if no explicit target is set
            if target == nil {
                // Calculation for 3-month average suggestion (similar to existing logic)
                let calendar = Calendar.current
                var monthDates: [Date] = []
                for i in 1...3 { // Look at 3 previous months
                    if let monthDate = calendar.date(byAdding: .month, value: -i, to: self.currentMonthDate) {
                        monthDates.append(monthDate)
                    }
                }

                var totalHistoricalAmount: Double = 0
                var monthCount = 0

                let categoryTransactions = self.transactions.filter { $0.effectiveCategoryName == name }

                for monthDate in monthDates {
                    let monthTransactions = categoryTransactions.filter { tx in
                        guard let txDate = tx.parsedDate else { return false }
                        return calendar.isDate(txDate, equalTo: monthDate, toGranularity: .month)
                    }
                    
                    let monthTotal = monthTransactions.reduce(0) { sum, transaction in
                        if isIncome {
                            return sum + max(0, transaction.normalizedAmount)
                        } else { // For savings and non-cashflow (which are typically negative or neutral)
                            return sum + abs(min(0, transaction.normalizedAmount))
                        }
                    }

                    if monthTotal > 0 {
                        totalHistoricalAmount += monthTotal
                        monthCount += 1
                    }
                }

                if monthCount > 0 {
                    target = totalHistoricalAmount / Double(monthCount)
                    isSuggested = true
                }
            }


            let weeklyExpected = (target ?? 0) / Double(max(weeksInMonth, 1))
            var weekly: [Int: Double] = [:]
            for t in txs {
                if let d = t.parsedDate {
                    let w = cal.component(.weekOfMonth, from: d)
                    if isIncome {
                        weekly[w, default: 0] += max(0, t.normalizedAmount)
                    } else { // For savings and non-cashflow
                        weekly[w, default: 0] += abs(min(0, t.normalizedAmount))
                    }
                }
            }

            let sum = txs.reduce(0) { total, transaction in
                if isIncome {
                    return total + max(0, transaction.normalizedAmount)
                } else { // For savings and non-cashflow
                    return total + abs(min(0, transaction.normalizedAmount))
                }
            }

            summaries.append(.init(
                name: name,
                target: target,
                isTargetSuggested: isSuggested,
                totalSpent: sum, // Will be totalEarned for income
                weeksInMonth: weeksInMonth,
                weekly: weekly,
                weeklyExpected: weeklyExpected,
                transactions: txs.sorted { ($0.parsedDate ?? .distantPast) < ($1.parsedDate ?? .distantPast) }
            ))
        }

        // Add empty categories for monthly goals if applicable
        for emptyCat in emptyCategories {
            if !groupedTransactions.keys.contains(emptyCat.categoryName) {
                // Only add if it hasn't been added already
                if let cfg = categoryOrderMap[emptyCat.categoryName] {
                    // Check if this empty category belongs to income, savings, or non-cashflow group
                    let isRelevant = (isIncome && (cfg.sharedCategory == "הכנסות" || emptyCat.categoryName.contains("הכנסות"))) ||
                                     (isSavings && (cfg.sharedCategory?.contains("חיסכון") == true || emptyCat.categoryName.contains("חיסכון"))) ||
                                     (isNonCashflow && (cfg.sharedCategory == "לא בתזרים" || emptyCat.categoryName.contains("לא תזרימיות")))

                    if isRelevant {
                        summaries.append(.init(
                            name: emptyCat.categoryName,
                            target: cfg.monthlyTarget.flatMap { Double($0) },
                            isTargetSuggested: false,
                            totalSpent: 0,
                            weeksInMonth: weeksInMonth,
                            weekly: [:],
                            weeklyExpected: (cfg.monthlyTarget.flatMap { Double($0) } ?? 0) / Double(max(weeksInMonth, 1)),
                            transactions: []
                        ))
                    }
                }
            }
        }


        // Sort all summaries by display_order from category_order table
        summaries.sort { (a, b) in
            let oa = categoryOrderMap[a.name]?.displayOrder ?? Int.max
            let ob = categoryOrderMap[b.name]?.displayOrder ?? Int.max
            if oa == ob { return a.name < b.name }
            return oa < ob
        }
        return summaries
    }

    private func _buildAllExpenseCategorySummaries() -> [CategorySummary] {
        let monthTx = transactions.filter { isTransactionInCurrentMonth($0) }
        let expenseTx = monthTx.filter { $0.normalizedAmount < 0 && !isExcluded($0) && !isSavings($0) }
        
        return _buildCategorySummariesForTransactions(
            transactions: expenseTx,
            isIncome: false,
            isSavings: false,
            isNonCashflow: false,
            emptyCategories: [] // Empty categories are handled in buildCardsForCurrentMonth
        )
    }

    private var allExpenseCategorySummaries: [CategorySummary] {
        _buildAllExpenseCategorySummaries()
    }

    private var visibleExpenseCategorySummaries: [CategorySummary] {
        allExpenseCategorySummaries.filter { $0.totalSpent > 0 }
    }

    private var fixedExpenseCategories: [CategorySummary] {
        visibleExpenseCategorySummaries.filter { $0.isFixed }
    }

    private var variableExpenseCategories: [CategorySummary] {
        visibleExpenseCategorySummaries.filter { !$0.isFixed }
    }


    /// מחזיר את ה-display_order של קבוצה משותפת לפי השם שלה.
    /// אם אין שום קטגוריה עם shared_category כזה – חוזר ל-fallback.
    private func orderForSharedGroup(named sharedName: String, fallback: Int) -> Int {
        // כל הקטגוריות שה-shared_category שלהן הוא השם המבוקש
        let matching = categoryOrderMap.values.filter { $0.sharedCategory == sharedName }

        // מוציאים את כל ה-display_order (ללא nil) ולוקחים את המינימום
        let orders = matching.compactMap { $0.displayOrder }

        if let minOrder = orders.min() {
            return minOrder
        }

        // אם לא מצאנו כלום – נשתמש ב-fallback
        return fallback
    }

    private func buildCardsForCurrentMonth(all: [Transaction],
                                           emptyCategories: [UserEmptyCategoryDisplay]) {

        var monthTx = all.filter { isTransactionInCurrentMonth($0) }

        if monthTx.isEmpty {
            let calendar = Calendar.current
            let allMonths: [String: [Transaction]] = Dictionary(grouping: all) { transaction in
                guard let date = transaction.parsedDate else { return "unknown" }
                let year = calendar.component(.year, from: date)
                let month = calendar.component(.month, from: date)
                return String(format: "%04d-%02d", year, month)
            }
            let latestMonthDate: Date? = allMonths.keys.compactMap { key -> Date? in
                let parts = key.split(separator: "-")
                guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
                var comps = DateComponents()
                comps.year = year
                comps.month = month
                return calendar.date(from: comps)
            }.max()
            if let latestDate = latestMonthDate {
                currentMonthDate = latestDate
                monthTx = all.filter { isTransactionInCurrentMonth($0) }
            }
        }

        // --- New List Building Logic ---

        // Temporary structure to hold items with their sort order.
        struct DisplayableItem {
            let item: Item
            let order: Int
        }

        var displayableItems: [DisplayableItem] = []

        // Generate CategorySummaries for Income
        let incomeSummaries = _buildCategorySummariesForTransactions(
            transactions: monthTx.filter { ($0.isIncome || $0.normalizedAmount > 0) && !isExcluded($0) },
            isIncome: true,
            isSavings: false,
            isNonCashflow: false,
            emptyCategories: emptyCategories // Pass empty categories here
        )
        // Update incomeTotal with the sum from summaries
        incomeTotal = incomeSummaries.reduce(0) { $0 + $1.totalSpent }

        // Generate CategorySummaries for Savings
        let savingsSummaries = _buildCategorySummariesForTransactions(
            transactions: monthTx.filter { !isExcluded($0) && $0.normalizedAmount < 0 && isSavings($0) },
            isIncome: false,
            isSavings: true,
            isNonCashflow: false,
            emptyCategories: emptyCategories // Pass empty categories here
        )
        // Update savingsTotal with the sum from summaries
        savingsTotal = savingsSummaries.reduce(0) { $0 + $1.totalSpent }


        // Generate CategorySummaries for Non-Cashflow
        let excludedTx = monthTx.filter { isExcluded($0) }
        let nonCashflowSummaries = _buildCategorySummariesForTransactions(
            transactions: excludedTx,
            isIncome: false,
            isSavings: false,
            isNonCashflow: true,
            emptyCategories: emptyCategories // Pass empty categories here
        )
        // Update excludedIncomeTotal and excludedExpenseTotal from summaries
        excludedIncomeTotal = nonCashflowSummaries.filter { $0.transactions.first?.isIncome == true }.reduce(0) { $0 + $1.totalSpent }
        excludedExpenseTotal = nonCashflowSummaries.filter { $0.transactions.first?.isIncome == false }.reduce(0) { $0 + $1.totalSpent }

        // Combine all summaries (expenses, income, savings, non-cashflow)
        var allCategorizedSummaries = visibleExpenseCategorySummaries // Already processed
        allCategorizedSummaries.append(contentsOf: incomeSummaries)
        allCategorizedSummaries.append(contentsOf: savingsSummaries)
        allCategorizedSummaries.append(contentsOf: nonCashflowSummaries)

        var sharedGroupMembers: [String: [CategorySummary]] = [:]
        var standaloneCategories: [CategorySummary] = []

        for summary in allCategorizedSummaries {
            if let sharedCategoryName = categoryOrderMap[summary.name]?.sharedCategory, !sharedCategoryName.isEmpty {
                sharedGroupMembers[sharedCategoryName, default: []].append(summary)
            } else {
                standaloneCategories.append(summary)
            }
        }
        
        // 3. Add standalone categories to the display list.
        for category in standaloneCategories {
            let order = categoryOrderMap[category.name]?.displayOrder ?? Int.max
            displayableItems.append(DisplayableItem(item: .category(category), order: order))
        }
        
        // 4. Build shared groups and add them to the display list.
        var newSharedGroups: [String: GroupSummary] = [:]
        for (groupName, members) in sharedGroupMembers {
            let cal = Calendar(identifier: .gregorian)
            let weeksInMonth = Self.numberOfWeeks(in: currentMonthDate, calendar: cal)
            
            if let groupSummary = buildGroupSummary(title: groupName, members: members, weeksInMonth: weeksInMonth) {
                // The group's order is the minimum order of its members.
                // Since members are sourced from a sorted list, the first member has the min order.
                let firstMemberName = members.first!.name
                let orderFromMap = categoryOrderMap[firstMemberName]?.displayOrder
                let groupOrder = orderFromMap ?? Int.max
                
                print("🔍 [GROUP SORTING] Group: '\(groupName)'")
                print("  - First member: '\(firstMemberName)'")
                print("  - displayOrder from map: \(orderFromMap.map(String.init) ?? "nil")")
                print("  - Final groupOrder: \(groupOrder)")

                displayableItems.append(DisplayableItem(item: .sharedGroup(groupSummary), order: groupOrder))
                newSharedGroups[groupName] = groupSummary
            }
        }
        
        // 5. Sort the final list based on the calculated order.
        displayableItems.sort { $0.order < $1.order }

        // 6. Finalize the `orderedItems` and `sharedGroups` for the UI.
        self.orderedItems = displayableItems.map { $0.item }
        self.sharedGroups = newSharedGroups


        // Debug: Print final ordered items
        print("📋 [ORDERED ITEMS] Final list (\(orderedItems.count) items):")
        for (index, item) in orderedItems.enumerated() {
            switch item {
            case .income:
                print("  \(index + 1). [INCOME]")
            case .savings:
                print("  \(index + 1). [SAVINGS]")
            case .nonCashflow:
                print("  \(index + 1). [NON-CASHFLOW]")
            case .sharedGroup(let group):
                print("  \(index + 1). [GROUP] \(group.title)")
            case .category(let cat):
                print("  \(index + 1). [CATEGORY] \(cat.name)")
            }
        }
    }

    private func buildGroupSummary(title: String, members: [CategorySummary], weeksInMonth: Int) -> GroupSummary? {
        guard !members.isEmpty else { return nil }
        let target = members.reduce(0) { $0 + ( $1.target ?? 0 ) }
        let spent  = members.reduce(0) { $0 + $1.totalSpent }

        var weekly: [Int: Double] = [:]
        var txs: [Transaction] = []
        for c in members {
            for (w, v) in c.weekly { weekly[w, default: 0] += v }
            txs.append(contentsOf: c.transactions)
        }

        let weeklyExpected = target / Double(max(weeksInMonth, 1))

        return .init(
            title: title,
            target: target,
            totalSpent: spent,
            weeksInMonth: weeksInMonth,
            weekly: weekly,
            weeklyExpected: weeklyExpected,
            transactions: txs.sorted { ($0.parsedDate ?? .distantPast) < ($1.parsedDate ?? .distantPast) },
            members: members
        )
    }

    // MARK: - Utilities

    private func isExcluded(_ t: Transaction) -> Bool {
        if t.excluded_from_flow == true { return true }
        let name = t.effectiveCategoryName
        if let cfg = categoryOrderMap[name], (cfg.sharedCategory ?? "") == "לא בתזרים" { return true }
        let s = (t.category_name ?? t.category?.name ?? "").lowercased()
        return s.contains("לא תזרימיות")
    }

    // Savings detection
    private func isSavings(_ tx: Transaction) -> Bool {
        let name = tx.effectiveCategoryName
        if let cfg = self.categoryOrderMap[name], (cfg.sharedCategory ?? "").contains("חיסכון") { return true }
        return name.contains("חיסכון")
    }

    private func clearAll() {
        totalIncome = 0; totalExpenses = 0; transactions = []
        monthlyLabels = []; incomeSeries = []; expensesSeries = []; netSeries = []
        cumulativeSeries = []; expenseCategorySlices = []; goalSeries = []
        orderedItems = []
        incomeTransactions = []; incomeTotal = 0; incomeExpected = 0
        savingsTransactions = []; savingsTotal = 0; savingsExpected = 0
        excludedIncome = []; excludedExpense = []; excludedIncomeTotal = 0; excludedExpenseTotal = 0
        sharedGroups = [:]
    }

    private func dateRange(for range: TimeRange) -> (start: Date, end: Date) {
        let end = Date()
        let months: Int = (range == .months3 ? 3 : range == .months6 ? 6 : 12)
        let start = Calendar.current.date(byAdding: .month, value: -months, to: end)!
        return (start, end)
    }

    private func monthLabel(_ key: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: key) else { return key }
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "MMM yy"
        return f.string(from: d)
    }

    private static func numberOfWeeks(in date: Date, calendar: Calendar) -> Int {
        let range = calendar.range(of: .weekOfMonth, in: .month, for: date)
        return range?.count ?? 4
    }
}
