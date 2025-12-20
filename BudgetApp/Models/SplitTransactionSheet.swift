import SwiftUI

struct SplitTransactionSheet: View {
    let transaction: Transaction
    let availableCategories: [String]
    // Closure now passes the transaction id with typed split entries (synchronous)
    var onSubmit: (_ originalTransactionId: String, _ splits: [SplitTransactionEntry]) -> Void
    var onSuccess: (() -> Void)?

    private let categoryService: TransactionsService

    @State private var entries: [SplitEntryDraft] = []
    @State private var categories: [String]
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var isLoadingCategories = false
    @State private var didLoadCategories = false
    @Environment(\.dismiss) private var dismiss

    init(
        transaction: Transaction,
        availableCategories: [String],
        onSubmit: @escaping (_ originalTransactionId: String, _ splits: [SplitTransactionEntry]) -> Void,
        onSuccess: (() -> Void)? = nil,
        transactionsService: TransactionsService = TransactionsService(baseURL: AppConfig.baseURL)
    ) {
        self.transaction = transaction
        self.availableCategories = availableCategories
        self.onSubmit = onSubmit
        self.onSuccess = onSuccess
        self.categoryService = transactionsService
        _categories = State(initialValue: availableCategories)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection
                    splitsList
                    addSplitButton
                    totalsSummary
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                    checkValidationButton
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .navigationTitle("פיצול עסקה")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // Hide default back button to avoid constraint conflicts
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("ביטול") {
                    dismiss()
                }
                .disabled(isSubmitting)
                .accessibilityLabel("סגור")
            }
        }
        .task {
            await loadCategoriesIfNeeded()
        }
        .onAppear {
            if entries.isEmpty {
                entries = [makeDefaultEntry(isOriginal: true)]
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(transaction.business_name ?? "ללא שם")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("סכום מקורי")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if let dateText = formattedPaymentDate {
                        Text("תשלום: \(dateText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Text("\(formatted(amount: originalAmount))₪")
                    .font(.title2.bold())
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
    }

    private var splitsList: some View {
        VStack(spacing: 16) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, _ in
                splitCard(for: binding(for: index), index: index)
            }
        }
    }

    private func splitCard(for entry: Binding<SplitEntryDraft>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(index == 0 ? "רשומה מקורית" : "פיצול \(index)")
                    .font(.headline)
                if index != 0 {
                    Button(role: .destructive) {
                        removeEntry(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Text("(₪) סכום")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("0.0", text: entry.amountBinding { newValue in
                    handleAmountChange(newValue, index: index)
                })
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .environment(\.layoutDirection, .leftToRight)
                .padding(12)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("שם העסק / תיאור")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("לדוגמה: קניות סופר", text: entry.businessName)
                    .textInputAutocapitalization(.sentences)
                    .multilineTextAlignment(.leading)
                .padding(12)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("קטגוריה")
                    .font(.caption)
                    .foregroundColor(.secondary)
                CategoryPickerField(
                    selectedCategory: Binding(
                        get: { entry.wrappedValue.category },
                        set: { entry.wrappedValue.category = $0 }
                    ),
                    availableCategories: categories,
                    isLoading: isLoadingCategories
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("חודש תזרים")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                FlowMonthSelector(flowMonth: entry.flowMonth)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("הסבר (אופציונלי)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("פרט מה שייך לחלק הזה בפיצול", text: entry.notes, axis: .vertical)
                    .lineLimit(1...3)
                    .multilineTextAlignment(.leading)
                .padding(12)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(index == 0 ? Color.secondary.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private var addSplitButton: some View {
        Button {
            addEntry()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text(entries.count == 1 ? "התחל פיצול" : "הוסף פיצול נוסף")
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.accentColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var totalsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("סך פיצולים")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(formatted(amount: currentSplitTotal))₪")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text("סכום מקורי")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(formatted(amount: originalAmount))₪")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let difference = abs(currentSplitTotal - originalAmount)
            HStack(spacing: 8) {
                Text("הפרש")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(difference <= tolerance ? "בתוך הטולרנס" : "\(formatted(amount: difference))₪")")
                    .font(.body.weight(.semibold))
                    .foregroundColor(difference <= tolerance ? .green : .orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(UIColor.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var checkValidationButton: some View {
        Button {
            errorMessage = validateEntries()
        } label: {
            Text("בדוק מה חסר")
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.blue.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            if isSubmitting {
                ProgressView("שולח בקשת פיצול...")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(spacing: 12) {
                Button {
                    // Add debug logging before submitting
                    print("🔍 [SPLIT DEBUG] Submit button pressed - about to call submitSplit()")
                    submitSplit()
                } label: {
                    Text(isSubmitting ? "מפצל..." : "פצל עסקה")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(isSubmitting)

                Button("סגור") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func loadCategoriesIfNeeded() async {
        guard !didLoadCategories else { return }
        didLoadCategories = true
        isLoadingCategories = true
        do {
            let remote = try await categoryService.getUniqueCategories()
            await MainActor.run {
                categories = remote.isEmpty ? availableCategories : remote.sorted()
                isLoadingCategories = false
            }
        } catch {
            await MainActor.run {
                categories = availableCategories
                isLoadingCategories = false
            }
        }
    }

    private func addEntry() {
        let remaining = max(originalAmount - currentSplitTotal, 0)
        var newEntry = makeDefaultEntry(isOriginal: false)
        if remaining > 0 {
            newEntry.amountText = formatted(amount: remaining)
        }
        entries.append(newEntry)
        if entries.count == 2 {
            let firstAmount = max(originalAmount - remaining, 0)
            entries[0].amountText = firstAmount > 0 ? formatted(amount: firstAmount) : ""
        }
    }

    private func removeEntry(at index: Int) {
        guard index != 0 else { return }
        entries.remove(at: index)
    }

    private func makeDefaultEntry(isOriginal: Bool) -> SplitEntryDraft {
        let month = initialFlowMonthString()
        let baseAmount = isOriginal ? formatted(amount: originalAmount) : ""
        let notes = isOriginal ? (transaction.notes ?? "") : ""
        // Use the original transaction's effective category for all splits initially
        let initialCategory = transaction.effectiveCategoryName
        return SplitEntryDraft(
            amountText: baseAmount,
            category: initialCategory,
            businessName: transaction.business_name ?? "",
            flowMonth: month,
            notes: notes,
            isOriginal: isOriginal
        )
    }

    private func handleAmountChange(_ newValue: String, index: Int) {
        let sanitized = newValue.replacingOccurrences(of: ",", with: ".")
        entries[index].amountText = sanitized
        guard entries.count == 2, index == 1 else { return }
        let second = Double(sanitized) ?? 0
        let adjusted = max(originalAmount - second, 0)
        entries[0].amountText = adjusted <= 0 ? "" : formatted(amount: adjusted)
    }

    private func binding(for index: Int) -> Binding<SplitEntryDraft> {
        Binding(
            get: { entries[index] },
            set: { entries[index] = $0 }
        )
    }

    private func submitSplit() {
        guard runPreflightValidation() else { return }
        guard let splits = buildSplitEntries(), !splits.isEmpty else {
            errorMessage = "שגיאה בבניית נתוני הפיצול"
            return
        }

        let originalTransactionId = String(transaction.id) // Ensure safe copy
        let safeSplits = Array(splits) // Ensure safe copy of splits array

        logSplitSummary(id: originalTransactionId, splits: safeSplits)
        performSplitSubmission(id: originalTransactionId, splits: safeSplits)
    }

    private func runPreflightValidation() -> Bool {
        if let validationError = validateEntries() {
            errorMessage = validationError
            return false
        }
        return true
    }

    private func logSplitSummary(id: String, splits: [SplitTransactionEntry]) {
        print("🔍 [SPLIT DEBUG] ======================================")
        print("🔍 [SPLIT DEBUG] READY TO SUBMIT SPLIT")
        print("🔍 [SPLIT DEBUG] original_transaction_id:", id)
        print("🔍 [SPLIT DEBUG] splits count:", splits.count)
        for (index, entry) in splits.enumerated() {
            print("    ↳ Split #", index, "amount=", entry.amount, "category=", entry.category, "flow_month=", entry.flowMonth)
        }
        print("🔍 [SPLIT DEBUG] ======================================")
    }

    private func performSplitSubmission(id: String, splits: [SplitTransactionEntry]) {
        errorMessage = nil
        isSubmitting = true

        // Create safe copies to prevent EXC_BAD_ACCESS due to memory issues
        let safeId = String(id)
        let safeSplits = Array(splits)

        Task {
            do {
                print("🔍 [SPLIT DEBUG] Calling TransactionsService.splitTransaction")
                try await categoryService.splitTransaction(
                    originalTransactionId: safeId,
                    splits: safeSplits
                )
                await MainActor.run {
                    print("🔍 [SPLIT DEBUG] Calling onSubmit closure...")
                    onSubmit(safeId, safeSplits)
                    print("✅ [SPLIT DEBUG] onSubmit closure completed successfully")
                    isSubmitting = false
                    onSuccess?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func validateEntries() -> String? {
        if entries.count < 2 {
            return "חייבים לפחות שני פיצולים כדי לפצל עסקה."
        }

        for (index, entry) in entries.enumerated() {
            let contextLabel = index == 0 ? "הרשומה המקורית" : "פיצול \(index)"
            let amount = Double(entry.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
            if amount <= 0 {
                return "הזן סכום חיובי עבור \(contextLabel)"
            }
            if entry.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "הזן שם עסק עבור \(contextLabel)"
            }
            if entry.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "בחר קטגוריה עבור \(contextLabel)"
            }
            if !FlowMonthInputValidator.isValidFlowMonth(entry.flowMonth) {
                return "קבע חודש תזרים בפורמט yyyy-MM עבור \(contextLabel)"
            }
        }

        let difference = abs(currentSplitTotal - originalAmount)
        if difference > tolerance {
            return "סך הפיצולים חייב להיות שווה לסכום המקורי. נותר פער של ₪\(formatted(amount: difference))."
        }
        return nil
    }

    private func buildSplitEntries() -> [SplitTransactionEntry]? {
        let paymentDate = resolvedPaymentDate()
        // Extract proper currency code, not symbol
        let rawCurrency = transaction.currency ?? "ILS"
        // If the currency looks like a symbol instead of currency code, use proper code
        let currency: String
        switch rawCurrency {
        case "₪":
            currency = "ILS"
        case "$", "US$":
            currency = "USD"
        case "€":
            currency = "EUR"
        case "¥", "CNY":
            currency = "CNY"
        default:
            // If it's already a proper currency code (3 letters), use it as is
            if rawCurrency.count == 3 && rawCurrency.allSatisfy({ $0.isLetter }) {
                currency = rawCurrency.uppercased()
            } else {
                // Otherwise fallback to ILS
                currency = "ILS"
            }
        }
        let sign: Double = transaction.normalizedAmount >= 0 ? 1 : -1

        var splitsArray: [SplitTransactionEntry] = []

        for entry in entries {
            let raw = Double(entry.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
            let signedAmount = raw * sign

            // Validate and trim required fields
            let trimmedCategory = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedBusinessName = entry.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
            let sanitizedFlowMonth = FlowMonthInputValidator.sanitizeFlowMonthInput(entry.flowMonth)
            let trimmedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if required fields are valid
            guard !trimmedCategory.isEmpty,
                  !trimmedBusinessName.isEmpty,
                  !sanitizedFlowMonth.isEmpty,
                  !trimmedCurrency.isEmpty else {
                return nil
            }

            let trimmedNotes = entry.notes.trimmingCharacters(in: .whitespacesAndNewlines)

            let splitEntry = SplitTransactionEntry(
                amount: signedAmount,
                category: trimmedCategory,
                businessName: trimmedBusinessName,
                flowMonth: sanitizedFlowMonth,
                paymentDate: paymentDate,
                currency: trimmedCurrency,
                description: trimmedNotes.isEmpty ? nil : trimmedNotes
            )

            splitsArray.append(splitEntry)
        }

        guard !splitsArray.isEmpty else {
            return nil
        }
        return splitsArray
    }

    private func formatted(amount: Double) -> String {
        String(format: "%.2f", amount)
    }

    private func initialFlowMonthString() -> String {
        if let raw = transaction.flow_month, FlowMonthInputValidator.isValidFlowMonth(raw) {
            return raw
        }
        if let date = transaction.parsedDate {
            return FlowMonthInputValidator.monthFormatter.string(from: date)
        }
        return FlowMonthInputValidator.monthFormatter.string(from: Date())
    }

    private func resolvedPaymentDate() -> String {
        if let payment = transaction.payment_date?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !payment.isEmpty {
            return payment
        }
        if let date = transaction.date?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !date.isEmpty {
            return date
        }
        if let parsed = transaction.parsedDate {
            return Self.isoFormatter.string(from: parsed)
        }
        return Self.isoFormatter.string(from: Date())
    }

    private var originalAmount: Double {
        abs(transaction.normalizedAmount)
    }

    private var currentSplitTotal: Double {
        entries.reduce(0) { partialResult, entry in
            let value = Double(entry.amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
            return partialResult + max(0, value)
        }
    }

    private var tolerance: Double { 0.05 }

    private var formattedPaymentDate: String? {
        guard let date = transaction.parsedDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.string(from: date)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
}

// MARK: - Category Picker Field Component

private struct CategoryPickerField: View {
    @Binding var selectedCategory: String
    let availableCategories: [String]
    let isLoading: Bool

    var body: some View {
        Menu {
            ForEach(availableCategories, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack {
                        Text(category)
                        if category == selectedCategory {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            if !selectedCategory.isEmpty {
                Divider()
                Button("נקה", role: .destructive) {
                    selectedCategory = ""
                }
            }
        } label: {
            HStack {
                Image(systemName: "chevron.down")
                    .font(.caption.bold())
                Text(selectedCategory.isEmpty ? "בחר קטגוריה" : selectedCategory)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(UIColor.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundColor(.primary)
        }
        .disabled(isLoading || availableCategories.isEmpty)
    }
}

// MARK: - Flow Month Selector Component

private struct FlowMonthSelector: View {
    @Binding var flowMonth: String
    @State private var internalDate: Date
    @State private var isExpanded = false
    
    init(flowMonth: Binding<String>) {
        _flowMonth = flowMonth
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        if let date = formatter.date(from: flowMonth.wrappedValue) {
            _internalDate = State(initialValue: date)
        } else {
            _internalDate = State(initialValue: Date())
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.accentColor)
                    
                    Text(formattedDisplay(flowMonth))
                        .font(.body.monospacedDigit())
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if !flowMonth.isEmpty {
                        Text(flowMonth)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack {
                    DatePicker(
                        "",
                        selection: $internalDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "he_IL"))
                    .onChange(of: internalDate) { _, newDate in
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM"
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        flowMonth = formatter.string(from: newDate)
                    }
                    
                    Button("סגור") {
                        withAnimation { isExpanded = false }
                    }
                    .font(.footnote.weight(.medium))
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func formattedDisplay(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        
        guard let date = formatter.date(from: raw) else { return raw }
        
        let display = DateFormatter()
        display.locale = Locale(identifier: "he_IL")
        display.dateFormat = "MMMM yyyy"
        return display.string(from: date)
    }
}

private struct SplitEntryDraft: Identifiable, Equatable {
    let id = UUID()
    var amountText: String
    var category: String
    var businessName: String
    var flowMonth: String
    var notes: String
    var isOriginal: Bool
}

private extension Binding where Value == SplitEntryDraft {
    var businessName: Binding<String> {
        Binding<String>(
            get: { wrappedValue.businessName },
            set: { wrappedValue.businessName = $0 }
        )
    }

    var notes: Binding<String> {
        Binding<String>(
            get: { wrappedValue.notes },
            set: { wrappedValue.notes = $0 }
        )
    }

    var flowMonth: Binding<String> {
        Binding<String>(
            get: { wrappedValue.flowMonth },
            set: { wrappedValue.flowMonth = $0 }
        )
    }

    func amountBinding(onChange: @escaping (String) -> Void) -> Binding<String> {
        Binding<String>(
            get: { wrappedValue.amountText },
            set: { newValue in
                wrappedValue.amountText = newValue
                onChange(newValue)
            }
        )
    }
}
