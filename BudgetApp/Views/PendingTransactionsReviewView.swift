import SwiftUI
import UIKit

struct PendingTransactionsReviewView: View {
    @EnvironmentObject var viewModel: PendingTransactionsReviewViewModel
    @State private var sheetDragOffset: CGFloat = 0
    @State private var pendingCategoryChange: Transaction?
    @State private var heroNoteExpanded = false
    @State private var heroNoteText = ""
    @State private var moveFlowMonthExpanded = false
    @State private var moveFlowMonthDate = Date()
    @State private var moveFlowMonthError: String?
    @State private var isMovingFlowMonth = false
    @State private var toastMessage: String?
    @State private var splitTransactionTarget: Transaction?
    
    // Inline Category Selection
    @State private var showCategorySelector = false
    @State private var categorySearchText = ""
    @State private var selectedCategory: String?
    @State private var isSavingCategory = false
    @State private var applyToAllFuture = false
    @State private var autoSaveTask: Task<Void, Never>?

    let cashFlowID: String
    var onDismiss: () -> Void

    private let swipeThreshold: CGFloat = 110

    private var currentTransaction: Transaction? {
        viewModel.transactions.first
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                // Dimmed Background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        animateDismissal()
                    }

                if let transaction = currentTransaction {
                    mainSheet(for: transaction, height: proxy.size.height)
                } else if viewModel.loading {
                     // Keep loading state simple or adapt
                     ProgressView()
                } else {
                     // Empty state
                     heroEmptyState
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .navigationTitle("") // Hide default title in sheet mode if needed, or keep
        .navigationBarHidden(true)
        .task {
            AppLogger.log("📱 [DEBUG] PendingTransactionsReviewView appeared")
            await viewModel.refresh()
        }
        .onChange(of: viewModel.transactions.first?.id) { oldValue, newValue in
            if let transaction = viewModel.transactions.first {
                heroNoteText = transaction.notes ?? ""
            } else {
                heroNoteText = ""
            }
        }
        .sheet(item: $pendingCategoryChange) { transaction in
             CategorySelectionSheet(
                transaction: transaction,
                categories: viewModel.categories,
                onSelect: { categoryName, note in
                    Task { await viewModel.reassign(transaction, to: categoryName, note: note) }
                },
                onSelectForFuture: { categoryName, note in
                    Task { await viewModel.reassignForFuture(transaction, to: categoryName, note: note) }
                },
                onDelete: {
                    Task { await viewModel.delete(transaction) }
                },
                onHideBusiness: {
                    Task { await viewModel.hideBusiness(transaction) }
                }
            )
        }
        .sheet(item: $splitTransactionTarget) { transaction in
            let availableCategories = prepareAvailableCategories(for: transaction)
            SplitTransactionSheet(
                transaction: transaction,
                availableCategories: availableCategories,
                onSubmit: { originalTransactionId, splits in
                    Task { @MainActor in
                        do {
                            try await viewModel.splitTransaction(
                                transaction,
                                originalTransactionId: originalTransactionId,
                                splits: splits
                            )
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                },
                onSuccess: {
                    splitTransactionTarget = nil
                }
            )
        }
        .overlay(alignment: .top) {
             if let toastMessage {
                 toastView(message: toastMessage)
                     .transition(.move(edge: .top).combined(with: .opacity))
                     .padding(.top, 12)
                     .padding(.horizontal, 24)
             }
        }
    }

    // MARK: - Layout

    private func mainSheet(for transaction: Transaction, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection(for: transaction)
                    
                    secondaryActions(for: transaction)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            
            primaryActions(for: transaction)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
                .padding(.top, 16)
                .background(Color.white)
        }
        // .dismissKeyboardOnTap() // Removed to fix button tap conflict
        .background(Color.white.opacity(0.98))
        .clipShape(TopRoundedSheetShape(radius: 32))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 0)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: height * 0.9, alignment: .bottom) // Start at 90% height like edit
        .offset(y: sheetDragOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sheetDragOffset)
        .gesture(sheetDismissGesture)
        .ignoresSafeArea(.container, edges: .bottom)
    }


    private func heroSection(for transaction: Transaction) -> some View {
        VStack(spacing: 12) {
            // Drag Handle
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.2))
                .frame(width: 48, height: 5)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                // Category
                Text(categoryLabel(for: transaction))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // Amount
                Text("\(heroAmountText(transaction.absoluteAmount)) \(currencySymbol(for: transaction.currency))")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    if let businessLine = heroBusinessLine(for: transaction) {
                        Text(businessLine)
                    }
                    if let cardLine = heroCardLine(for: transaction) {
                        Text(cardLine)
                    }
                    if let flowLine = heroFlowMonthLine(for: transaction) {
                        Text(flowLine)
                    }
                    if let dateLine = heroDateLine(for: transaction) {
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
        .contentShape(Rectangle())
        .highPriorityGesture(sheetDismissGesture)
    }

    private var sheetDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let translation = value.translation.height
                if translation > 0 {
                    sheetDragOffset = translation
                } else {
                    sheetDragOffset = 0
                }
            }
            .onEnded { value in
                let translation = value.translation.height
                let shouldDismiss = translation > 140 || value.predictedEndLocation.y - value.location.y > 160
                if shouldDismiss {
                    animateDismissal()
                } else {
                    withAnimation {
                        sheetDragOffset = 0
                    }
                }
            }
    }

    private func animateDismissal() {
        withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
            sheetDragOffset = screenHeight
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    private var screenHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.height ?? 0
    }

    private func resolvedFlowMonth(for transaction: Transaction) -> String {
        if let raw = transaction.flow_month, FlowMonthInputValidator.isValidFlowMonth(raw) {
            return raw
        }
        if let date = transaction.parsedDate {
            return FlowMonthInputValidator.monthFormatter.string(from: date)
        }
        return FlowMonthInputValidator.monthFormatter.string(from: Date())
    }

    private func submitMoveFlowMonth(_ transaction: Transaction) {
        let targetMonth = formattedFlowMonth(from: moveFlowMonthDate)
        moveFlowMonthError = nil
        isMovingFlowMonth = true
        Task {
            do {
                try await viewModel.move(transaction, toFlowMonth: targetMonth)
                await MainActor.run {
                    isMovingFlowMonth = false
                    moveFlowMonthExpanded = false
                }
            } catch {
                await MainActor.run {
                    moveFlowMonthError = error.localizedDescription
                    isMovingFlowMonth = false
                }
            }
        }
    }

    private func displayedFlowMonth(for transaction: Transaction) -> String {
        if moveFlowMonthExpanded {
            return formattedFlowMonth(from: moveFlowMonthDate)
        }
        return resolvedFlowMonth(for: transaction)
    }

    private func flowMonthDate(for transaction: Transaction) -> Date {
        if let raw = transaction.flow_month,
           let date = FlowMonthInputValidator.monthFormatter.date(from: raw) {
            return date
        }
        if let parsed = transaction.parsedDate {
            let formatted = FlowMonthInputValidator.monthFormatter.string(from: parsed)
            return FlowMonthInputValidator.monthFormatter.date(from: formatted) ?? parsed
        }
        let formatted = FlowMonthInputValidator.monthFormatter.string(from: Date())
        return FlowMonthInputValidator.monthFormatter.date(from: formatted) ?? Date()
    }

    private func formattedFlowMonth(from date: Date) -> String {
        FlowMonthInputValidator.monthFormatter.string(from: date)
    }

    private var heroEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundColor(.orange)
            Text("אין עסקאות ממתינות")
                .font(.title3.weight(.semibold))
            Text("רענן את המסך כדי לבדוק אם הגיעו עסקאות חדשות.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onDismiss()
            } label: {
                Text("סגור")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        .padding(.horizontal, 20)
    }

    private func primaryActions(for transaction: Transaction) -> some View {
        let isProcessing = viewModel.processingTransactionID == transaction.id
        return HStack(spacing: 12) {
             // Approve Button (Primary style - filled) - NOW FIRST (Right in RTL)
             Button {
                 guard !isProcessing else { return }
                 let noteToSave = heroNoteText.isEmpty ? nil : heroNoteText
                 Task { await viewModel.approve(transaction, note: noteToSave, cashFlowID: cashFlowID) }
             } label: {
                 HStack {
                     Text("להמשיך")
                         .font(.body.weight(.semibold))
                     Spacer()
                     Image(systemName: "checkmark")
                 }
                 .padding()
                 .frame(maxWidth: .infinity)
                 .background(
                     RoundedRectangle(cornerRadius: 16, style: .continuous)
                         .fill(Color.accentColor)
                 )
                 .foregroundColor(.white)
             }
             .buttonStyle(.plain)
             .disabled(isProcessing)
             .opacity(isProcessing ? 0.6 : 1)

             // Edit Button (Secondary style - transparent with border) - NOW SECOND (Left in RTL)
             Button {
                 pendingCategoryChange = transaction
             } label: {
                 HStack {
                     Text("לערוך")
                         .font(.body.weight(.semibold))
                     Spacer()
                     Image(systemName: "arrowshape.turn.up.right")
                 }
                 .padding()
                 .frame(maxWidth: .infinity)
                 .background(
                     RoundedRectangle(cornerRadius: 16, style: .continuous)
                         .strokeBorder(Color.accentColor, lineWidth: 1.5)
                 )
                 .foregroundColor(.accentColor)
             }
             .buttonStyle(.plain)
        }
    }

    private func secondaryActions(for transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heroNoteEditor(for: transaction)
            heroCategoryEditor(for: transaction)
            heroMoveFlowMonthEditor(for: transaction)
            
            // Split Action
            Button {
                splitTransactionTarget = transaction
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scissors")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Text("לפצל את ההוצאה")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard()
            


            // Delete Action
            Button {
                Task { await viewModel.delete(transaction) }
            } label: {
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
            
            if viewModel.transactions.count > 1 {
                Text("נותרו עוד \(viewModel.transactions.count - 1) טרנזקציות ממתינות")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 8)
            }
        }
    }

    private func heroNoteEditor(for transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    heroNoteExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Text(heroNoteExpanded ? "סגור הערה" : (heroNoteText.isEmpty ? "הוסף הערה" : "ערוך הערה"))
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard()

            if heroNoteExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $heroNoteText)
                        .frame(minHeight: 120, alignment: .top)
                        .padding(12)
                        .background(Color(UIColor.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .multilineTextAlignment(.leading)
                        .onChange(of: heroNoteText) { oldValue, newValue in
                            autoSaveTask?.cancel()
                            autoSaveTask = Task {
                                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s debounce
                                if !Task.isCancelled {
                                    // Skip save if the text matches what's already in the transaction (to avoid save on load)
                                    // But be careful about trimmed vs raw.
                                    // Simple check:
                                    let currentNote = transaction.notes ?? ""
                                    if newValue.trimmingCharacters(in: .whitespacesAndNewlines) != currentNote.trimmingCharacters(in: .whitespacesAndNewlines) {
                                         _ = await viewModel.saveNote(newValue, for: transaction.id, silent: true)
                                    }
                                }
                            }
                        }

                    Button {
                        Task { @MainActor in
                            let saved = await viewModel.saveNote(heroNoteText, for: transaction.id)
                            if saved {
                                withAnimation { heroNoteExpanded = false }
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.processingTransactionID == transaction.id {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            }
                            Text(viewModel.processingTransactionID == transaction.id ? "שומר..." : "שמור הערה")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(viewModel.processingTransactionID == transaction.id)
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



    private func heroCategoryEditor(for transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showCategorySelector.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Text(showCategorySelector ? "בטל שינוי" : "להזיז את ההוצאה")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .actionCard()

            .actionCard()

            if showCategorySelector {
                categorySelectionContent(for: transaction)
            }
        }
    }

    @ViewBuilder
    private func categorySelectionContent(for transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("בחר קטגוריה חדשה")
                .font(.subheadline.weight(.semibold))

            TextField("חפש קטגוריה…", text: $categorySearchText)
                .padding(10)
                .background(Color(UIColor.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .multilineTextAlignment(.trailing)

            if !categorySearchText.isEmpty {
                ForEach(filteredCategories(for: transaction), id: \.self) { category in
                    Button {
                        selectCategory(category, for: transaction)
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

            // Toggle for future transactions
            Button {
                withAnimation { applyToAllFuture.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: applyToAllFuture ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundColor(applyToAllFuture ? .accentColor : .secondary)
                    Text("החל על כל העסקאות העתידיות")
                        .font(.footnote)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            
            Button {
                commitCategoryChange(for: transaction)
            } label: {
                HStack {
                   if isSavingCategory {
                       ProgressView().progressViewStyle(.circular)
                   }
                   Text(isSavingCategory ? "שומר..." : "שמור קטגוריה")
                       .font(.body.weight(.semibold))
                       .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSavingCategory)
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
    
    private func selectCategory(_ category: String, for transaction: Transaction) {
        selectedCategory = category
        // dismissKeyboard() // Helper if needed
    }


// ... existing ...

    private func commitCategoryChange(for transaction: Transaction) {
        let trimmedSearch = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = selectedCategory
        let newCategory = chosen ?? (!trimmedSearch.isEmpty ? trimmedSearch : transaction.effectiveCategoryName)
        
        guard !newCategory.isEmpty else { return }
        
        isSavingCategory = true
        let shouldApplyToFuture = applyToAllFuture
        
        Task {
            if shouldApplyToFuture {
                await viewModel.reassignForFuture(transaction, to: newCategory, note: nil)
            } else {
                await viewModel.reassign(transaction, to: newCategory, note: nil)
            }
            
            await MainActor.run {
                isSavingCategory = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    showCategorySelector = false
                    categorySearchText = ""
                    selectedCategory = nil
                    applyToAllFuture = false
                }
            }
        }
    }
    
    private func filteredCategories(for transaction: Transaction) -> [String] {
        let available = prepareAvailableCategories(for: transaction)
        let search = categorySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return available }
        return available
            .filter { $0.localizedCaseInsensitiveContains(search) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func heroMoveFlowMonthEditor(for transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if moveFlowMonthExpanded {
                        moveFlowMonthExpanded = false
                    } else {
                        moveFlowMonthDate = flowMonthDate(for: transaction)
                        moveFlowMonthError = nil
                        moveFlowMonthExpanded = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Text(moveFlowMonthExpanded ? "בטל העברת תזרים" : "העברת תזרים לחודש אחר")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
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
                     
                     Text(formattedFlowMonth(from: moveFlowMonthDate))
                        .font(.subheadline.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                     
                     if let error = moveFlowMonthError {
                         Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                     }

                     HStack(spacing: 12) {
                         Button("בטל") {
                             withAnimation { moveFlowMonthExpanded = false }
                         }
                         
                         Spacer()
                         
                         Button {
                             submitMoveFlowMonth(transaction)
                         } label: {
                             HStack {
                                 if isMovingFlowMonth {
                                     ProgressView().progressViewStyle(.circular)
                                 }
                                 Text(isMovingFlowMonth ? "מעביר..." : "שמור לחודש זה")
                                     .font(.body.weight(.semibold))
                             }
                         }
                         .disabled(isMovingFlowMonth)
                     }
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

    private func showToastMessage(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            if toastMessage == message {
                withAnimation {
                    toastMessage = nil
                }
            }
        }
    }

    private func toastView(message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
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

    private func prepareAvailableCategories(for transaction: Transaction) -> [String] {
        let trimmedCategoryNames = viewModel.categories
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var uniqueCategories = Set(trimmedCategoryNames)
        let effectiveCategory = transaction.effectiveCategoryName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !effectiveCategory.isEmpty {
            _ = uniqueCategories.insert(effectiveCategory)
        }
        var availableCategories = Array(uniqueCategories).sorted()
        if availableCategories.isEmpty {
            let fallback = effectiveCategory.isEmpty ? "הוצאות משתנות" : effectiveCategory
            availableCategories = [fallback]
        }
        return availableCategories
    }

    private func categoryLabel(for transaction: Transaction) -> String {
        let trimmedEffective = transaction.effectiveCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEffective.isEmpty {
            return trimmedEffective
        }
        if let fallback = transaction.category?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty {
            return fallback
        }
        return "הוצאות משתנות"
    }

    // MARK: - Hero Helpers (Parity with EditTransactionView)

    private func heroBusinessLine(for transaction: Transaction) -> String? {
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

    private func heroCardLine(for transaction: Transaction) -> String? {
        let method = transaction.payment_method?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let method, !method.isEmpty else { return nil }
        return "כרטיס \(method)"
    }

    private func heroDateLine(for transaction: Transaction) -> String? {
        guard let date = transaction.parsedDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateFormat = "d.M.yy"
        return formatter.string(from: date)
    }

    private func heroFlowMonthLine(for transaction: Transaction) -> String? {
        // Use live state if expanding/editing, otherwise transaction
        let raw: String = {
             if moveFlowMonthExpanded {
                 return formattedFlowMonth(from: moveFlowMonthDate)
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
}
