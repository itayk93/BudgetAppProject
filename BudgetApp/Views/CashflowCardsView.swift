// BudgetApp/Views/CashflowCardsView.swift

import SwiftUI
import Combine

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
    
    @State private var showingEditTargetSheet = false
    @State private var selectedCategoryForEdit: CashFlowDashboardViewModel.CategorySummary?
    @State private var editingTargetValue: Double?

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
    @State private var transactionToEdit: Transaction?
    @State private var transactionToShowDetails: Transaction?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    header
                    content
                }
                if vm.errorMessage == nil && (!vm.loading || !vm.transactions.isEmpty) {
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
                TransactionSearchSheet(
                    filter: transactionFilter,
                    currencySymbol: currentCurrencySymbol
                ) { selected in
                    transactionToEdit = selected
                }
                    .environmentObject(vm)
            }
            .sheet(isPresented: $showingFilterSheet) {
                TransactionFilterSheet(
                    filter: $transactionFilter,
                    categories: filterableCategories,
                    paymentMethods: paymentMethodOptions
                )
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
            .sheet(isPresented: $showingPendingTransactionsSheet) {
                PendingTransactionsReviewView()
            }
            .sheet(item: $transactionToEdit) { transaction in
                EditTransactionView(
                    transaction: transaction,
                    onSave: { updatedTransaction in
                        transactionToEdit = nil
                        // Update the transaction in the UI by calling the view model
                        // For now, we'll just refresh the data
                        Task {
                            await vm.refreshData()
                            await pendingTxsVm.refresh()
                        }
                    },
                    onDelete: { transactionToDelete in
                        transactionToEdit = nil
                        AppLogger.log(
                            "🗑️ onDelete triggered for tx \(transactionToDelete.id) (status: \(transactionToDelete.status ?? "nil"))",
                            force: true
                        )
                        Task {
                            AppLogger.log("🗑️ Deleting transaction \(transactionToDelete.id)", force: true)
                            await vm.deleteTransaction(transactionToDelete)
                            await pendingTxsVm.refresh()
                        }
                    },
                    onCancel: {
                        transactionToEdit = nil
                    }
                )
            }
            .sheet(item: $transactionToShowDetails) { transaction in
                TransactionDetailsView(transaction: transaction)
            }
        }
            .onAppear {
                Task {
                    // Only load if not already loaded by LoginView
                    if vm.cashFlows.isEmpty || vm.selectedCashFlow == nil {
                        await vm.loadInitial()
                    } else if vm.orderedItems.isEmpty {
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

                Button(action: { showingSearchSheet = true }) {
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
        if let err = vm.errorMessage {
            VStack(spacing: 10) {
                Text("שגיאה").font(.headline)
                Text(err)
                Button("נסה שוב") { Task { await vm.refreshData() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !isDashboardReady {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    MonthlyLoadingOverlay(
                        title: monthName(vm.currentMonthDate),
                        showChartsProgress: vm.isLoadingCharts || vm.monthlyLabels.isEmpty,
                        showCardsProgress: vm.isLoadingCurrentMonth || vm.orderedItems.isEmpty
                    )
                    .padding(.bottom, 48)
                }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    loadStatusPanel
                    mutationStatusView
                    if vm.isLoadingCurrentMonth && vm.orderedItems.isEmpty {
                        placeholderCard(height: 140)
                    } else {
                        WeeklyBudgetCard(
                            info: weeklyBudgetInfo,
                            currencySymbol: currencySymbol(for: vm.selectedCashFlow?.currency ?? "ILS"),
                            format: formatNumber,
                            onAccountStatusTap: { showingAccountStatusSheet = true }
                        )
                    }
                    if vm.isLoadingCurrentMonth && vm.orderedItems.isEmpty {
                        placeholderCard(height: 140)
                    } else {
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
                    if vm.monthlyLabels.isEmpty && vm.isLoadingCharts {
                        placeholderCard(height: 220)
                    } else {
                        MonthlyTrendCard(
                            labels: vm.monthlyLabels,
                            netSeries: vm.netSeries,
                            expenseSeries: vm.expensesSeries,
                            incomeSeries: vm.incomeSeries,
                            currencySymbol: currencySymbol(for: vm.selectedCashFlow?.currency ?? "ILS")
                        )
                        .overlay(alignment: .topLeading) {
                            if vm.isLoadingCharts {
                                ProgressView().padding().tint(.white)
                            }
                        }
                    }
                    summaryCard
                    if vm.orderedItems.isEmpty && vm.isLoadingCurrentMonth {
                        ForEach(0..<3, id: \.self) { _ in
                            placeholderCard(height: 160)
                        }
                    } else {
                        ForEach(vm.orderedItems, id: \.id) { item in
                            itemView(for: item)
                        }
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
            incomeSection

        case .savings:
            savingsSection

        case .nonCashflow:
            nonCashflowSection

        case .sharedGroup(let group):
            GroupSectionCard(
                group: group,
                accent: groupAccentColor(for: group.title),
                currency: vm.selectedCashFlow?.currency ?? "ILS",
                onEditTransaction: { transaction in
                    transactionToEdit = transaction
                },
                onViewTransactionDetails: { transaction in
                    transactionToShowDetails = transaction
                }
            )

        case .category(let cat):
            CategorySummaryCard(
                category: cat,
                currency: vm.selectedCashFlow?.currency ?? "ILS",
                isWeekly: vm.isWeeklyCategory(cat.name),
                onEdit: vm.isCurrentMonth ? {
                    editingTargetValue = cat.target
                    selectedCategoryForEdit = cat
                    showingEditTargetSheet = true
                } : nil,
                onEditBudget: vm.isCurrentMonth ? {
                    editingBudgetValue = cat.target
                    selectedCategoryForBudgetEdit = cat
                    showingEditTargetSheet = true
                } : nil,
                onEditTransaction: { transaction in
                    transactionToEdit = transaction
                },
                onViewTransactionDetails: { transaction in
                    transactionToShowDetails = transaction
                }
            )
        }
    }

    @ViewBuilder
    private var loadStatusPanel: some View {
        if shouldShowStatusPanel {
            VStack(alignment: .trailing, spacing: 8) {
                if vm.isCachingTransactions {
                    statusCapsule(icon: "bolt.horizontal.circle", text: "הנתונים הוצגו מהמטמון")
                }
                if vm.isLoadingCurrentMonth && vm.orderedItems.isEmpty {
                    statusCapsule(icon: "rectangle.stack.person.crop", text: "טוען כרטיסים לחודש הנוכחי...")
                } else if let cardsError = vm.cardsLoadError {
                    partialErrorRow(
                        title: "טעינת הכרטיסים נכשלה",
                        detail: cardsError,
                        actionTitle: "רענון כרטיסים"
                    ) {
                        Task { await vm.refreshCardsOnly() }
                    }
                }
                if vm.isLoadingCharts && vm.monthlyLabels.isEmpty {
                    statusCapsule(icon: "chart.line.uptrend.xyaxis", text: "טוען גרפים (\(vm.timeRange.rawValue))...")
                } else if let chartsError = vm.chartsLoadError {
                    partialErrorRow(
                        title: "טעינת הגרפים נכשלה",
                        detail: chartsError,
                        actionTitle: "רענון גרפים"
                    ) {
                        Task { await vm.refreshChartsOnly() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var shouldShowStatusPanel: Bool {
        vm.isCachingTransactions ||
        (vm.isLoadingCurrentMonth && vm.orderedItems.isEmpty) ||
        vm.cardsLoadError != nil ||
        (vm.isLoadingCharts && vm.monthlyLabels.isEmpty) ||
        vm.chartsLoadError != nil
    }

    private var isDashboardReady: Bool {
        !vm.orderedItems.isEmpty &&
        !vm.monthlyLabels.isEmpty &&
        vm.cardsLoadError == nil &&
        vm.chartsLoadError == nil
    }

    @ViewBuilder
    private var mutationStatusView: some View {
        switch vm.lastMutation {
        case .working(let message):
            mutationRow(
                icon: "arrow.triangle.2.circlepath",
                color: .orange,
                text: message ?? "מעדכן נתונים..."
            )
        case .failed(let message):
            mutationRow(
                icon: "xmark.octagon.fill",
                color: .red,
                text: message.isEmpty ? "הפעולה נכשלה" : message
            )
        case .success(let date):
            mutationRow(
                icon: "checkmark.circle.fill",
                color: .green,
                text: "הנתונים עודכנו \(relativeTimeString(since: date))"
            )
        default:
            EmptyView()
        }
    }

    private func mutationRow(icon: String, color: Color, text: String) -> some View {
        HStack {
            Spacer()
            Label(text, systemImage: icon)
                .font(.footnote)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.15)))
                .foregroundColor(color)
        }
    }

    private func statusCapsule(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.12)))
            .foregroundColor(.white)
    }

    private func partialErrorRow(
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(detail)
                .font(.footnote)
                .foregroundColor(Theme.muted)
                .lineLimit(2)
            Button(actionTitle) { action() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primary)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
    }

    private func placeholderCard(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color.white.opacity(0.05))
            .frame(height: height)
            .overlay(
                ProgressView()
                    .tint(.white)
            )
    }

    private func relativeTimeString(since date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private struct MonthlyLoadingOverlay: View {
        let title: String
        let showChartsProgress: Bool
        let showCardsProgress: Bool
        private let accent = Color(red: 0.23, green: 0.62, blue: 0.94)
        @State private var gradientPhase: CGFloat = 0
        @State private var dotPhase: Int = 0
        private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

        var body: some View {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 18) {
                    Text("טוען את \(title)")
                        .font(.title3.weight(.semibold))
                    Text(statusDescription)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(accent)
                    animatedBar
                        .frame(height: 14)
                        .padding(.horizontal, 24)
                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(accent.opacity(dotPhase == index ? 1 : 0.35))
                                .frame(width: 10, height: 10)
                        }
                    }
                    .onReceive(timer) { _ in
                        dotPhase = (dotPhase + 1) % 3
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.25),
                                    accent.opacity(0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .black.opacity(0.3), radius: 25, x: 0, y: 10)
                )
                .padding(.horizontal, 32)
            }
            .onAppear {
                gradientPhase = 0
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    gradientPhase = 1
                }
            }
        }

        private var animatedBar: some View {
            GeometryReader { geo in
                let width = geo.size.width
                let activeWidth = width * 0.4
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(accent.opacity(0.25))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.2),
                                    accent,
                                    accent.opacity(0.2)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: activeWidth)
                        .offset(x: gradientPhase * max(1, width - activeWidth))
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: gradientPhase)
                }
            }
        }

        private var statusDescription: String {
            switch (showCardsProgress, showChartsProgress) {
            case (true, true):
                return "אנחנו מסדרים גם את הכרטיסים וגם את הגרפים..."
            case (true, false):
                return "מסיימים לסדר את כרטיסי החודש..."
            case (false, true):
                return "מעדכנים את הגרפים של התקופה..."
            default:
                return "מעדכנים את הנתונים..."
            }
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
                Text(formatNumber(abs(totals.net)))
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(totals.net >= 0 ? .green : .red)
                    .monospacedDigit()
                Text("₪").font(.system(size: 20, weight: .medium))
                    .foregroundColor(totals.net >= 0 ? .green : .red)
                Spacer()
            }
            .environment(\.layoutDirection, .leftToRight)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("סה\"כ הכנסות").font(.footnote).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text(formatNumber(totals.income)).foregroundColor(.green).monospacedDigit()
                        Text("₪").font(.caption).foregroundColor(.green)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("סה\"כ הוצאות").font(.footnote).foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text(formatNumber(totals.expenses)).monospacedDigit()
                        Text("₪").font(.caption)
                    }
                    .foregroundColor(.primary)
                    .environment(\.layoutDirection, .leftToRight)
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
            if case .category(let cat) = item, vm.isWeeklyCategory(cat.name) {
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
                            Text(format(abs(info.remaining)))
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(info.remaining >= 0 ? Theme.success : Theme.danger)
                                .monospacedDigit()
                            Text("₪")
                                .font(.title3)
                                .foregroundColor(info.remaining >= 0 ? Theme.success : Theme.danger)
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
                .environment(\.layoutDirection, .leftToRight)
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
                        .environment(\.layoutDirection, .leftToRight)
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
                            .environment(\.layoutDirection, .leftToRight)
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
            .environment(\.layoutDirection, .leftToRight)
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
                        Text(format(value)).font(.headline).foregroundColor(color).monospacedDigit()
                        Text(currencySymbol).font(.caption2).foregroundColor(color)
                    }
                    .environment(\.layoutDirection, .leftToRight)
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
        let onSelect: (Transaction) -> Void
        @State private var searchText: String = ""
        @State private var debouncedSearchText: String = ""
        @State private var debounceWorkItem: DispatchWorkItem?

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    headerBar
                    List {
                        Section(header:
                            Text(sectionHeader)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        ) {
                            if !hasQuery {
                                Text("התחל להקליד כדי לחפש עסקאות")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            } else if results.isEmpty {
                                Text("לא נמצאו עסקאות")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            ForEach(results, id: \.id) { tx in
                                Button {
                                    onSelect(tx)
                                    dismiss()
                                } label: {
                                    TransactionSearchRow(transaction: tx, currencySymbol: currencySymbol)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .environment(\.layoutDirection, .rightToLeft)
                }
                .navigationTitle("חיפוש עסקאות")
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: searchText) { _, newValue in
                    debounceWorkItem?.cancel()
                    let workItem = DispatchWorkItem {
                        debouncedSearchText = newValue
                    }
                    debounceWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
                }
                .onDisappear {
                    debounceWorkItem?.cancel()
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
        }

        private var headerBar: some View {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.bold))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Color(UIColor.systemGray5))
                        .clipShape(Circle())
                }

                Spacer()

                searchField
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemGroupedBackground))
            .environment(\.layoutDirection, .leftToRight)
        }

        private var searchField: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(UIColor.systemGray6))
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("חפש עסקאות...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .multilineTextAlignment(.trailing)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            debouncedSearchText = ""
                            dismissKeyboard()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: 44)
            .environment(\.layoutDirection, .rightToLeft)
        }

        private var hasQuery: Bool {
            !trimmedQuery.isEmpty
        }

        private var trimmedQuery: String {
            debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var sectionHeader: String {
            hasQuery ? "תוצאות (\(results.count))" : "התחל חיפוש"
        }

        private var results: [Transaction] {
            guard hasQuery else { return [] }
            return vm.transactions
                .filter { filter.matches($0, accountName: $0.accountDisplayName) && matchesSearchText($0, query: trimmedQuery) }
                .sorted { ($0.parsedDate ?? .distantPast) > ($1.parsedDate ?? .distantPast) }
        }

        private func matchesSearchText(_ transaction: Transaction, query: String) -> Bool {
            let lower = query.lowercased()
            if transaction.business_name?.lowercased().contains(lower) == true { return true }
            if transaction.effectiveCategoryName.lowercased().contains(lower) { return true }
            if transaction.accountDisplayName.lowercased().contains(lower) { return true }
            if formatNumber(abs(transaction.normalizedAmount)).lowercased().contains(lower) { return true }
            return false
        }

        private func formatNumber(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
        }

            private struct TransactionSearchRow: View {
            let transaction: Transaction
            let currencySymbol: String

            var body: some View {
                HStack(alignment: .center, spacing: 12) {
                    Spacer()
                    detailsView
                    amountView
                }
                .environment(\.layoutDirection, .rightToLeft)
            }

            private var amountView: some View {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatAmount())
                        .font(.headline)
                        .monospacedDigit()
                    Text(currencySymbol)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            private var detailsView: some View {
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
                    HStack(spacing: 8) {
                        if let flowBadge = flowMonthLabel() {
                            Text(flowBadge)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .clipShape(Capsule())
                        }
                        Text(dateString(transaction.parsedDate))
                            .font(.caption2)
                            .foregroundColor(.secondary)
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

        private func flowMonthLabel() -> String? {
            guard let flowMonthKey = transaction.flowMonthKey else { return nil }
            return "תזרים \(flowMonthKey)"
        }
    }

    private func dismissKeyboard() {
#if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
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
    private var incomeSection: some View {
        SectionCard(title: "הכנסות", accent: .green, expectedLabel: "צפוי להיכנס", expectedValue: vm.incomeExpected, actualLabel: "נכנס", actualValue: vm.incomeTotal, currency: vm.selectedCashFlow?.currency ?? "ILS") {
            ForEach(vm.incomeTransactions, id: \.id) { t in
                transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .green)
            }
        }
    }

    private var savingsSection: some View {
        SectionCard(title: "הפקדות לחיסכון", accent: .orange, expectedLabel: "צפוי לצאת", expectedValue: vm.savingsExpected, actualLabel: "יצא", actualValue: vm.savingsTotal, currency: vm.selectedCashFlow?.currency ?? "ILS") {
            ForEach(vm.savingsTransactions, id: \.id) { t in
                transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .orange)
            }
        }
    }

    private var nonCashflowSection: some View {
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
                        .environment(\.layoutDirection, .leftToRight)
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
                            transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .green)
                        }
                    }
                }.accentColor(.primary)
                DisclosureGroup("פירוט הוצאות לא תזרימיות") {
                    VStack(spacing: 8) {
                        ForEach(vm.excludedExpense, id: \.id) { t in
                            transactionRow(t, currency: vm.selectedCashFlow?.currency ?? "ILS", highlight: .pink)
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
        GroupSectionCard(
            group: group,
            accent: accent,
            currency: vm.selectedCashFlow?.currency ?? "ILS",
            onEditTransaction: { transaction in
                transactionToEdit = transaction
            },
            onViewTransactionDetails: { transaction in
                transactionToShowDetails = transaction
            }
        )
    }

    private func transactionRow(_ t: Transaction, currency: String, highlight: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(CashflowCardsView.shortDate(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                HStack(spacing: 4) {
                    Text(formatNumber(abs(t.normalizedAmount))).foregroundColor(highlight).monospacedDigit()
                    Text("₪").font(.caption).foregroundColor(highlight)
                }
                .environment(\.layoutDirection, .leftToRight).font(.headline).frame(minWidth: 80, alignment: .leading)
                Spacer()
                NavigationLink(destination: TransactionDetailsView(transaction: t)) {
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

    static func shortDate(_ d: Date?) -> String {
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
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(expectedLabel).font(.footnote).foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    Text(formatAmount(expectedValue)).font(.headline).foregroundColor(accent).monospacedDigit()
                                    Text("₪").font(.caption).foregroundColor(accent)
                                }
                                .environment(\.layoutDirection, .leftToRight)
                            }
                            Spacer()
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
        let onEdit: (() -> Void)?
        let onEditBudget: (() -> Void)?
        let onEditTransaction: (Transaction) -> Void
        let onViewTransactionDetails: (Transaction) -> Void
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
                    HStack(spacing: 8) {

                        // קודם אייקון
                        if let iconName = categoryIcon(for: category.name) as String? {
                            Image(systemName: iconName)
                                .foregroundColor(.secondary)
                        }

                        // אחר כך שם הקטגוריה
                        Text(category.name)
                            .font(.title3)
                            .bold()

                        // בסוף תגית המצב – "חריגה" / "יעד" וכו'
                        if targetValue > 0 {
                            statusBadge(targetValue: targetValue, spent: category.totalSpent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("יצא").font(.footnote).foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    Text(formatAmount(category.totalSpent)).font(.headline).foregroundColor(accentColor).monospacedDigit()
                                    Text("₪").font(.caption).foregroundColor(accentColor)
                                }
                                .environment(\.layoutDirection, .leftToRight)
                            }
                            Spacer()
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
                                                    weeklyTransactionRow(tx, highlight: accentColor, currency: currency, onEditTransaction: onEditTransaction, onViewDetails: onViewTransactionDetails)
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
                                Text("צפוי היה לצאת")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                Spacer()
                                HStack(spacing: 4) {
                                    Text(formatAmount(targetValue))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                    Text("₪").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .environment(\.layoutDirection, .leftToRight)
                        }
                        Divider()
                        DisclosureGroup(isExpanded: $showMonthlyTransactions) {
                            VStack(spacing: 10) {
                                ForEach(category.transactions, id: \.id) { t in
                                    monthlyTransactionRow(t, onEditTransaction: onEditTransaction, onViewDetails: onViewTransactionDetails)
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
        private func weeklyTransactionRow(_ t: Transaction, highlight: Color, currency: String, onEditTransaction: @escaping (Transaction) -> Void, onViewDetails: @escaping (Transaction) -> Void) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(currencySymbol(for: currency)).font(.caption).foregroundColor(highlight)
                        Text(formatAmount(abs(t.normalizedAmount))).font(.subheadline).foregroundColor(highlight).monospacedDigit()
                    }
                    .environment(\.layoutDirection, .leftToRight).frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    TransactionMenuView(
                        transaction: t,
                        onEdit: { transaction in
                            onEditTransaction(transaction)
                        },
                        onDelete: { transaction in
                            // Handle delete action
                        },
                        onApprove: { transaction in
                            // Handle approve action for pending transactions
                        },
                        onViewDetails: onViewDetails
                    )
                }
                Text(t.business_name?.isEmpty == false ? t.business_name! : "—").font(.subheadline).foregroundColor(t.business_name?.isEmpty == false ? .primary : .secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let note = t.notes, !note.isEmpty { Text(note).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                Divider().padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        @ViewBuilder
        private func monthlyTransactionRow(_ t: Transaction, onEditTransaction: @escaping (Transaction) -> Void = { _ in }, onViewDetails: @escaping (Transaction) -> Void = { _ in }) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(formatAmount(abs(t.normalizedAmount))).font(.subheadline).foregroundColor(.blue).monospacedDigit()
                        Text("₪").font(.caption).foregroundColor(.blue)
                    }
                    .environment(\.layoutDirection, .leftToRight).frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    TransactionMenuView(
                        transaction: t,
                        onEdit: { transaction in
                            onEditTransaction(transaction)
                        },
                        onDelete: { transaction in
                            // Handle delete action
                        },
                        onApprove: { transaction in
                            // Handle approve action for pending transactions
                        },
                        onViewDetails: onViewDetails
                    )
                }
                Text(t.business_name?.isEmpty == false ? t.business_name! : "—").font(.subheadline).foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading)
                if let note = t.notes, !note.isEmpty { Text(note).font(.footnote).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                Divider().padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
        private func transactions(for week: Int) -> [Transaction] {
            let cal = Calendar(identifier: .gregorian)
            return category.transactions.filter { tx in
                guard let date = tx.parsedDate else { return false }
                return cal.component(.weekOfMonth, from: date) == week
            }
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
            .environment(\.layoutDirection, .leftToRight)
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
        let onViewTransactionDetails: (Transaction) -> Void
        var body: some View {
            SectionCard(title: group.title, accent: accent, expectedLabel: "צפוי לצאת", expectedValue: group.target, actualLabel: "יצא", actualValue: group.totalSpent, currency: currency) {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Text("יצא").font(.footnote).foregroundColor(.secondary).frame(width: 90, alignment: .leading).environment(\.layoutDirection, .leftToRight)
                        Text("צפוי לצאת").font(.footnote).foregroundColor(.secondary).frame(width: 90, alignment: .leading).environment(\.layoutDirection, .leftToRight)
                    }
                    .padding(.horizontal, 12).padding(.bottom, 6)
                    ForEach(group.members, id: \.id) { member in
                        CompactCategoryRow(category: member, currency: currency, onEdit: nil, onEditBudget: nil, onEditTransaction: onEditTransaction, onViewTransactionDetails: onViewTransactionDetails)
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
        let onViewTransactionDetails: (Transaction) -> Void
        @State private var open = false
        var body: some View {
            VStack(spacing: 8) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "chevron.up" : "chevron.down").foregroundColor(.secondary)
                        Text(category.name).font(.subheadline)
                        Spacer()
                        HStack(spacing: 4) { Text(formatAmount(category.totalSpent)).foregroundColor(.pink).monospacedDigit(); Text("₪").font(.caption).foregroundColor(.pink) }.environment(\.layoutDirection, .leftToRight).frame(width: 90, alignment: .leading)
                        HStack(spacing: 4) { Text(formatAmount(category.target ?? 0)).foregroundColor(.secondary).monospacedDigit(); Text("₪").font(.caption).foregroundColor(.secondary) }.environment(\.layoutDirection, .leftToRight).frame(width: 90, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)
                if open { VStack(spacing: 8) { ForEach(category.transactions, id: \.id) { t in monthlyRow(t, onEditTransaction: onEditTransaction, onViewDetails: onViewTransactionDetails) } }.transition(.opacity) }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        private func monthlyRow(_ t: Transaction, onEditTransaction: @escaping (Transaction) -> Void = { _ in }, onViewDetails: @escaping (Transaction) -> Void = { _ in }) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(t.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(formatAmount(abs(t.normalizedAmount))).font(.subheadline).foregroundColor(.pink).monospacedDigit()
                        Text("₪").font(.caption).foregroundColor(.pink)
                    }
                    .environment(\.layoutDirection, .leftToRight).frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    TransactionMenuView(
                        transaction: t,
                        onEdit: { transaction in
                            onEditTransaction(transaction)
                        },
                        onDelete: { transaction in
                            // Handle delete action
                        },
                        onApprove: { transaction in
                            // Handle approve action for pending transactions
                        },
                        onViewDetails: onViewDetails
                    )
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
        let onViewTransactionDetails: (Transaction) -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dateString(transaction.parsedDate)).font(.footnote).foregroundColor(.secondary).frame(minWidth: 60, alignment: .leading)
                    Text(formatAmount(abs(transaction.normalizedAmount))).font(.subheadline).foregroundColor(accent).monospacedDigit().frame(minWidth: 80, alignment: .leading)
                    Spacer()
                    TransactionMenuView(
                        transaction: transaction,
                        onEdit: { transaction in
                            onEditTransaction(transaction)
                        },
                        onDelete: { transaction in
                            // Handle delete action
                        },
                        onApprove: { transaction in
                            // Handle approve action for pending transactions
                        },
                        onViewDetails: onViewTransactionDetails
                    )
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
