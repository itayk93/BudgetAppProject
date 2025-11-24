import SwiftUI
import UIKit

struct EditTransactionView: View {
    let transaction: Transaction
    let onSave: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    let onCancel: () -> Void
    @State private var categoryName: String
    @State private var notes: String
    @State private var flowMonth: String
    @State private var showCategorySelector = false
    @State private var noteExpanded = false
    @State private var moveFlowMonthExpanded = false
    @State private var moveFlowMonthText = ""
    @State private var moveFlowMonthError: String?
    @State private var isMovingFlowMonth = false
    @State private var showSplitTransaction = false
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var errorMessage: String?
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
        // Initialize state variables with current transaction values
        self._categoryName = State(initialValue: transaction.category?.name ?? transaction.effectiveCategoryName)
        self._notes = State(initialValue: transaction.notes ?? "")
        self._flowMonth = State(initialValue: transaction.flow_month ?? "")
        self._showCategorySelector = State(initialValue: false)
        self._noteExpanded = State(initialValue: !transaction.notes.isNilOrEmpty)
        self._moveFlowMonthExpanded = State(initialValue: false)
        self._showSplitTransaction = State(initialValue: false)
        self._showDeleteConfirmation = State(initialValue: false)
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(UIColor.systemGray5).ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroSection
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("עריכת עסקה")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSplitTransaction) {
                // Prepare available categories for the split transaction
                let availableCategories = prepareAvailableCategories()
                SplitTransactionSheet(
                    transaction: transaction,
                    availableCategories: availableCategories,
                    onSubmit: { originalTransactionId, splits in
                        // Handle the split transaction submission
                        // In the edit context, we would typically just close the sheet
                        // and let the user know the transaction was split
                        showSplitTransaction = false

                        // In a real implementation, you might want to update the UI
                        // to reflect that the transaction was split
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            // Maybe show a toast or update the transaction state
                            // For now, just closing the split transaction sheet
                        }
                    }
                )
            }
            .alert("מחיקת עסקה", isPresented: $showDeleteConfirmation) {
                Button("ביטול", role: .cancel) { }
                Button("מחק", role: .destructive) {
                    deleteTransaction()
                }
            } message: {
                Text("האם אתה בטוח שברצונך למחוק עסקה זו? פעולה זו בלתי הפיכה.")
            }
        }
        .overlay(alignment: .top) {
            if let errorMessage {
                toastView(message: errorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            AppLogger.log("✏️ Entered EditTransactionView for tx \(transaction.id)", force: true)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 0) {
            // Yellow header section
            VStack(alignment: .leading, spacing: 8) {
                // Close button - visually on top-left regardless of RTL
                HStack {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.25))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Category label
                Text(transaction.effectiveCategoryName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // Main amount
                Text("\(currencySymbol(for: transaction.currency))\(heroAmountText(abs(transaction.normalizedAmount)))")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // Business name/description
                Text((transaction.business_name ?? transaction.payment_method ?? "עסקה"))
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // Date
                Text(formattedPaymentDate(for: transaction))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                Text("חודש תזרים: \(displayedFlowMonth())")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(heroYellowColor)

            // White section with editing fields
            VStack(spacing: 12) {
                notesSection
                flowMonthSection()
                categorySection
                splitTransactionSection
                deleteTransactionSection
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
    }

    private func saveTransaction() {
        isSaving = true
        errorMessage = nil

        // Create a new transaction with the edited values (business name and amount remain unchanged)
        let updatedTransaction = Transaction(
            id: transaction.id,
            effectiveCategoryName: categoryName.isEmpty ? transaction.effectiveCategoryName : categoryName,
            isIncome: transaction.isIncome,
            business_name: transaction.business_name, // Keep original business name
            payment_method: transaction.payment_method,
            createdAtDate: transaction.createdAtDate,
            currency: transaction.currency,
            absoluteAmount: abs(transaction.normalizedAmount), // Keep original amount
            notes: notes.isEmpty ? nil : notes,
            normalizedAmount: transaction.normalizedAmount, // Keep original normalized amount
            excluded_from_flow: transaction.excluded_from_flow,
            category_name: categoryName.isEmpty ? transaction.category_name : categoryName,
            category: transaction.category, // We'll keep the original category object for now
            status: transaction.status,
            user_id: transaction.user_id,
            suppress_from_automation: transaction.suppress_from_automation,
            manual_split_applied: transaction.manual_split_applied,
            reviewed_at: transaction.reviewed_at,
            source_type: transaction.source_type,
            date: transaction.date,
            payment_date: transaction.payment_date,
            flow_month: flowMonth.isEmpty ? nil : flowMonth
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Simulate save delay
            isSaving = false
            onSave(updatedTransaction)
        }
    }

    private func heroAmountText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formattedPaymentDate(for transaction: Transaction) -> String {
        guard let date = transaction.parsedDate else {
            return "תאריך לא זמין"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func currencySymbol(for code: String?) -> String {
        guard let code else { return "₪" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.currencySymbol ?? "₪"
    }

    private var categorySection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            actionCardButton(
                title: showCategorySelector ? "סגור בחירת קטגוריה" : "להזיז את ההוצאה",
                systemIcon: "arrowshape.turn.up.right"
            ) {
                showCategorySelector.toggle()
            }

            if showCategorySelector {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("בחר קטגוריה חדשה")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    TextField("הזן שם קטגוריה", text: $categoryName)
                        .padding(12)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .multilineTextAlignment(.trailing)

                    Button {
                        saveTransaction()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(isSaving ? "שומר..." : "שמור קטגוריה")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            actionCardButton(
                title: noteExpanded ? "סגור הערה" : (notes.isEmpty ? "הוסף הערה" : "ערוך הערה"),
                systemIcon: "square.and.pencil"
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    noteExpanded.toggle()
                }
            }

            if noteExpanded {
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(Color(UIColor.systemGray5).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .multilineTextAlignment(.trailing)
                }
                Button {
                    saveTransaction()
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
                    .padding()
                    .background(Color.accentColor.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(isSaving)
            } else if !notes.isEmpty {
                Text(notes)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var heroYellowColor: Color {
        Color(red: 241/255, green: 193/255, blue: 26/255)
    }

    private func prepareAvailableCategories() -> [String] {
        // Get categories from the view model's orderedItems, if available
        var availableCategories: [String] = []

        // Extract categories from the ViewModel's orderedItems
        for item in vm.orderedItems {
            switch item {
            case .category(let categorySummary):
                availableCategories.append(categorySummary.name)
            case .sharedGroup(let groupSummary):
                // Include members of shared groups as well
                for member in groupSummary.members {
                    availableCategories.append(member.name)
                }
            case .income, .savings, .nonCashflow:
                // Skip these special items
                break
            }
        }

        // Add the current transaction's effective category if it's not already in the list
        let effectiveCategory = transaction.effectiveCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveCategory.isEmpty && !availableCategories.contains(effectiveCategory) {
            availableCategories.append(effectiveCategory)
        }

        // Add the current categoryName if it's not already in the list
        if !categoryName.isEmpty && !availableCategories.contains(categoryName) {
            availableCategories.append(categoryName)
        }

        // If no categories are available, fallback to the effective category
        if availableCategories.isEmpty, !effectiveCategory.isEmpty {
            availableCategories = [effectiveCategory]
        }

        // If still no categories, use a default category
        if availableCategories.isEmpty {
            availableCategories = ["הוצאות משתנות"]
        }

        return availableCategories.sorted()
    }

    private var deleteTransactionSection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Button(action: {
                AppLogger.log("🗑️ Delete button tapped for tx \(transaction.id)", force: true)
                showDeleteConfirmation = true
            }) {
                HStack(spacing: 12) {
                    Text("למחוק את העסקה")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "trash")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(UIColor.systemGray6))
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var splitTransactionSection: some View {
        VStack(alignment: .trailing, spacing: 10) {
            actionCardButton(
                title: "לפצל את ההוצאה",
                systemIcon: "scissors"
            ) {
                showSplitTransaction = true
            }
        }
    }

    private func flowMonthSection() -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            actionCardButton(
                title: moveFlowMonthExpanded ? "בטל העברת תזרים" : "העברת תזרים לחודש אחר",
                systemIcon: "calendar.badge.plus"
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if moveFlowMonthExpanded {
                        moveFlowMonthExpanded = false
                    } else {
                        moveFlowMonthText = flowMonth.isEmpty ? resolvedFlowMonth(for: transaction) : flowMonth
                        moveFlowMonthError = nil
                        moveFlowMonthExpanded = true
                    }
                }
            }

            if moveFlowMonthExpanded {
                VStack(alignment: .trailing, spacing: 10) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("חודש תזרים חדש (yyyy-MM)")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                        TextField("2025-11", text: $moveFlowMonthText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .font(.title3.monospacedDigit())
                            .padding(10)
                            .background(Color(UIColor.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if let error = moveFlowMonthError {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    HStack(spacing: 12) {
                        Button("בטל") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                moveFlowMonthExpanded = false
                                moveFlowMonthError = nil
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(UIColor.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button(action: submitMoveFlowMonth) {
                            HStack {
                                if isMovingFlowMonth {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                                Text(isMovingFlowMonth ? "מעביר..." : "שמור לחודש זה")
                                    .font(.body.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(
                            !isValidFlowMonth(moveFlowMonthText) || isMovingFlowMonth
                        )
                        .opacity(!isValidFlowMonth(moveFlowMonthText) || isMovingFlowMonth ? 0.6 : 1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
                )
            }
        }
    }

    private func actionCardButton(
        title: String,
        systemIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: systemIcon)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(UIColor.systemGray6))
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            )
        }
        .buttonStyle(.plain)
    }

    private func displayedFlowMonth() -> String {
        if moveFlowMonthExpanded && isValidFlowMonth(moveFlowMonthText) {
            return moveFlowMonthText
        }
        return flowMonth.isEmpty ? resolvedFlowMonth(for: transaction) : flowMonth
    }

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

    private func isValidFlowMonth(_ flowMonth: String) -> Bool {
        let components = flowMonth.split(separator: "-")
        if components.count != 2 {
            return false
        }

        guard let year = Int(components[0]), year >= 2000, year <= 2100 else {
            return false
        }

        guard let month = Int(components[1]), month >= 1, month <= 12 else {
            return false
        }

        return true
    }

    private func submitMoveFlowMonth() {
        guard isValidFlowMonth(moveFlowMonthText) else {
            moveFlowMonthError = "הזן חודש תזרים תקין בפורמט yyyy-MM"
            return
        }
        moveFlowMonthError = nil
        isMovingFlowMonth = true

        // Update the flowMonth state variable
        flowMonth = moveFlowMonthText

        // Close the expansion after successful update
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            moveFlowMonthExpanded = false
        }

        saveTransaction()
        isMovingFlowMonth = false
    }

    private func deleteTransaction() {
        AppLogger.log("⚠️ Confirmation accepted; deleting tx \(transaction.id)", force: true)
        // Call the onDelete callback to handle the deletion
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
}

extension String? {
    var isNilOrEmpty: Bool {
        return self?.isEmpty ?? true
    }
}
