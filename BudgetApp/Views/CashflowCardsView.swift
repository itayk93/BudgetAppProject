// BudgetApp/Views/CashflowCardsView.swift

import SwiftUI

private let weeklyGridLineColor = Color.white.opacity(0.22)
private let weeklyGridBackgroundColor = Color.white.opacity(0.04)

private func currencySymbol(for code: String) -> String {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "he_IL")
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    return formatter.currencySymbol ?? "₪"
}

struct CashflowCardsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var vm: CashFlowDashboardViewModel
    @EnvironmentObject private var pendingTxsVm: PendingTransactionsReviewViewModel
    @AppStorage("biometrics.enabled") private var biometricsEnabled = false
    @AppStorage("dashboard.showWeeklyBudgetCard") private var showWeeklyBudgetCard = true
    @AppStorage("dashboard.showMonthlyTargetCard") private var showMonthlyTargetCard = true
    @AppStorage("dashboard.showMonthlyTrendCard") private var showMonthlyTrendCard = true
    
    @State private var showingEditTargetSheet = false
    @State private var selectedCategoryForEdit: CashFlowDashboardViewModel.CategorySummary?
    @State private var editingTargetValue: Double?
    @State private var selectedTransactionForEdit: Transaction?

    @State private var showingEditBudgetSheet = false
    @State private var selectedCategoryForBudgetEdit: CashFlowDashboardViewModel.CategorySummary?
    @State private var editingBudgetValue: Double?
    @State private var biometricLocked = false
    @State private var biometricAlertMessage: String?
    @State private var showBiometricAlert = false
    @State private var isAnimatingButton = false
    @State private var showingAccountStatusSheet = false
    @State private var showingSearchSheet = false
    @State private var showingFilterSheet = false
    @State private var showingMonthlyTargetSheet = false
    @State private var showingPlanAheadSheet = false
    @State private var monthlyTargetEditingValue: Double?
    @State private var transactionFilter = TransactionFilter()
    @State private var showingPendingTransactionsSheet = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    header
                    content
                }
                
                if !vm.loading && vm.errorMessage == nil {
                    FloatingActionButton(count: pendingTxsVm.transactions.count) {
                        showingPendingTransactionsSheet = true
                    }
                    .padding()
                }
            }
            .navigationTitle("תזרים מזומנים")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingEditTargetSheet) {
                if let category = selectedCategoryForEdit {
                    EditTargetView(
                        categoryName: category.name,
                        target: $editingTargetValue,
                        onSave: { newTarget in
                            Task {
                                await vm.updateTarget(for: category.name, newTarget: newTarget)
                            }
                        },
                        onSuggest: {
                            return await vm.suggestTarget(for: category.name)
                        }
                    )
                }
            }
            .sheet(isPresented: $showingMonthlyTargetSheet) {
                EditTargetView(
                    categoryName: "היעד החודשי",
                    target: $monthlyTargetEditingValue,
                    onSave: { newTarget in
                        Task {
                            await vm.updateMonthlyTargetGoal(to: newTarget)
                        }
                    },
                    onSuggest: {
                        await vm.suggestMonthlyTarget()
                    }
                )
            }
            .sheet(isPresented: $showingEditBudgetSheet) {
                if let category = selectedCategoryForBudgetEdit {
                    EditBudgetView(
                        categoryName: category.name,
                        monthName: monthName(vm.currentMonthDate),
                        budget: $editingBudgetValue,
                        onSave: { newBudget in
                            Task {
                                await vm.saveMonthlyBudget(for: category.name, amount: newBudget ?? 0)
                            }
                        },
                        onDelete: {
                            Task {
                                await vm.deleteMonthlyBudget(for: category.name)
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showingSearchSheet) {
                TransactionSearchSheet(filter: transactionFilter, currencySymbol: currentCurrencySymbol)
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showingFilterSheet) {
                TransactionFilterSheet(
                    filter: $transactionFilter,
                    categories: filterableCategories,
                    paymentMethods: paymentMethodOptions
                )
                .environment(\.layoutDirection, .rightToLeft)
            }
            .sheet(isPresented: $showingAccountStatusSheet) {
                AccountStatusSheet(
                    snapshots: vm.accountSnapshots,
                    currencySymbol: currentCurrencySymbol
                )
            }
            .sheet(isPresented: $showingPlanAheadSheet) {
                PlanAheadSheet(suggestions: planAheadSuggestions)
            }
            .overlay(alignment: .bottom) {
                if showingPendingTransactionsSheet {
                     ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation {
                                    showingPendingTransactionsSheet = false
                                }
                                Task { await vm.refreshData() }
                            }
                            
                        PendingTransactionsReviewView(
                            cashFlowID: vm.selectedCashFlow?.id ?? "",
                            onDismiss: {
                             withAnimation {
                                 showingPendingTransactionsSheet = false
                             }
                             Task { await vm.refreshData() }
                        })
                        .transition(.move(edge: .bottom))
                        .zIndex(102) 
                    }
                    .zIndex(102)
                }

                if let transaction = selectedTransactionForEdit {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation {
                                    selectedTransactionForEdit = nil
                                }
                            }
                        
                        EditTransactionView(
                            transaction: transaction,
                            onSave: { _ in
                                selectedTransactionForEdit = nil
                            },
                            onDelete: { tx in
                                Task {
                                    await vm.deleteTransaction(tx)
                                    selectedTransactionForEdit = nil
                                }
                            },
                            onCancel: {
                                selectedTransactionForEdit = nil
                            }
                        )
                        .transition(.move(edge: .bottom))
                    }
                    .zIndex(100)
                }
            }
        }
        .onAppear {
            Task {
                // Only load if not already loaded by LoginView
                if vm.selectedCashFlow == nil && vm.cashFlows.isEmpty {
                    await vm.loadInitial()
                    await vm.refreshData()
                } else if vm.selectedCashFlow != nil && vm.orderedItems.isEmpty {
                    // If cash flow is selected but no data yet, just refresh
                    await vm.refreshData()
                }
                
                await pendingTxsVm.refresh()
            }

            if biometricsEnabled {
                Task { await requestBiometricUnlock() }
            } else {
                biometricLocked = false
            }
        }
        .alert("זיהוי פנים", isPresented: $showBiometricAlert, presenting: biometricAlertMessage) { _ in
            Button("בסדר", role: .cancel) {
                biometricAlertMessage = nil
            }
        } message: { message in
            Text(message)
        }
        .overlay {
            if biometricsEnabled && biometricLocked {
                biometricLockView
            }
        }
        // The toolbar item for pending transactions has been moved below the biometrics section.
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: { vm.previousMonth() }) {
                Image(systemName: "chevron.backward")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.35)))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(monthName(vm.currentMonthDate))
                    .font(.headline)
                    .fontWeight(.bold)
                Text(String(Calendar.current.component(.year, from: vm.currentMonthDate)))
                    .font(.subheadline)
                    .foregroundColor(Theme.muted)
            }
            Spacer()
            Button(action: { vm.nextMonth() }) {
                Image(systemName: "chevron.forward")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.35)))
            }
            HStack(spacing: 10) {
                Button(action: { showingFilterSheet = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title3)
                        if transactionFilter.isActive {
                            Circle()
                                .fill(Theme.primary)
                                .frame(width: 8, height: 8)
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(FocusRingButtonStyle(cornerRadius: 24))
                .foregroundColor(Theme.primary)
                .accessibilityLabel("פתח סינון עסקאות")

                Button {
                    AppLogger.log("🔎 Search menu opened from cashflow cards")
                    showingSearchSheet = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                }
                .buttonStyle(FocusRingButtonStyle(cornerRadius: 24))
                .foregroundColor(Theme.primary)
                .accessibilityLabel("חיפוש עסקאות")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage {
            VStack(spacing: 10) {
                Text("שגיאה").font(.headline)
                Text(err)
                Button("נסה שוב") { Task { await vm.refreshData() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    if showWeeklyBudgetCard {
                        WeeklyBudgetCard(
                            info: weeklyBudgetInfo,
                            currencySymbol: currencySymbol(for: vm.selectedCashFlow?.currency ?? "ILS"),
                            format: formatNumber,
                            onAccountStatusTap: { showingAccountStatusSheet = true }
                        )
                    }
                    
                    if showMonthlyTargetCard {
                        MonthlyTargetCard(
                            target: monthlyGoalValue,
                            actual: vm.monthlyTotals.net,
                            currencySymbol: currencySymbol(for: vm.selectedCashFlow?.currency ?? "ILS"),
                            format: formatNumber,
                            onEdit: {
                                monthlyTargetEditingValue = monthlyGoalValue
                                showingMonthlyTargetSheet = true
                            },
                            onPlanAhead: {
                                showingPlanAheadSheet = true
                            }
                        )
                    }
                    
                    if showMonthlyTrendCard {
                        MonthlyTrendCard(
                            labels: vm.monthlyLabels,
                            netSeries: vm.netSeries,
                            expenseSeries: vm.expensesSeries,
                            incomeSeries: vm.incomeSeries,
                            currencySymbol: currencySymbol(for: vm.selectedCashFlow?.currency ?? "ILS")
                        )
                    }
                    summaryCard
                    ForEach(vm.orderedItems, id: \.id) { item in
                        itemView(for: item)
                    }
                    biometricToggleSection
                }
                .frame(maxWidth: 480, alignment: .trailing)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .background(Theme.background)
        }
    }

    @ViewBuilder
    private func itemView(for item: CashFlowDashboardViewModel.Item) -> some View {
        switch item {
        case .income:
            incomeSection(onEdit: { t in selectedTransactionForEdit = t })

        case .savings:
            savingsSection(onEdit: { t in selectedTransactionForEdit = t })

        case .nonCashflow:
            nonCashflowSection(onEdit: { t in selectedTransactionForEdit = t })

        case .sharedGroup(let group):
            GroupSectionCard(
                group: group,
                accent: groupAccentColor(for: group.title),
                currency: vm.selectedCashFlow?.currency ?? "ILS",
                onEditTransaction: { t in selectedTransactionForEdit = t }
            )

        case .category(let cat):
            CategorySummaryCard(
                category: cat,
                currency: vm.selectedCashFlow?.currency ?? "ILS",
                isWeekly: cat.weeklyDisplay,
                isCurrentMonth: vm.isCurrentMonth,
                onEdit: {
                    selectedCategoryForEdit = cat
                    editingTargetValue = cat.target
                    showingEditTargetSheet = true
                },
                onEditBudget: {
                    selectedCategoryForBudgetEdit = cat
                    editingBudgetValue = cat.target ?? 0
                    showingEditBudgetSheet = true
                },
                onPlanAhead: {
                    showingPlanAheadSheet = true
                },
                onEditTransaction: { t in
                    selectedTransactionForEdit = t
                }
            )
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        let totals = vm.monthlyTotals
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.and.arrow.up").foregroundColor(.secondary)
                Spacer()
            }
            HStack {
                Text("מעולה!").font(.headline)
                Spacer()
            }
            HStack {
                Text("\(monthName(vm.currentMonthDate)) הסתיים בתזרים \(totals.net >= 0 ? "חיובי" : "שלילי")")
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("₪").font(.system(size: 20, weight: .medium))
                    .foregroundColor(totals.net >= 0 ? .green : .red)
                Text(formatNumber(abs(totals.net)))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(totals.net >= 0 ? .green : .red)
                    .monospacedDigit()
                Spacer()
            }

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("סה\"כ הכנסות").font(.footnote).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text("₪").font(.caption).foregroundColor(.green)
                        Text(formatNumber(totals.income)).foregroundColor(.green).monospacedDigit()
                    }

                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("סה\"כ הוצאות").font(.footnote).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text("₪").font(.caption)
                        Text(formatNumber(totals.expenses)).monospacedDigit()
                    }
                    .foregroundColor(.primary)

                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }

    private var biometricToggleSection: some View {
        VStack(alignment: .trailing, spacing: 12) {
            HStack {
                Image(systemName: "faceid")
                    .foregroundColor(.secondary)
                Spacer()
                Text("כניסה עם Face ID")
                    .font(.headline)
            }
            Text(biometricsEnabled ? "זיהוי פנים מופעל ויידרש בכל כניסה למסך זה." : "אפשר כניסה באמצעות Face ID כדי להבטיח שרק אתה תראה את התזרים.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Button(biometricsEnabled ? "בטל זיהוי פנים" : "אפשר זיהוי פנים") {
                if biometricsEnabled {
                    biometricsEnabled = false
                    biometricLocked = false
                } else {
                    Task { await enableBiometricLogin() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(biometricsEnabled ? Color.red.opacity(0.15) : Color.blue.opacity(0.15)))
            .foregroundColor(biometricsEnabled ? .red : .blue)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    private func monthName(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "LLLL"
        return f.string(from: d).capitalized
    }
    
    private func formatNumber(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }
    
    private func groupAccentColor(for title: String) -> Color {
        if title.contains("קבוע") { return .pink }
        if title.contains("משתנ") { return .yellow }
        if title.contains("חיסכון") { return .orange }
        return .blue
    }

    private var biometricLockView: some View {
        VStack(spacing: 12) {
            Image(systemName: "faceid")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.accentColor)
            Text("אנא אמת את זהותך בעזרת Face ID כדי להמשיך.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("נסה שוב") {
                Task { await requestBiometricUnlock() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.45).ignoresSafeArea())
    }

    private var visibleCategories: [CashFlowDashboardViewModel.CategorySummary] {
        vm.orderedItems.compactMap {
            if case .category(let cat) = $0 {
                return cat
            }
            return nil
        }
    }

    private var overBudgetCategory: CashFlowDashboardViewModel.CategorySummary? {
        visibleCategories
            .filter { ($0.target ?? 0) > 0 && $0.totalSpent > ($0.target ?? 0) }
            .sorted { ($0.totalSpent - ($0.target ?? 0)) > ($1.totalSpent - ($1.target ?? 0)) }
            .first
    }

    private var planAheadSuggestions: [PlanAheadSuggestion] {
        var suggestions = visibleCategories.compactMap { category -> PlanAheadSuggestion? in
            guard let target = category.target, target > 0 else { return nil }
            let saved = min(category.totalSpent, target)
            let remaining = max(target - saved, 0)
            let monthlyContribution = max(50, remaining / Double(max(category.weeksInMonth, 1)))
            let description = "עדיין לא הושלם \(formatNumber(remaining)) ₪ מתוך \(formatNumber(target)) ₪"
            return PlanAheadSuggestion(
                title: category.name,
                description: description,
                target: target,
                saved: saved,
                monthlyContribution: monthlyContribution
            )
        }
        if suggestions.count < 3 {
            suggestions.append(contentsOf: [
                PlanAheadSuggestion(
                    title: "נסיעת חורף משפחתית",
                    description: "חיסכון לנסיעה חוץ לארץ בתוך שנה.",
                    target: 7200,
                    saved: 2700,
                    monthlyContribution: 600
                ),
                PlanAheadSuggestion(
                    title: "חליפה חדשה לעבודה",
                    description: "ציוד מקצועי שיגיע בעוד שישה חודשים.",
                    target: 2400,
                    saved: 1100,
                    monthlyContribution: 200
                )
            ])
        }
        return Array(suggestions.prefix(3))
    }

    private struct PlanAheadSuggestion: Identifiable {
        let id = UUID().uuidString
        let title: String
        let description: String
        let target: Double
        let saved: Double
        let monthlyContribution: Double
        var progress: Double {
            guard target > 0 else { return 0 }
            return min(saved / target, 1.0)
        }
    }

    private func enableBiometricLogin() async {
        do {
            try await BiometricAuthManager.shared.authenticate(reason: "הפעל זיהוי פנים לתזרים המזומנים")
            await MainActor.run {
                biometricsEnabled = true
                biometricLocked = false
            }
        } catch {
            await MainActor.run {
                presentBiometricError(error)
            }
        }
    }

    private func requestBiometricUnlock() async {
        await MainActor.run {
            biometricLocked = true
        }
        do {
            try await BiometricAuthManager.shared.authenticate(reason: "אנא אמת את זהותך כדי לצפות בתזרים")
            await MainActor.run {
                biometricLocked = false
            }
        } catch {
            await MainActor.run {
                presentBiometricError(error)
            }
        }
    }

    @MainActor
    private func presentBiometricError(_ error: Error) {
        biometricAlertMessage = error.localizedDescription
        showBiometricAlert = true
    }

    private var weeklyBudgetInfo: WeeklyBudgetInfo? {
        let weeklyCategories = vm.orderedItems.compactMap { item -> CashFlowDashboardViewModel.CategorySummary? in
            if case .category(let cat) = item, !cat.isFixed && cat.weeklyDisplay {
                return cat
            }
            return nil
        }
        guard !weeklyCategories.isEmpty else { return nil }

        let calendar = Calendar(identifier: .gregorian)
        let currentWeek = calendar.component(.weekOfMonth, from: vm.currentMonthDate)
        let expectedPerWeek = weeklyCategories.reduce(0) { $0 + $1.weeklyExpected }
        let spentThisWeek = weeklyCategories.reduce(0) { result, category in
            result + (category.weekly[currentWeek] ?? 0)
        }
        let maxWeeks = weeklyCategories.map { $0.weeksInMonth }.max() ?? 4
        let weeks = (1...maxWeeks).map { week -> WeeklyBudgetWeek in
            let weekSpent = weeklyCategories.reduce(0) { subTotal, category in
                subTotal + (category.weekly[week] ?? 0)
            }
            return WeeklyBudgetWeek(weekNumber: week, spent: weekSpent, expected: expectedPerWeek)
        }

        return WeeklyBudgetInfo(
            totalExpected: expectedPerWeek,
            spentThisWeek: spentThisWeek,
            remaining: expectedPerWeek - spentThisWeek,
            weeks: weeks
        )
    }

    private var monthlyGoalValue: Double? {
        if let custom = vm.monthlyTargetGoal, custom > 0 {
            return custom
        }
        if vm.savingsExpected > 0 {
            return vm.savingsExpected
        }
        return nil
    }

    private var currentCurrencySymbol: String {
        currencySymbol(for: vm.selectedCashFlow?.currency ?? "ILS")
    }

    private var filterableCategories: [String] {
        var seen: Set<String> = []
        return vm.orderedItems.compactMap { item in
            if case .category(let cat) = item, !seen.contains(cat.name) {
                seen.insert(cat.name)
                return cat.name
            }
            return nil
        }
    }

    private var paymentMethodOptions: [String] {
        var seen: Set<String> = []
        var list: [String] = []
        for tx in vm.transactions {
            let method = tx.accountDisplayName
            if seen.insert(method).inserted {
                list.append(method)
            }
        }
        if list.isEmpty {
            list.append("עו\"ש ראשי")
        }
        return list
    }

    private struct WeeklyBudgetCard: View {
        let info: WeeklyBudgetInfo?
        let currencySymbol: String
        let format: (Double) -> String
        let onAccountStatusTap: () -> Void
        @State private var expanded = false

        var body: some View {
            DashboardCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("כמה נשאר להוציא השבוע")
                            .font(.headline)
                        Spacer()
                        Menu {
                            Button("רענן מקורות", action: {})
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let info = info {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("₪")
                                .font(.title3)
                                .foregroundColor(info.remaining >= 0 ? Theme.success : Theme.danger)
                            Text(format(abs(info.remaining)))
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(info.remaining >= 0 ? Theme.success : Theme.danger)
                                .monospacedDigit()
                        }
                        Text(info.remaining >= 0 ? "עוד שבוע אחד לפני החריגה" : "חריגה של \(format(abs(info.remaining))) ₪")
                            .font(.subheadline)
                            .foregroundColor(info.remaining >= 0 ? Theme.success : Theme.danger)
                        ProgressCapsule(progress: info.totalExpected > 0 ? info.spentThisWeek / info.totalExpected : 0,
                                         color: Theme.primary)
                            .frame(height: 10)
                        HStack {
                            budgetSummary(title: "נוצל", value: info.spentThisWeek)
                            Spacer()
                            budgetSummary(title: "צפוי", value: info.totalExpected)
                        }
                        Button(action: { withAnimation(.easeInOut) { expanded.toggle() } }) {
                            Text(expanded ? "הסתר פירוט שבועי" : "הצג פירוט שבועי")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        if expanded {
                            VStack(spacing: 10) {
                                ForEach(info.weeks) { week in
                                    WeeklyBudgetWeekRow(week: week, currencySymbol: currencySymbol, format: format)
                                }
                            }
                            .transition(.opacity)
                        }
                    } else {
                        Text("אין קטגוריות שבועיות פעילות החודש.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Button(action: onAccountStatusTap) {
                        Text("ומה מצב העו\"ש?")
                            .font(.subheadline)
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.success)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: info)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("כמה נשאר להוציא השבוע")
            .accessibilityValue(info?.remainingDescription ?? "אין קטגוריות שבועיות פעילות")
        }

        private func budgetSummary(title: String, value: Double) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundColor(.secondary)
                HStack(spacing: 2) {
                    Text(format(value)).font(.headline).monospacedDigit()
                    Text(currencySymbol).font(.caption2)
                }

            }
        }

        private struct WeeklyBudgetWeekRow: View {
            let week: WeeklyBudgetWeek
            let currencySymbol: String
            let format: (Double) -> String

            var body: some View {
                HStack {
                    Text("שבוע \(week.weekNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    DataColumn(label: "יצא", value: week.spent, currencySymbol: currencySymbol, format: format)
                    Spacer()
                    DataColumn(label: "נשאר", value: max(week.expected - week.spent, 0), currencySymbol: currencySymbol, format: format)
                }
            }

            private struct DataColumn: View {
                let label: String
                let value: Double
                let currencySymbol: String
                let format: (Double) -> String

                var body: some View {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(label).font(.caption2).foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Text(format(value)).font(.subheadline).monospacedDigit()
                            Text(currencySymbol).font(.caption2)
                        }

                    }
                }
            }
        }

    }


    private struct MonthlyTargetCard: View {
        let target: Double?
        let actual: Double
        let currencySymbol: String
        let format: (Double) -> String
        let onEdit: () -> Void
        let onPlanAhead: () -> Void

        var body: some View {
            DashboardCard {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("היעד החודשי")
                            .font(.headline)
                        Spacer()
                        Menu {
                            Button("על היעד", action: {})
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                    if let target = target {
                        amountView(amount: target, currencySymbol: currencySymbol, format: format)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Theme.primary)
                        ProgressCapsule(progress: target > 0 ? actual / target : 0, color: Theme.primary)
                            .frame(height: 10)
                        let difference = target - actual
                        Text(difference >= 0 ? "נשאר להשיג \(format(difference)) ₪" : "חרגת ב־\(format(abs(difference))) ₪")
                            .font(.caption)
                            .foregroundColor(difference >= 0 ? Theme.success : Theme.danger)
                    } else {
                        Text("טרם נקבע יעד חודשי")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("נטו נוכחי").font(.caption).foregroundColor(.secondary)
                            HStack(spacing: 2) {
                                Text(format(abs(actual))).font(.headline).monospacedDigit()
                                Text(currencySymbol).font(.caption2)
                            }

                        }
                        Spacer()
                        Text(actual >= 0 ? "חיובי" : "שלילי")
                            .font(.caption)
                            .foregroundColor(actual >= 0 ? Theme.success : Theme.danger)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill((actual >= 0 ? Theme.success : Theme.danger).opacity(0.1))
                            )
                    }

                    HStack(spacing: 12) {
                        Button("לעריכה", action: onEdit)
                            .buttonStyle(.bordered)
                            .accessibilityLabel("עריכת היעד החודשי")
                        Button("לתכנן קדימה", action: onPlanAhead)
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.primary)
                            .accessibilityLabel("פתח תכניות חסכון עתידיות")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("היעד החודשי")
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint("הכנסה נטו \(format(abs(actual))) ₪")
        }

        @ViewBuilder
        private func amountView(amount: Double, currencySymbol: String, format: (Double) -> String) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(format(amount)).monospacedDigit()
                Text(currencySymbol).font(.title3)
            }

        }

        private var accessibilityValueText: String {
            guard let target = target else {
                return "טרם נקבע יעד"
            }
            let difference = target - actual
            if difference >= 0 {
                return "נשאר להשיג \(format(abs(difference))) ₪ מתוך \(format(target)) ₪"
            }
            return "חריגה של \(format(abs(difference))) ₪"
        }
    }

    private struct DashboardCard<Content: View>: View {
        let background: Color
        let content: Content

        init(background: Color = Theme.cardBackground, @ViewBuilder content: () -> Content) {
            self.background = background
            self.content = content()
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(background)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
            )
        }
    }

    private struct PlaceholderSheet: View {
        let title: String
        let description: String
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                VStack(spacing: 20) {
                    Text(description)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Button("סגור") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .navigationTitle(title)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("סגור") { dismiss() }
                }
            }
        }
    }

    private struct MonthlyTrendCard: View {
        let labels: [String]
        let netSeries: [Double]
        let expenseSeries: [Double]
        let incomeSeries: [Double]
        let currencySymbol: String
        @State private var selectedMonthIndex: Int?

        private var maxValue: Double {
            netSeries.max() ?? 0
        }

        private var minValue: Double {
            netSeries.min() ?? 0
        }

        private func format(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? "0"
        }

        private var monthDetails: [MonthlyTrendDetail] {
            var details: [MonthlyTrendDetail] = []
            let count = min(labels.count, netSeries.count)
            for idx in 0..<count {
                let detail = MonthlyTrendDetail(
                    label: labels[idx],
                    net: netSeries[idx],
                    income: incomeSeries.indices.contains(idx) ? incomeSeries[idx] : 0,
                    expense: expenseSeries.indices.contains(idx) ? expenseSeries[idx] : 0
                )
                details.append(detail)
            }
            return details
        }

        private var selectedMonthDetail: MonthlyTrendDetail? {
            guard let idx = selectedMonthIndex, monthDetails.indices.contains(idx) else { return nil }
            return monthDetails[idx]
        }

        var body: some View {
            DashboardCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("מבט חודשי")
                            .font(.headline)
                        Spacer()
                        Text("גרף נטו")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if netSeries.isEmpty {
                        Text("אין מספיק נתונים להצגה.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(format(maxValue))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(format(minValue))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            SparklineChart(values: netSeries, lineColor: Theme.primary)
                                .frame(height: 100)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(monthDetails.enumerated()), id: \.offset) { index, detail in
                                    Button(action: {
                                        selectedMonthIndex = index
                                    }) {
                                        Text(detail.label)
                                            .font(.caption2)
                                            .bold()
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(selectedMonthIndex == index ? Theme.primary : Theme.primary.opacity(0.2))
                                            )
                                            .foregroundColor(selectedMonthIndex == index ? .white : Theme.primary)
                                    }
                                    .accessibilityLabel("בחר חודש \(detail.label) להציג נתונים")
                                }
                            }
                        }
                        if let detail = selectedMonthDetail {
                            TooltipView(text: detail.tooltipText, accent: Theme.primary)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                        HStack {
                            StatColumn(label: "הכנסות", value: incomeSeries.last ?? 0, color: Theme.success, currencySymbol: currencySymbol)
                            StatColumn(label: "הוצאות", value: expenseSeries.last ?? 0, color: Theme.danger, currencySymbol: currencySymbol)
                            StatColumn(label: "נטו", value: netSeries.last ?? 0, color: (netSeries.last ?? 0) >= 0 ? Theme.success : Theme.danger, currencySymbol: currencySymbol)
                        }
                    }
                }
            }
        }

        private struct StatColumn: View {
            let label: String
            let value: Double
            let color: Color
            let currencySymbol: String

            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.caption).foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(currencySymbol).font(.caption2).foregroundColor(color)
                        Text(format(value)).font(.headline).foregroundColor(color).monospacedDigit()
                    }

                }
            }

            private func format(_ value: Double) -> String {
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.maximumFractionDigits = 1
                formatter.groupingSeparator = ","
                return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
            }
        }
    }

    private struct MonthlyTrendDetail {
        let label: String
        let net: Double
        let income: Double
        let expense: Double

        var tooltipText: String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.groupingSeparator = ","
            let netText = formatter.string(from: NSNumber(value: abs(net))) ?? "0"
            let incomeText = formatter.string(from: NSNumber(value: income)) ?? "0"
            let expenseText = formatter.string(from: NSNumber(value: expense)) ?? "0"
            let netSign = net >= 0 ? "חיובי" : "שלילי"
            return "\(label)\n\(netSign) \(netText) ₪ • הכנסות \(incomeText) ₪ • הוצאות \(expenseText) ₪"
        }
    }

    private struct TooltipView: View {
        let text: String
        let accent: Color

        var body: some View {
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accent.opacity(0.4), lineWidth: 1)
                )
                .multilineTextAlignment(.trailing)
        }
    }

    private struct SparklineChart: View {
        let values: [Double]
        let lineColor: Color

        var body: some View {
            GeometryReader { geo in
                let points = normalizedPoints(in: geo.size)
                Path { path in
                    guard points.count > 1 else { return }
                    path.move(to: points[0])
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(lineColor, lineWidth: 2)
                if points.count > 1 {
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() {
                            path.addLine(to: point)
                        }
                        path.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                        path.addLine(to: CGPoint(x: points.first!.x, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [lineColor.opacity(0.2), lineColor.opacity(0.01)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }

        private func normalizedPoints(in size: CGSize) -> [CGPoint] {
            guard let minValue = values.min(), let maxValue = values.max(), maxValue != minValue else {
                return values.enumerated().map { idx, _ in
                    CGPoint(x: size.width * CGFloat(idx) / CGFloat(max(values.count - 1, 1)), y: size.height / 2)
                }
            }
            let range = maxValue - minValue
            return values.enumerated().map { idx, value in
                let x = size.width * CGFloat(idx) / CGFloat(max(values.count - 1, 1))
                let y = size.height * (1 - CGFloat((value - minValue) / range))
                return CGPoint(x: x, y: y)
            }
        }
    }

    private struct TransactionFilter: Equatable {
        var includeIncome = true
        var includeExpenses = true
        var selectedCategories: Set<String> = []
        var selectedPaymentMethods: Set<String> = []
        var minAmount: Double?
        var maxAmount: Double?
        var startDate: Date?
        var endDate: Date?

        var isActive: Bool {
            !includeIncome || !includeExpenses || !selectedCategories.isEmpty || !selectedPaymentMethods.isEmpty
                || minAmount != nil || maxAmount != nil || startDate != nil || endDate != nil
        }

        func matches(_ transaction: Transaction, accountName: String) -> Bool {
            if transaction.isIncome && !includeIncome { return false }
            if !transaction.isIncome && !includeExpenses { return false }
            if !selectedCategories.isEmpty && !selectedCategories.contains(transaction.effectiveCategoryName) {
                return false
            }
            if !selectedPaymentMethods.isEmpty && !selectedPaymentMethods.contains(accountName) {
                return false
            }
            let amount = abs(transaction.normalizedAmount)
            if let minAmount, amount < minAmount { return false }
            if let maxAmount, amount > maxAmount { return false }
            if let startDate, let date = transaction.parsedDate, date < startDate { return false }
            if let endDate, let date = transaction.parsedDate, date > endDate { return false }
            return true
        }
    }

    private struct TransactionFilterSheet: View {
        @Binding var filter: TransactionFilter
        let categories: [String]
        let paymentMethods: [String]
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section("סוגי פעילות") {
                        Toggle("הכנסות", isOn: $filter.includeIncome)
                        Toggle("הוצאות", isOn: $filter.includeExpenses)
                    }
                    Section("טווח סכומים (₪)") {
                        HStack {
                            TextField("מ־0", text: amountBinding(for: $filter.minAmount))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("עד", text: amountBinding(for: $filter.maxAmount))
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button("נקה סכום") {
                            filter.minAmount = nil
                            filter.maxAmount = nil
                        }
                        .buttonStyle(.bordered)
                    }
                    Section("טווח תאריכים") {
                        DatePicker("מהתאריך", selection: dateBinding(for: $filter.startDate), displayedComponents: .date)
                        DatePicker("עד התאריך", selection: dateBinding(for: $filter.endDate), displayedComponents: .date)
                        Button("נקה תאריכים") {
                            filter.startDate = nil
                            filter.endDate = nil
                        }
                        .buttonStyle(.bordered)
                    }
                    Section("קטגוריות") {
                        if categories.isEmpty {
                            Text("עדיין לא זוהו קטגוריות")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(categories, id: \.self) { category in
                                buttonRow(title: category, isSelected: filter.selectedCategories.contains(category)) {
                                    if filter.selectedCategories.contains(category) {
                                        filter.selectedCategories.remove(category)
                                    } else {
                                        filter.selectedCategories.insert(category)
                                    }
                                }
                            }
                            if !filter.selectedCategories.isEmpty {
                                Button("נקה בחירת קטגוריות") {
                                    filter.selectedCategories.removeAll()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    Section("חשבונות") {
                        if paymentMethods.isEmpty {
                            Text("עדיין לא נרשמו חשבונות")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(paymentMethods, id: \.self) { method in
                                buttonRow(title: method, isSelected: filter.selectedPaymentMethods.contains(method)) {
                                    if filter.selectedPaymentMethods.contains(method) {
                                        filter.selectedPaymentMethods.remove(method)
                                    } else {
                                        filter.selectedPaymentMethods.insert(method)
                                    }
                                }
                            }
                            if !filter.selectedPaymentMethods.isEmpty {
                                Button("נקה בחירת חשבונות") {
                                    filter.selectedPaymentMethods.removeAll()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .navigationTitle("סינון")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("ביטול") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("הצג") { dismiss() }
                    }
                }
            }
        }

        private func buttonRow(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack {
                    Text(title)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.primary)
                    }
                }
            }
            .buttonStyle(.plain)
        }

        private func amountBinding(for binding: Binding<Double?>) -> Binding<String> {
            Binding<String>(
                get: {
                    guard let value = binding.wrappedValue else { return "" }
                    return amountFormatter.string(from: NSNumber(value: value)) ?? ""
                },
                set: { newValue in
                    let cleaned = newValue.replacingOccurrences(of: ",", with: "")
                    binding.wrappedValue = Double(cleaned)
                }
            )
        }

        private func dateBinding(for binding: Binding<Date?>) -> Binding<Date> {
            Binding<Date>(
                get: { binding.wrappedValue ?? Date() },
                set: { binding.wrappedValue = $0 }
            )
        }

        private let amountFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.groupingSeparator = ","
            return formatter
        }()
    }

    private struct TransactionSearchSheet: View {
        @EnvironmentObject private var vm: CashFlowDashboardViewModel
        @Environment(\.dismiss) private var dismiss
        let filter: TransactionFilter
        let currencySymbol: String
        @State private var searchText: String = ""
        @State private var debouncedQuery: String = ""
        @State private var debounceTask: Task<Void, Never>?
        @State private var editingTransaction: Transaction? = nil
        @State private var windowChunkCount = 1

        private let minSearchLength = 2
        private let debounceDelay: UInt64 = 500_000_000 // 0.5s
        private let monthsPerChunk = 4

        private static let monthKeyFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()

        private static let displayMonthFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "LLLL yyyy"
            formatter.locale = Locale(identifier: "he_IL")
            return formatter
        }()

        private var visibleMonthWindow: Int {
            max(monthsPerChunk * max(windowChunkCount, 1), monthsPerChunk)
        }

        private var windowStartKey: String? {
            let calendar = Calendar(identifier: .gregorian)
            guard
                let startOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())),
                let startDate = calendar.date(byAdding: .month, value: -(visibleMonthWindow - 1), to: startOfCurrentMonth)
            else {
                return nil
            }
            return Self.monthKeyFormatter.string(from: startDate)
        }

        private var windowStartLabel: String? {
            guard let key = windowStartKey,
                  let date = Self.monthKeyFormatter.date(from: key)
            else { return nil }
            return Self.displayMonthFormatter.string(from: date)
        }

        private var earliestAvailableMonthKey: String? {
            vm.transactions.compactMap { $0.flowMonthKey }.min()
        }

        private var canLoadMoreMonths: Bool {
            guard
                let earliest = earliestAvailableMonthKey,
                let startKey = windowStartKey
            else {
                return false
            }
            return earliest < startKey
        }

        var body: some View {
            NavigationStack {
                ZStack(alignment: .bottom) {
                    List {
                        Section(header: Text("תוצאות (\(results.count))").frame(maxWidth: .infinity, alignment: .leading)) {
                            if !isReadyToSearch {
                                Text("הקלד לפחות שתי אותיות כדי להתחיל לחפש")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .multilineTextAlignment(.trailing)
                            } else if results.isEmpty {
                                Text("לא נמצאו עסקאות")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .multilineTextAlignment(.trailing)
                            }

                            ForEach(results, id: \.id) { tx in
                                TransactionSearchRow(transaction: tx, currencySymbol: currencySymbol)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingTransaction = tx
                                    }
                            }
                        }
                        if isReadyToSearch && canLoadMoreMonths {
                            Section {
                                loadOlderResultsButton
                            }
                        }
                    }
                    .listStyle(.insetGrouped)

                    if let transaction = editingTransaction {
                        ZStack {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation {
                                        editingTransaction = nil
                                    }
                                }

                            EditTransactionView(
                                transaction: transaction,
                                onSave: { updatedTx in
                                    Task {
                                        do {
                                            _ = try await vm.updateTransaction(
                                                updatedTx,
                                                categoryName: updatedTx.effectiveCategoryName,
                                                notes: updatedTx.notes,
                                                flowMonth: updatedTx.flow_month
                                            )
                                        } catch {
                                            AppLogger.log("⚠️ Failed to update reviewed transaction: \(error)", force: true)
                                        }
                                        await MainActor.run {
                                            withAnimation {
                                                editingTransaction = nil
                                            }
                                        }
                                    }
                                },
                                onDelete: { deletedTx in
                                    Task {
                                        await vm.deleteTransaction(deletedTx)
                                        await MainActor.run {
                                            withAnimation {
                                                editingTransaction = nil
                                            }
                                        }
                                    }
                                },
                                onCancel: {
                                    withAnimation {
                                        editingTransaction = nil
                                    }
                                }
                            )
                            .transition(.move(edge: .bottom))
                        }
                        .zIndex(100)
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                .navigationTitle("חיפוש עסקאות")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("סגור") { dismiss() }
                    }
                }
                .environment(\.layoutDirection, .rightToLeft) // Fix for RTL alignment
                .onAppear {
                    AppLogger.log("🔍 TransactionSearchSheet appeared (filter active=\(filter.isActive))")
                }
                .onChange(of: searchText) { _, newValue in
                    AppLogger.log("🔍 TransactionSearchSheet search text updated: '\(newValue)'")
                    debounceTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    debounceTask = Task { @MainActor in
                        do {
                            try await Task.sleep(nanoseconds: debounceDelay)
                            debouncedQuery = trimmed
                        } catch {
                            // Task cancelled, do not update query
                        }
                    }
                }
                .onChange(of: debouncedQuery) { _, _ in
                    windowChunkCount = 1
                }
                .onDisappear {
                    debounceTask?.cancel()
                }
            }
        }

        private var results: [Transaction] {
            guard isReadyToSearch else { return [] }
            return vm.transactions
                .filter { filter.matches($0, accountName: $0.accountDisplayName) && matchesSearchText($0, query: debouncedQuery) && transactionInWindow($0) }
                .sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
        }

        private var isReadyToSearch: Bool {
            debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).count >= minSearchLength
        }

        private func transactionInWindow(_ transaction: Transaction) -> Bool {
            guard
                let monthKey = transaction.flowMonthKey,
                let startKey = windowStartKey
            else {
                return false
            }
            return monthKey >= startKey
        }

        private func matchesSearchText(_ transaction: Transaction, query: String) -> Bool {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard query.count >= minSearchLength else { return false }
            let lower = query.lowercased()
            if transaction.business_name?.lowercased().contains(lower) == true { return true }
            if transaction.effectiveCategoryName.lowercased().contains(lower) { return true }
            if transaction.accountDisplayName.lowercased().contains(lower) { return true }
            if formatNumber(abs(transaction.normalizedAmount)).lowercased().contains(lower) { return true }
            return false
        }

        private var loadOlderResultsButton: some View {
            Button {
                windowChunkCount += 1
            } label: {
                VStack(spacing: 6) {
                    HStack {
                        Text("טען תוצאות ישנות יותר")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    if let label = windowStartLabel {
                        Text("(מציג תוצאות מ\(label))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.blue.opacity(0.7), lineWidth: 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.systemBackground))
                        )
                )
            }
        }

        private func formatNumber(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }
    }

    private struct TransactionSearchRow: View {
        let transaction: Transaction
        let currencySymbol: String

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.business_name?.isEmpty == false ? transaction.business_name! : transaction.effectiveCategoryName)
                        .font(.body)
                    HStack(spacing: 6) {
                        Text(transaction.effectiveCategoryName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(transaction.accountDisplayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Text(dateString(transaction.parsedDate))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatAmount())
                        .font(.headline)
                        .monospacedDigit()
                    Text(currencySymbol).font(.caption2).foregroundColor(.secondary)
                    if let flowMonth = transaction.flow_month {
                         Text(flowMonth).font(.caption2).foregroundColor(.blue)
                    }
                }
            }
        }

        private func formatAmount() -> String {
            let value = abs(transaction.normalizedAmount)
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }

        private func dateString(_ date: Date?) -> String {
            guard let date else { return "—" }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "he_IL")
            formatter.dateFormat = "d.M.yy"
            return formatter.string(from: date)
        }
    }

    private struct AccountStatusSheet: View {
        let snapshots: [CashFlowDashboardViewModel.AccountSnapshot]
        let currencySymbol: String
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                List {
                    if snapshots.isEmpty {
                        Text("אין נתונים עבור חשבונות כרגע")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(snapshots) { snapshot in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(snapshot.accountName)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(formatCurrency(snapshot.balance)) \(currencySymbol)")
                                        .foregroundColor(snapshot.balance >= 0 ? Theme.success : Theme.danger)
                                        .font(.subheadline)
                                }
                                HStack {
                                    Text("חיובים מתוכננים")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatCurrency(snapshot.pendingCharges))
                                        .font(.caption)
                                        .foregroundColor(Theme.warning)
                                }
                                Text("עודכן \(relativeTime(snapshot.lastUpdated))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 6)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("\(snapshot.accountName), יתרה \(formatCurrency(snapshot.balance)) שקלים")
                            .accessibilityHint("חיובים מתוכננים: \(formatCurrency(snapshot.pendingCharges)) שקלים")
                        }
                    }
                }
                .navigationTitle("סטטוס עו\"ש")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("סגור") { dismiss() }
                    }
                }
            }
        }

        private func formatCurrency(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }

        private func relativeTime(_ date: Date) -> String {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = Locale(identifier: "he_IL")
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }

    private struct PlanAheadSheet: View {
        let suggestions: [PlanAheadSuggestion]
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(suggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(suggestion.title)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(formatCurrency(suggestion.saved)) ₪")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Text(suggestion.description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                ProgressView(value: suggestion.progress)
                                    .tint(Theme.primary)
                                    .animation(.easeInOut, value: suggestion.progress)
                                HStack {
                                    Text("יעד: \(formatCurrency(suggestion.target)) ₪")
                                        .font(.caption)
                                    Spacer()
                                    Text("חודשי: \(formatCurrency(suggestion.monthlyContribution)) ₪")
                                        .font(.caption)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Theme.cardBackground)
                                    .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 3)
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        Button("הוסף תכנית חדשה") {
                            // Placeholder - future integration
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .accessibilityLabel("הוסף תכנית חסכון חדשה")
                    }
                    .padding()
                }
                .navigationTitle("לתכנן קדימה")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("סגור") { dismiss() }
                    }
                }
            }
        }

        private func formatCurrency(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
        }
    }
}

