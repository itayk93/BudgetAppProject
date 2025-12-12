import SwiftUI
import UIKit

struct EditTransactionView: View {
    @Environment(\.dismiss) private var dismiss

    struct ContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value += nextValue()
        }
    }

    let transaction: Transaction
    let onSave: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    let onCancel: () -> Void

    @State private var categoryName: String
    @State private var notes: String
    @State private var flowMonth: String
    @State private var noteExpanded = false
    @State private var showCategorySelector = false
    @State private var categorySearchText = ""
    @State private var selectedCategory: String?
    @State private var showSplitTransaction = false
    @State private var moveFlowMonthExpanded = false
    @State private var moveFlowMonthDate = Date()
    @State private var isMovingFlowMonth = false
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var hasPendingChanges = false
    @State private var didDelete = false
    @State private var errorMessage: String?
    @State private var sheetDragOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 600

    @EnvironmentObject private var vm: CashFlowDashboardViewModel

    init(
        transaction: Transaction,
        onSave: @escaping (Transaction) -> Void,
        onDelete: @escaping (Transaction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.transaction = transaction
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        self._categoryName = State(initialValue: transaction.category?.name ?? transaction.effectiveCategoryName)
        self._notes = State(initialValue: transaction.notes ?? "")
        self._flowMonth = State(initialValue: transaction.flow_month ?? "")
        self._showCategorySelector = State(initialValue: false)
        self._categorySearchText = State(initialValue: "")
        self._selectedCategory = State(initialValue: nil)
        self._noteExpanded = State(initialValue: !transaction.notes.isNilOrEmpty)
        self._moveFlowMonthExpanded = State(initialValue: false)
        self._moveFlowMonthDate = State(initialValue: Date())
        self._showSplitTransaction = State(initialValue: false)
        self._showDeleteConfirmation = State(initialValue: false)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }

                bottomSheet
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .frame(maxHeight: min(proxy.size.height * 0.9, contentHeight), alignment: .bottom)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
            }
            .edgesIgnoringSafeArea(.bottom)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSplitTransaction) {
            let availableCategories = prepareAvailableCategories()
            SplitTransactionSheet(
                transaction: transaction,
                availableCategories: availableCategories,
                onSubmit: { _, _ in
                    showSplitTransaction = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Placeholder for potential post-split UI feedback
                    }
                }
            )
        }
        .overlay(alignment: .top) {
            if let errorMessage {
                toastView(message: errorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }
        }
        .onAppear {
            AppLogger.log(
                "✏️ Entered EditTransactionView for tx \(transaction.id) (status: \(transaction.status ?? "nil"))",
                force: true
            )
        }
        .onChange(of: vm.errorMessage) { _, newValue in
            if let newValue {
                AppLogger.log("⚠️ VM error message: \(newValue)", force: true)
            }
        }
        .onDisappear {
            if hasPendingChanges && !didDelete {
                saveTransaction()
            }
        }
    }

    // MARK: - Layout

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            heroSection
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )

            ScrollView(showsIndicators: false) {
                actionsSection
                    .padding(.bottom, 60)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                        }
                    )
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onPreferenceChange(ContentHeightKey.self) { newHeight in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                contentHeight = newHeight
            }
        }
        .background(Color.white.opacity(0.98))
        .clipShape(TopRoundedSheetShape(radius: 32))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 0)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .offset(y: sheetDragOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sheetDragOffset)
        .simultaneousGesture(sheetDismissGesture)
    }

    private var sheetDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = value.translation.height
                guard translation > 0 else {
                    sheetDragOffset = 0
                    return
                }
                sheetDragOffset = translation
            }
            .onEnded { value in
                let translation = value.translation.height
                let shouldDismiss = translation > 140 || value.predictedEndLocation.y - value.location.y > 160
                if shouldDismiss {
                    withAnimation {
                        sheetDragOffset = 0
                    }
                    dismiss()
                } else {
                    withAnimation {
                        sheetDragOffset = 0
                    }
                }
            }
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.2))
                .frame(width: 48, height: 5)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(displayCategoryName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Text("\(currencySymbol(for: transaction.currency)) \(heroAmountText(abs(transaction.normalizedAmount)))")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                VStack(alignment: .leading, spacing: 4) {
                    if let businessLine = heroBusinessLine() {
                        Text(businessLine)
                    }
                    if let cardLine = heroCardLine() {
                        Text(cardLine)
                    }
                    if let flowLine = heroFlowMonthLine() {
                        Text(flowLine)
                    }
                    if let dateLine = heroDateLine() {
                        Text(dateLine)
                    }
                }
                .font(.footnote)
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(heroYellowColor)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            notesSection
            categorySection
            splitTransactionSection
            flowMonthSection()
            deleteTransactionSection
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 60)
    }

    // MARK: - Save / Update

    private func saveTransaction() {
        guard !isSaving else { return }
        guard hasPendingChanges else { return }

        let trimmedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCategory.isEmpty else {
            errorMessage = "הזן שם קטגוריה"
            return
        }

        isSaving = true
        hasPendingChanges = false
        errorMessage = nil

        let trimmedNotes = notes.isEmpty ? nil : notes
        let trimmedFlowMonth = flowMonth.trimmingCharacters(in: .whitespacesAndNewlines)
        let flowMonthPayload = trimmedFlowMonth.isEmpty ? nil : trimmedFlowMonth

        Task { @MainActor in
            do {
                let updatedTransaction = try await vm.updateTransaction(
                    transaction,
                    categoryName: trimmedCategory,
                    notes: trimmedNotes,
                    flowMonth: flowMonthPayload
                )
                categoryName = trimmedCategory
                flowMonth = trimmedFlowMonth
                isSaving = false
                onSave(updatedTransaction)
            } catch {
                isSaving = false
                hasPendingChanges = true
                errorMessage = error.localizedDescription
            }
        }
    }

    private func selectCategory(_ category: String) {
        selectedCategory = category
        categoryName = category
        dismissKeyboard()
        hasPendingChanges = true
    }

    private func applyCategoryChange(_ category: String? = nil) {
        let trimmedSearch = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = category ?? selectedCategory
        let newCategory = chosen ?? (!trimmedSearch.isEmpty ? trimmedSearch : categoryName)
        categoryName = newCategory
        selectedCategory = newCategory

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showCategorySelector = false
        }

        dismissKeyboard()
        hasPendingChanges = true
    }

    // MARK: - Hero helpers

    private var displayCategoryName: String {
        let selected = selectedCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !selected.isEmpty { return selected }
        let typed = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return transaction.effectiveCategoryName
    }

    private func heroAmountText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func currencySymbol(for code: String?) -> String {
        guard let code else { return "₪" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? "₪"
    }

    private var heroYellowColor: Color {
        Color(red: 241/255, green: 193/255, blue: 26/255)
    }

    private func heroBusinessLine() -> String? {
        let business = transaction.business_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let method = transaction.payment_method?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let business, !business.isEmpty {
            return business
        }
        if let method, !method.isEmpty {
            return method
        }
        return nil
    }

    private func heroCardLine() -> String? {
        let method = transaction.payment_method?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let method, !method.isEmpty else { return nil }
        return "כרטיס \(method)"
    }

    private func heroDateLine() -> String? {
        guard let date = transaction.parsedDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "d.M.yy"
        return formatter.string(from: date)
    }

    private func heroFlowMonthLine() -> String? {
        // לוקח את flowMonth מה־state אם קיים, אחרת מהעסקה/תאריך
        let raw: String = {
            if !flowMonth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return flowMonth
            }
            if let txFlow = transaction.flow_month, !txFlow.isEmpty {
                return txFlow
            }
            return resolvedFlowMonth(for: transaction)
        }()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let inFormatter = DateFormatter()
        inFormatter.dateFormat = "yyyy-MM"
        inFormatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = inFormatter.date(from: trimmed) {
            let outFormatter = DateFormatter()
            outFormatter.locale = Locale(identifier: "he_IL")
            outFormatter.dateFormat = "M.yy"
            let formatted = outFormatter.string(from: date)
            return "חודש תזרים \(formatted)"
        } else {
            return "חודש תזרים \(trimmed)"
        }
    }

    // MARK: - Sections

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showCategorySelector.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.title3)
                    Text("להזיז את ההוצאה")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard()

            if showCategorySelector {
                VStack(alignment: .leading, spacing: 10) {
                    Text("בחר קטגוריה חדשה")
                        .font(.subheadline.weight(.semibold))

                    TextField("חפש קטגוריה…", text: $categorySearchText)
                        .padding(10)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .multilineTextAlignment(.trailing)

                    if !categorySearchText.isEmpty {
                        ForEach(filteredCategories, id: \.self) { category in
                            Button {
                                selectCategory(category)
                            } label: {
                                HStack {
                                    Image(systemName: "chevron.left")
                                        .font(.footnote)
                                    Text(category)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(
                                        selectedCategory == category ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.25),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 3)
                        }
                    }

                    Button {
                        applyCategoryChange()
                    } label: {
                        Text("שמור קטגוריה")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .actionCard()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    noteExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Text("להוסיף הערה")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard()

            if noteExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120, alignment: .top)
                        .padding(12)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .multilineTextAlignment(.leading)
                        .onChange(of: notes) { _, _ in
                            hasPendingChanges = true
                        }

                    Button {
                        hasPendingChanges = true
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            noteExpanded = false
                        }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(isSaving ? "שומר..." : "שמור הערה")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isSaving)
                    .buttonStyle(.plain)
                    .actionCard()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var splitTransactionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showSplitTransaction = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scissors")
                        .font(.title3)
                    Text("לפצל את ההוצאה")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard()
        }
    }

    private func flowMonthSection() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if moveFlowMonthExpanded {
                        moveFlowMonthExpanded = false
                    } else {
                        let initial = flowMonth.isEmpty ? resolvedFlowMonth(for: transaction) : flowMonth
                        moveFlowMonthDate = flowMonthStringToDate(initial)
                        moveFlowMonthExpanded = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                    Text("העברת תזרים לחודש אחר")
                        .font(.body.weight(.semibold))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard()

            if moveFlowMonthExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text("חודש תזרים")
                        .font(.subheadline)

                    DatePicker(
                        "",
                        selection: $moveFlowMonthDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "he_IL"))
                    .onChange(of: moveFlowMonthDate) { _, _ in
                        hasPendingChanges = true
                    }

                    Text(formattedFlowMonth(from: moveFlowMonthDate))
                        .font(.subheadline.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 12) {
                        Button("בטל") {
                            withAnimation {
                                moveFlowMonthExpanded = false
                            }
                        }

                        Spacer()

                        Button("שמור לחודש זה") {
                            applyFlowMonthChange()
                        }
                        .font(.body.weight(.semibold))
                        .disabled(isMovingFlowMonth || isSaving)
                }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var deleteTransactionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                AppLogger.log("🗑️ Delete button tapped for tx \(transaction.id)", force: true)
                showDeleteConfirmation = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(.red.opacity(0.7))
                    Text("למחוק את העסקה")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.red.opacity(0.85))
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard(destructive: true)
        }
        .alert(isPresented: $showDeleteConfirmation) {
            Alert(
                title: Text("מחיקת העסקה"),
                message: Text("האם אתה בטוח שברצונך למחוק את העסקה?"),
                primaryButton: .destructive(Text("מחק")) {
                    deleteTransaction()
                },
                secondaryButton: .cancel(Text("בטל"))
            )
        }
    }

    // MARK: - Flow month helpers

    private func resolvedFlowMonth(for transaction: Transaction) -> String {
        if let raw = transaction.flow_month, !raw.isEmpty {
            return raw
        }
        if let date = transaction.parsedDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func flowMonthStringToDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: value) ?? Date()
    }

    private func formattedFlowMonth(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private func applyFlowMonthChange() {
        isMovingFlowMonth = true

        let newValue = formattedFlowMonth(from: moveFlowMonthDate)
        flowMonth = newValue
        hasPendingChanges = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            moveFlowMonthExpanded = false
        }

        isMovingFlowMonth = false
    }

    // MARK: - Categories

    private func prepareAvailableCategories() -> [String] {
        var availableCategories: Set<String> = []
        let whitespaceSet = CharacterSet.whitespacesAndNewlines

        // Include categories from all loaded transactions (covers excluded/non-cashflow too).
        for tx in vm.transactions {
            let candidates = [
                tx.effectiveCategoryName,
                tx.category_name,
                tx.category?.name
            ]
            for name in candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty {
                availableCategories.insert(name)
            }
        }

        // Include all categories defined in category_order (even if no transactions yet).
        for name in vm.allCategoryOrderNames {
            let trimmed = name.trimmingCharacters(in: whitespaceSet)
            if !trimmed.isEmpty {
                availableCategories.insert(trimmed)
            }
        }

        for item in vm.orderedItems {
            switch item {
            case .category(let categorySummary):
                availableCategories.insert(categorySummary.name)
            case .sharedGroup(let groupSummary):
                for member in groupSummary.members {
                    availableCategories.insert(member.name)
                }
            case .income, .savings, .nonCashflow:
                break
            }
        }

        let effectiveCategory = transaction.effectiveCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveCategory.isEmpty {
            availableCategories.insert(effectiveCategory)
        }

        if !categoryName.isEmpty {
            availableCategories.insert(categoryName)
        }

        if availableCategories.isEmpty, !effectiveCategory.isEmpty {
            availableCategories = [effectiveCategory]
        }

        if availableCategories.isEmpty {
            availableCategories = ["הוצאות משתנות"]
        }

        return Array(availableCategories).sorted()
    }

    private var filteredCategories: [String] {
        let available = prepareAvailableCategories()
        let search = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return available }
        return available
            .filter { $0.localizedCaseInsensitiveContains(search) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Delete & Toast

    private func deleteTransaction() {
        AppLogger.log("⚠️ Confirmation accepted; deleting tx \(transaction.id)", force: true)
        didDelete = true
        hasPendingChanges = false
        onDelete(transaction)
    }

    private func toastView(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.white)
            Text(message)
                .font(.footnote)
                .foregroundColor(.white)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.8))
        .clipShape(Capsule())
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

}

// MARK: - Shared styles

private struct ActionCard: ViewModifier {
    let isDestructive: Bool

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isDestructive ? Color.red.opacity(0.25) : Color.gray.opacity(0.18),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
            )
    }
}

private extension View {
    func actionCard(destructive: Bool = false) -> some View {
        modifier(ActionCard(isDestructive: destructive))
    }
}

struct TopRoundedSheetShape: Shape {
    var radius: CGFloat = 32

    func path(in rect: CGRect) -> Path {
        let bezier = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(bezier.cgPath)
    }
}

extension String? {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}
