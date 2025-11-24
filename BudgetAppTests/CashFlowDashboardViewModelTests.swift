import XCTest
@testable import BudgetApp

@MainActor
final class CashFlowDashboardViewModelTests: XCTestCase {

    func testMutateStateAddsExpenseAndUpdatesCharts() {
        let client = AppAPIClient(baseURL: URL(string: "http://localhost")!)
        let vm = CashFlowDashboardViewModel(apiClient: client)
        vm.selectedCashFlow = CashFlow(id: "cf1", name: "ראשי", is_default: true, currency: "ILS")
        vm.currentMonthDate = makeDate(year: 2024, month: 1, day: 15)

        let expense = Transaction(
            id: "tx-expense-1",
            effectiveCategoryName: "מכולת",
            isIncome: false,
            absoluteAmount: 150,
            normalizedAmount: -150,
            payment_date: "2024-01-10T10:00:00Z",
            flow_month: "2024-01"
        )

        vm.mutateState(using: CashFlowDashboardViewModel.TransactionDiff(changes: [.insertion(expense)]))

        XCTAssertEqual(vm.transactions.count, 1)
        XCTAssertEqual(vm.totalExpenses, 150, accuracy: 0.01)
        XCTAssertTrue(vm.expenseCategorySlices.contains(where: { $0.name == "מכולת" && $0.value == 150 }))
        XCTAssertFalse(vm.orderedItems.isEmpty, "Expected orderedItems to include at least one card after inserting transactions")
    }

    func testMutateStateRemovalUpdatesTotals() {
        let client = AppAPIClient(baseURL: URL(string: "http://localhost")!)
        let vm = CashFlowDashboardViewModel(apiClient: client)
        vm.selectedCashFlow = CashFlow(id: "cf2", name: "תזרים 2", is_default: true, currency: "ILS")
        vm.currentMonthDate = makeDate(year: 2024, month: 2, day: 3)

        let rent = Transaction(
            id: "tx-rent",
            effectiveCategoryName: "דיור",
            isIncome: false,
            absoluteAmount: 4000,
            normalizedAmount: -4000,
            payment_date: "2024-02-01T08:00:00Z",
            flow_month: "2024-02"
        )
        let groceries = Transaction(
            id: "tx-food",
            effectiveCategoryName: "מכולת",
            isIncome: false,
            absoluteAmount: 900,
            normalizedAmount: -900,
            payment_date: "2024-02-05T08:00:00Z",
            flow_month: "2024-02"
        )

        vm.mutateState(using: CashFlowDashboardViewModel.TransactionDiff(changes: [.insertion(rent), .insertion(groceries)]))
        let expensesBeforeRemoval = vm.totalExpenses

        vm.mutateState(using: CashFlowDashboardViewModel.TransactionDiff(changes: [.removal(rent)]))

        XCTAssertEqual(vm.transactions.count, 1)
        XCTAssertLessThan(vm.totalExpenses, expensesBeforeRemoval)
        XCTAssertTrue(vm.transactions.contains { $0.id == groceries.id })
        XCTAssertFalse(vm.transactions.contains { $0.id == rent.id })
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: comps) ?? Date()
    }
}