// MARK: - Sections
private extension CashflowCardsView {
    private func incomeSection(onEdit: @escaping (Transaction) -> Void) -> some View {
        SectionCard(
            title: "הכנסות",
            accent: .green,
            expectedLabel: "צפוי להיכנס",
            expectedValue: vm.incomeExpected,
            actualLabel: "נכנס",
            actualValue: vm.incomeTotal,
            currency: vm.selectedCashFlow?.currency ?? "ILS",
            isCurrentMonth: vm.isCurrentMonth
        ) {
            ForEach(vm.incomeTransactions, id: \.id) { t in
                transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .green, onEdit: onEdit)
            }
        }
    }

    private func savingsSection(onEdit: @escaping (Transaction) -> Void) -> some View {
        SectionCard(
            title: "הפקדות לחיסכון",
            accent: .orange,
            expectedLabel: "צפוי לצאת",
            expectedValue: vm.savingsExpected,
            actualLabel: "יצא",
            actualValue: vm.savingsTotal,
            currency: vm.selectedCashFlow?.currency ?? "ILS",
            isCurrentMonth: vm.isCurrentMonth
        ) {
            ForEach(vm.savingsTransactions, id: \.id) { t in
                transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .orange, onEdit: onEdit)
            }
        }
    }

    private func nonCashflowSection(onEdit: @escaping (Transaction) -> Void) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Menu { Button("עוד", action: {}) } label: { Image(systemName: "ellipsis").foregroundColor(.secondary) }
                    Spacer()
                }
                HStack(alignment: .top) {
                    Text("לא בתזרים").font(.title2).bold()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("הכנסות לא תזרימיות").font(.footnote).foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text(formatNumber(vm.excludedIncomeTotal)).font(.headline).foregroundColor(.green).monospacedDigit()
                            Text("₪").font(.caption).foregroundColor(.green)
                        }

                    }
                    Spacer()
                }
            }
            .padding(16)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup("פירוט הכנסות לא תזרימיות") {
                    VStack(spacing: 8) {
                        ForEach(vm.excludedIncome, id: \.id) { t in
                            transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .green, onEdit: onEdit)
                        }
                    }
                }.accentColor(.primary)
                DisclosureGroup("פירוט הוצאות לא תזרימיות") {
                    VStack(spacing: 8) {
                        ForEach(vm.excludedExpense, id: \.id) { t in
                            transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .pink, onEdit: onEdit)
                        }
                    }
                }.accentColor(.primary)
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }

    private func groupSection(group: CashFlowDashboardViewModel.GroupSummary, accent: Color) -> some View {
        GroupSectionCard(group: group, accent: accent, currency: vm.selectedCashFlow?.currency ?? "ILS", onEditTransaction: { t in selectedTransactionForEdit = t })
    }


    private func transactionRow(_ t: Transaction, currency: String, highlight: Color, onEdit: @escaping (Transaction) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(shortDate(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                HStack(spacing: 4) {
                    Text(formatNumber(abs(t.normalizedAmount))).foregroundColor(highlight).monospacedDigit()
                    Text("₪").font(.caption).foregroundColor(highlight)
                }
                .font(.headline).frame(minWidth: 80, alignment: .leading)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        onEdit(t)
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundColor(.secondary).frame(width: 30)
                }
            }
            Text(t.business_name?.isEmpty == false ? t.business_name! : "—").font(.subheadline).foregroundColor(t.business_name?.isEmpty == false ? .primary : .secondary).frame(maxWidth: .infinity, alignment: .leading)
            if let note = t.notes, !note.isEmpty { Text(note).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            if let pm = t.payment_method, !pm.isEmpty { Text(pm).font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            Divider().padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    private func shortDate(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "he_IL")
        f.dateFormat = "d.M.yy"
        return f.string(from: d)
    }

}

// MARK: - Helper Views
private extension CashflowCardsView {
    struct FloatingActionButton: View {
        let count: Int
        let action: () -> Void
        @State private var isAnimating = false

        var body: some View {
            Button(action: action) {
                ZStack(alignment: .topTrailing) {
                    Text("לאישור היומי שלך")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Theme.primary, Theme.primary.opacity(0.7)]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .scaleEffect(isAnimating ? 1.1 : 1.0)

                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.red))
                            .offset(x: 8, y: -8)
                            .transition(.scale.animation(.spring()))
                    }
                }
            }
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }

    struct SectionCard<Content: View>: View {
        let title: String
        let accent: Color
        let expectedLabel: String
        let expectedValue: Double
        let actualLabel: String
        let actualValue: Double
        let currency: String
        let isCurrentMonth: Bool
        @ViewBuilder var content: Content
        @State private var expanded = false

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Menu { Button("עוד", action: {}) } label: { Image(systemName: "ellipsis").foregroundColor(.secondary) }
                        Spacer()
                    }
                    HStack { Text(title).font(.title3).bold(); Spacer() }
                    VStack(alignment: .leading, spacing: 8) {
                        if isCurrentMonth {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(expectedLabel).font(.footnote).foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Text(formatAmount(expectedValue)).font(.headline).foregroundColor(accent).monospacedDigit()
                                        Text("₪").font(.caption).foregroundColor(accent)
                                    }

                                }
                                Spacer()
                            }
                        } else {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(actualLabel).font(.footnote).foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Text(formatAmount(actualValue)).font(.title).fontWeight(.bold).foregroundColor(accent).monospacedDigit()
                                        Text("₪").font(.subheadline).foregroundColor(accent)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(expectedLabel).font(.caption2).foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Text(formatAmount(expectedValue)).font(.caption).foregroundColor(.secondary).monospacedDigit()
                                        Text("₪").font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        ProgressCapsule(progress: progress, color: accent).frame(height: 12)
                    }
                }
                .padding(16)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }) {
                        HStack {
                            Text("פירוט חודשי").foregroundColor(.primary)
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    if expanded { VStack(spacing: 8) { content }.transition(.opacity) }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Theme.cardBackground)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
            )
        }
        private var progress: Double {
            guard expectedValue > 0 else { return 0 }
            // Don't clamp to 1 - allow overflow to show over-budget visually
            return max(0, actualValue / expectedValue)
        }
        private func formatAmount(_ v: Double) -> String {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 1; f.groupingSeparator = ","; return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
        }
    }

    struct ProgressCapsule: View {
        let progress: Double
        let color: Color

        var body: some View {
            GeometryReader { geo in
                // Allow overflow but clamp the visual width to the capsule width.
                let displayProgress = max(0, progress)
                let fillWidth = min(displayProgress, 1) * geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: displayProgress > 1 ? geo.size.width : fillWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    struct CategorySummaryCard: View {
        let category: CashFlowDashboardViewModel.CategorySummary
        let currency: String
        let isWeekly: Bool
        let isCurrentMonth: Bool
        let onEdit: (() -> Void)?
        let onEditBudget: (() -> Void)?
        let onPlanAhead: (() -> Void)?
        let onEditTransaction: (Transaction) -> Void
        @State private var expandedWeek: Int? = nil
        @State private var showMonthlyTransactions = false

        var body: some View {
            let targetValue = category.target ?? 0
            let progressRatio = targetValue > 0 ? category.totalSpent / targetValue : 0
            let accentColor = progressColor(for: progressRatio, hasTarget: targetValue > 0)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        if onEdit != nil || onEditBudget != nil {
                            Menu {
                                if let onEdit = onEdit { Button("ערוך יעד כללי", action: onEdit) }
                                if let onEditBudget = onEditBudget { Button("הגדר תקציב חודשי", action: onEditBudget) }
                            } label: { Image(systemName: "ellipsis.circle").foregroundColor(.secondary) }
                        } else {
                            Image(systemName: "ellipsis.circle").foregroundColor(.clear)
                        }
                        Spacer()
                    }
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 6) {
                                Text(category.name).font(.title3).bold()
                                Image(systemName: categoryIcon(for: category.name)).foregroundColor(.secondary)
                            }
                            if targetValue > 0 {
                                statusBadge(targetValue: targetValue, spent: category.totalSpent)
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("יצא").font(.footnote).foregroundColor(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(formatAmount(category.totalSpent))
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(accentColor)
                                    .monospacedDigit()
                                Text("₪")
                                    .font(.headline)
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if targetValue > 0 {
                            HStack {
                                Text("צפוי היה לצאת").font(.footnote).foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(formatAmount(targetValue))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                    Text("₪").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        ProgressCapsule(progress: targetValue > 0 ? category.totalSpent / targetValue : 0, color: accentColor)
                            .frame(height: 12)
                        if category.isTargetSuggested && targetValue > 0 {
                            Button(action: { onEdit?() }) {
                                HStack(spacing: 4) {
                                    Text("יעד מוצע: \(formatAmount(targetValue)) ₪")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .underline(true, color: .secondary.opacity(0.5))
                                    Image(systemName: "pencil.circle")
                                        .imageScale(.small)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        } else if targetValue > 0 {
                            let difference = targetValue - category.totalSpent
                            HStack {
                                HStack(spacing: 4) {
                                    Image(systemName: difference >= 0 ? "arrow.down.circle" : "exclamationmark.circle.fill")
                                        .foregroundColor(difference >= 0 ? Theme.success : Theme.danger)
                                        .imageScale(.small)
                                    Text(difference >= 0 ? "נשאר להוציא \(formatAmount(difference)) ₪" : "חריגה של \(formatAmount(abs(difference))) ₪")
                                        .font(.caption)
                                        .foregroundColor(difference >= 0 ? Theme.success : Theme.danger)
                                        .monospacedDigit()
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding(16)
                Divider()
                VStack(spacing: 10) {
                    if isWeekly {
                        VStack(spacing: 0) {
                            WeeklyGridHeader()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            HorizontalGridDivider()
                            ForEach(1..<(category.weeksInMonth + 1), id: \.self) { week in
                                let spent = category.weekly[week] ?? 0
                                let expected = category.weeklyExpected
                                let remain = max(expected - spent, 0)
                                let isOpen = expandedWeek == week
                                VStack(spacing: 8) {
                                    Button { withAnimation(.easeInOut(duration: 0.2)) { expandedWeek = isOpen ? nil : week } } label: {
                                        WeekRow(week: week, spent: spent, remain: remain, isOpen: isOpen, currencySymbol: currencySymbol(for: currency))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    if isOpen {
                                        let weekTransactions = transactions(for: week)
                                        if weekTransactions.isEmpty {
                                            Text("אין עסקאות בשבוע זה")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .transition(.opacity)
                                                .padding(.horizontal, 16)
                                                .padding(.bottom, 6)
                                        } else {
                                            VStack(spacing: 8) {
                                                ForEach(weekTransactions, id: \.id) { tx in
                                                    weeklyTransactionRow(tx, highlight: accentColor, currency: currency)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.bottom, 8)
                                            .transition(.opacity)
                                        }
                                    }
                                }
                                if week != category.weeksInMonth { HorizontalGridDivider() }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(weeklyGridBackgroundColor)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(weeklyGridLineColor.opacity(0.8), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        if targetValue > 0 {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(isCurrentMonth ? "צפוי היה לצאת" : "סה\"כ יצא")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                    HStack(spacing: 4) {
                                        Text(formatAmount(isCurrentMonth ? targetValue : category.totalSpent))
                                            .font(isCurrentMonth ? .subheadline : .headline)
                                            .foregroundColor(isCurrentMonth ? .secondary : accentColor)
                                            .monospacedDigit()
                                        Text("₪")
                                            .font(isCurrentMonth ? .caption2 : .subheadline)
                                            .foregroundColor(isCurrentMonth ? .secondary : accentColor)
                                    }
                                }
                                Spacer()
                                if !isCurrentMonth {
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("צפוי היה לצאת")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        HStack(spacing: 4) {
                                            Text(formatAmount(targetValue))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .monospacedDigit()
                                            Text("₪")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }

                        }
                        Divider()
                        DisclosureGroup(isExpanded: $showMonthlyTransactions) {
                            VStack(spacing: 10) {
                                ForEach(category.transactions, id: \.id) { t in
                                    monthlyTransactionRow(t)
                                }
                            }
                            .transition(.opacity)
                        } label: {
                            HStack {
                                Text(showMonthlyTransactions ? "הסתר עסקאות החודש" : "הצג עסקאות החודש")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: showMonthlyTransactions ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .accentColor(.primary)
                    }
                }
                .padding(16)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Theme.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
        }

        private func progressColor(for ratio: Double, hasTarget: Bool) -> Color {
            guard hasTarget else { return Theme.primary }
            if ratio < 0.8 { return Theme.success }
            if ratio <= 1.0 { return Theme.warning }
            return Theme.danger
        }

        private func statusBadge(targetValue: Double, spent: Double) -> AnyView {
            guard targetValue > 0 else { return AnyView(EmptyView()) }
            let ratio = spent / targetValue
            let text: String
            let color: Color
            switch ratio {
            case ..<0.85:
                text = "בתקציב"
                color = Theme.success
            case 0.85...1.0:
                text = "ליד היעד"
                color = Theme.warning
            default:
                text = "חריגה"
                color = Theme.danger
            }
            let badge = Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(color.opacity(0.18))
                )
                .foregroundColor(color)
            return AnyView(badge)
        }

        private func categoryIcon(for name: String) -> String {
            let lower = name.lowercased()
            if lower.contains("רכב") { return "car.fill" }
            if lower.contains("סופר") { return "cart.fill" }
            if lower.contains("פנאי") || lower.contains("בילוי") { return "sparkles" }
            if lower.contains("בתי קפה") { return "cup.and.saucer.fill" }
            if lower.contains("חיסכון") { return "banknote" }
            if lower.contains("מס") || lower.contains("ארנונה") { return "building.2.fill" }
            return "circle.grid.cross"
        }

        private func formatAmount(_ v: Double) -> String {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 1; f.groupingSeparator = ","; return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
        }

        private func dateString(_ d: Date?) -> String {
            guard let d else { return "" }; let f = DateFormatter(); f.locale = Locale(identifier: "he_IL"); f.dateFormat = "d.M.yy"; return f.string(from: d)
        }
        @ViewBuilder
        private func weeklyTransactionRow(_ t: Transaction, highlight: Color, currency: String) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(currencySymbol(for: currency)).font(.caption).foregroundColor(highlight)
                        Text(formatAmount(abs(t.normalizedAmount))).font(.subheadline).foregroundColor(highlight).monospacedDigit()
                    }
                    .frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            onEditTransaction(t)
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundColor(.secondary).frame(width: 30)
                    }
                }
                Text(t.business_name?.isEmpty == false ? t.business_name! : "—").font(.subheadline).foregroundColor(t.business_name?.isEmpty == false ? .primary : .secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let note = t.notes, !note.isEmpty { Text(note).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                Divider().padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        @ViewBuilder
        private func monthlyTransactionRow(_ t: Transaction) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(formatAmount(abs(t.normalizedAmount))).font(.subheadline).foregroundColor(.blue).monospacedDigit()
                        Text("₪").font(.caption).foregroundColor(.blue)
                    }
                    .frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            onEditTransaction(t)
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundColor(.secondary).frame(width: 30)
                    }
                }
                Text(t.business_name?.isEmpty == false ? t.business_name! : "—").font(.subheadline).foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading)
                if let note = t.notes, !note.isEmpty { Text(note).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                Divider().padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        private func transactions(for week: Int) -> [Transaction] {
            // Use the bucketed transactions provided by the ViewModel so flow_month overrides stick to the intended week.
            return category.weeklyTransactions[week] ?? []
        }
    }


    struct WeekRow: View {
        let week: Int
        let spent: Double
        let remain: Double
        let isOpen: Bool
        let currencySymbol: String
        var body: some View {
            HStack(spacing: 12) {
                WeekBadge(week: week, filled: isOpen)
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .trailing)
                VerticalGridDivider()
                WeeklyAmountCell(valueText: format(spent), currencySymbol: currencySymbol, color: .blue)
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .trailing)
                VerticalGridDivider()
                WeeklyAmountCell(valueText: format(remain), currencySymbol: currencySymbol, color: .secondary)
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .trailing)
                VerticalGridDivider()
                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28, alignment: .center)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        private func format(_ v: Double) -> String {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 1; f.groupingSeparator = ","; return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
        }
    }

    struct HorizontalGridDivider: View {
        var body: some View {
            Rectangle()
                .fill(weeklyGridLineColor)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .opacity(0.8)
        }
    }

    struct VerticalGridDivider: View {
        var body: some View {
            Rectangle()
                .fill(weeklyGridLineColor)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .opacity(0.8)
        }
    }

    struct WeeklyGridHeader: View {
        var body: some View {
            HStack(spacing: 12) {
                Text("שבוע")
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .trailing)
                VerticalGridDivider()
                Text("יצא")
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .trailing)
                VerticalGridDivider()
                Text("נשאר להוציא")
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .trailing)
                VerticalGridDivider()
                Image(systemName: "chevron.down").foregroundColor(.clear).frame(width: 28, alignment: .center)
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(.bottom, 4)
        }
    }

    struct WeeklyAmountCell: View {
        let valueText: String
        let currencySymbol: String
        let color: Color

        var body: some View {
            HStack(spacing: 4) {
                Text(currencySymbol).font(.caption2)
                Text(valueText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(color)

        }
    }

    struct WeekBadge: View {
        let week: Int
        let filled: Bool
        var body: some View {
            Text("שבוע \(week)").font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(filled ? Color.blue : Color.blue.opacity(0.12)))
                .foregroundColor(filled ? .white : .blue)
                .frame(width: 78, height: 26, alignment: .center)
                .animation(nil, value: filled)
        }
    }

    struct GroupSectionCard: View {
        @EnvironmentObject private var vm: CashFlowDashboardViewModel
        let group: CashFlowDashboardViewModel.GroupSummary
        let accent: Color
        let currency: String
        let onEditTransaction: (Transaction) -> Void
        var body: some View {
            SectionCard(
                title: group.title,
                accent: accent,
                expectedLabel: "צפוי לצאת",
                expectedValue: group.target,
                actualLabel: "יצא",
                actualValue: group.totalSpent,
                currency: currency,
                isCurrentMonth: vm.isCurrentMonth
            ) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Text("יצא").font(.footnote).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                        Text("צפוי לצאת").font(.footnote).foregroundColor(.secondary).frame(width: 90, alignment: .leading)
                    }
                    .padding(.horizontal, 12).padding(.bottom, 6)
                    ForEach(group.members, id: \.id) { member in
                        CompactCategoryRow(category: member, currency: currency, onEdit: nil, onEditBudget: nil, onEditTransaction: onEditTransaction)
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
    }

    struct CompactCategoryRow: View {
        let category: CashFlowDashboardViewModel.CategorySummary
        let currency: String
        let onEdit: (() -> Void)?
        let onEditBudget: (() -> Void)?
        let onEditTransaction: (Transaction) -> Void
        @State private var open = false
        var body: some View {
            VStack(spacing: 8) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
                        Text(category.name).font(.subheadline)
                        Spacer()
                        HStack(spacing: 4) { Text(formatAmount(category.totalSpent)).foregroundColor(.pink).monospacedDigit(); Text("₪").font(.caption).foregroundColor(.pink) }.frame(width: 90, alignment: .leading)
                        HStack(spacing: 4) { Text(formatAmount(category.target ?? 0)).foregroundColor(.secondary).monospacedDigit(); Text("₪").font(.caption).foregroundColor(.secondary) }.frame(width: 90, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                if open { VStack(spacing: 8) { ForEach(category.transactions, id: \.id) { t in monthlyRow(t) } }.transition(.opacity) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        private func monthlyRow(_ t: Transaction) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(formatAmount(abs(t.normalizedAmount))).font(.subheadline).foregroundColor(.pink).monospacedDigit()
                        Text("₪").font(.caption).foregroundColor(.pink)
                    }
                    .frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            onEditTransaction(t)
                        }
                    } label: {
                        Image(systemName: "ellipsis").foregroundColor(.secondary).frame(width: 30)
                    }
                }
                Text(t.business_name?.isEmpty == false ? t.business_name! : "—").font(.subheadline).foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading)
                if let note = t.notes, !note.isEmpty { Text(note).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                Divider().padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        private func dateString(_ d: Date?) -> String {
            guard let d else { return "" }; let f = DateFormatter(); f.locale = Locale(identifier: "he_IL"); f.dateFormat = "d.M.yy"; return f.string(from: d)
        }
        private func formatAmount(_ v: Double) -> String {
            let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 1; f.groupingSeparator = ","; return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
        }
    }

struct GroupTransactionRow: View {
        let transaction: Transaction
        let accent: Color
        let currency: String
        let onEditTransaction: (Transaction) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(transaction.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    Text(formatAmount(abs(transaction.normalizedAmount))).font(.subheadline).foregroundColor(accent).monospacedDigit().frame(minWidth: 80, alignment: .leading)
                    Spacer()
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                onEditTransaction(transaction)
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundColor(.secondary)
                        }
                }
                Text(transaction.business_name?.isEmpty == false ? transaction.business_name! : "—").font(.subheadline).foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading)
                if let note = transaction.notes, !note.isEmpty { Text(note).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                Divider().padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        private func dateString(_ d: Date?) -> String {
            guard let d else { return "" }; let f = DateFormatter(); f.locale = Locale(identifier: "he_IL"); f.dateFormat = "d.M.yy"; return f.string(from: d)
        }
        private func formatAmount(_ value: Double) -> String {
            let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "he_IL"); formatter.numberStyle = .currency; formatter.currencyCode = currency; formatter.maximumFractionDigits = 1; return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }
    }
}



private struct WeeklyBudgetInfo: Equatable {
    let totalExpected: Double
    let spentThisWeek: Double
    let remaining: Double
    let weeks: [WeeklyBudgetWeek]
}

private struct WeeklyBudgetWeek: Identifiable, Equatable {
    let weekNumber: Int
    let spent: Double
    let expected: Double
    var id: Int { weekNumber }
}

private extension WeeklyBudgetInfo {
    var remainingDescription: String {
        if remaining >= 0 {
            return "נשאר " + formatValue(remaining)
        } else {
            return "חריגה של " + formatValue(abs(remaining))
        }
    }

    private func formatValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
