import SwiftUI
import UIKit

struct PendingTransactionsReviewView: View {
    @StateObject private var viewModel = PendingTransactionsReviewViewModel()
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
    @Environment(\.dismiss) private var dismiss

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
            heroSection(for: transaction)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    primaryActions(for: transaction)
                    secondaryActions(for: transaction)
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 60)
            }
            .background(Color.white)
        }
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
                Text("\(currencySymbol(for: transaction.currency)) \(heroAmountText(transaction.absoluteAmount))")
                    .font(.system(size: 46, weight: .bold)) // Updated size
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.business_name ?? transaction.payment_method ?? "עסקה ממתינה")
                    Text(formattedPaymentDate(for: transaction))
                    Text("חודש תזרים: \(displayedFlowMonth(for: transaction))")
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
            sheetDragOffset = UIScreen.main.bounds.height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }

    // MARK: - Yellow hero card



    private func heroNoteEditor(for transaction: Transaction) -> some View {
        let trimmed = heroNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .trailing, spacing: 10) {
            actionCardButton(
                title: heroNoteExpanded ? "סגור הערה" : (trimmed.isEmpty ? "הוסף הערה" : "ערוך הערה"),
                systemIcon: "square.and.pencil"
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    heroNoteExpanded.toggle()
                }
            }
            if heroNoteExpanded {
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $heroNoteText)
                        .frame(minHeight: 120)
                        .padding(12)
                        .background(Color(UIColor.systemGray5).opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .multilineTextAlignment(.leading)
                }
                Button {
                    Task { @MainActor in
                        let saved = await viewModel.saveNote(heroNoteText, for: transaction.id)
                        if saved {
                            heroNoteExpanded = false
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
                    .padding()
                    .background(Color.accentColor.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(viewModel.processingTransactionID == transaction.id)
            } else if !trimmed.isEmpty {
                Text(trimmed)
                    .font(.callout)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 18)
    }

    private func heroMoveFlowMonthEditor(for transaction: Transaction) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            actionCardButton(
                title: moveFlowMonthExpanded ? "בטל העברת תזרים" : "העברת תזרים לחודש אחר",
                systemIcon: "calendar.badge.plus"
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if moveFlowMonthExpanded {
                        moveFlowMonthExpanded = false
                    } else {
                        moveFlowMonthDate = flowMonthDate(for: transaction)
                        moveFlowMonthError = nil
                        moveFlowMonthExpanded = true
                    }
                }
            }

            if moveFlowMonthExpanded {
                VStack(alignment: .trailing, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("חודש תזרים")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                        DatePicker(
                            "",
                            selection: $moveFlowMonthDate,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .clipped()
                        Text(formattedFlowMonth(from: moveFlowMonthDate))
                            .font(.subheadline.monospacedDigit())
                            .frame(maxWidth: .infinity, alignment: .trailing)
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

                        Button {
                            submitMoveFlowMonth(transaction)
                        } label: {
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
                        .disabled(isMovingFlowMonth)
                        .opacity(isMovingFlowMonth ? 0.6 : 1)
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
                dismiss()
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
             // Edit Button (Secondary style - transparent with border)
             Button {
                 pendingCategoryChange = transaction
             } label: {
                 HStack {
                     Text("לערוך")
                         .font(.body.weight(.semibold))
                     Spacer()
                     Image(systemName: "square.and.pencil")
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

             // Approve Button (Primary style - filled)
             Button {
                 guard !isProcessing else { return }
                 Task { await viewModel.approve(transaction) }
             } label: {
                 HStack {
                     Text("להמשיך")
                         .font(.body.weight(.semibold))
                     Spacer()
                     Image(systemName: "arrowshape.turn.up.right")
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
        }
    }

    private func secondaryActions(for transaction: Transaction) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heroNoteEditor(for: transaction)
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
            
            // Move Category Action (Redundant if 'Edit' is top, but keeping per plan if desired, or maybe just remove?)
            // The user wanted "all options", so we can keep a specific move category if distinct from "Edit".
            // However, "Edit" usually opens the category sheet. Let's keep it consistent with EditTransactionView.
            // On Edit view, category is a section. Here "Edit" is a button.
            // Let's stick to the plan: Notes, Flow, Split, Move, Delete.
            
            Button {
                pendingCategoryChange = transaction
            } label: {
                 HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.title3)
                        .foregroundColor(.primary)
                    Text("שינוי קטגוריה")
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
                    Text("מחיקת עסקה")
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
