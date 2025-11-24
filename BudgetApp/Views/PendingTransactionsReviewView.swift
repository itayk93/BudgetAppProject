import SwiftUI
import UIKit

struct PendingTransactionsReviewView: View {
    @StateObject private var viewModel = PendingTransactionsReviewViewModel()
    @State private var dragOffset: CGSize = .zero
    @State private var pendingCategoryChange: Transaction?
    @State private var heroNoteExpanded = false
    @State private var heroNoteText = ""
    @State private var moveFlowMonthExpanded = false
    @State private var moveFlowMonthText = ""
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
        contentView
            .dismissKeyboardOnTap()
            .navigationTitle("אישור עסקאות")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                AppLogger.log("📱 [DEBUG] PendingTransactionsReviewView appeared, refreshing")
                await viewModel.refresh()
            }
            .refreshable {
                AppLogger.log("📱 [DEBUG] Pull to refresh triggered")
                await viewModel.refresh()
            }
            .sheet(item: $pendingCategoryChange) { transaction in
                CategorySelectionSheet(
                    transaction: transaction,
                    categories: viewModel.categories,
                    onSelect: { categoryName, note in
                        Task {
                            await viewModel.reassign(transaction, to: categoryName, note: note)
                        }
                    },
                    onSelectForFuture: { categoryName, note in
                        Task {
                            await viewModel.reassignForFuture(transaction, to: categoryName, note: note)
                        }
                    },
                    onDelete: {
                        Task {
                            await viewModel.delete(transaction)
                        }
                    },
                    onHideBusiness: {
                        Task {
                            await viewModel.hideBusiness(transaction)
                        }
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
            .onChange(of: viewModel.actionMessage) { newValue, _ in
                guard let newValue else { return }
                toastMessage = newValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
                    if toastMessage == newValue {
                        withAnimation {
                            toastMessage = nil
                        }
                        viewModel.actionMessage = nil
                    }
                }
            }
            .onChange(of: viewModel.transactions.first?.id) { _, _ in
                dragOffset = .zero
                heroNoteExpanded = false
                heroNoteText = currentTransaction?.notes ?? ""
                moveFlowMonthExpanded = false
                moveFlowMonthError = nil
            }
            // RTL גלובלי – ה־HStackים של הכפתורים נשארים כמו בעבר,
            // ואת הכרטיס הצהוב אנחנו מיישרים ידנית לצד ימין.
            .environment(\.layoutDirection, .rightToLeft)
    }

    private var contentView: some View {
        ZStack(alignment: .top) {
            Color(UIColor.systemGray5).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroSection
                    if let transaction = currentTransaction {
                        heroFooter(for: transaction)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 12)
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private var heroSection: some View {
        if let transaction = currentTransaction {
            heroCardView(transaction)
        } else if viewModel.loading {
            heroLoadingPlaceholder
        } else {
            heroEmptyState
        }
    }

    // MARK: - Yellow hero card

    private func heroCardView(_ transaction: Transaction) -> some View {
        VStack(spacing: 0) {
            // חלק הכותרת הצהוב
            VStack(alignment: .leading, spacing: 8) {
                // 1. כפתור סגירה – חזותית בצד ימין-עליון ב־RTL
                HStack {
                    Button {
                        dismiss()
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
                .frame(maxWidth: .infinity, alignment: .trailing)

                // 2. כותרת קטגוריה
                Text(categoryLabel(for: transaction))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // 3. סכום ראשי
                Text("\(currencySymbol(for: transaction.currency))\(heroAmountText(transaction.absoluteAmount))")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // 4. שם העסק / תיאור
                Text(transaction.business_name ?? transaction.payment_method ?? "עסקה ממתינה")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.95))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // 5. תאריך עסקה
                Text(formattedPaymentDate(for: transaction))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                // 6. חודש תזרים
                Text("חודש תזרים: \(displayedFlowMonth(for: transaction))")
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

            // אזור הלבן עם האקשנים
            VStack(spacing: 12) {
                heroNoteEditor(for: transaction)
                heroMoveFlowMonthEditor(for: transaction)
                ForEach(heroActions(for: transaction)) { action in
                    heroActionButton(action)
                }
                if viewModel.transactions.count > 1 {
                    Text("נותרו עוד \(viewModel.transactions.count - 1) טרנזקציות ממתינות")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
        .offset(x: dragOffset.width, y: 0)
        .rotationEffect(.degrees(Double(dragOffset.width / 10)))
        .gesture(heroDragGesture(for: transaction))
        .onTapGesture {
            guard viewModel.processingTransactionID == nil && pendingCategoryChange == nil else { return }
            pendingCategoryChange = transaction
        }
        .allowsHitTesting(viewModel.processingTransactionID == nil && pendingCategoryChange == nil)
        .onAppear {
            heroNoteText = transaction.notes ?? ""
        }
    }

    private func heroDragGesture(for transaction: Transaction) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let clamped = min(0, value.translation.width) // Only allow swiping left
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    dragOffset = CGSize(width: clamped, height: 0)
                }
            }
            .onEnded { value in
                handleDragEnd(translationX: value.translation.width, transaction: transaction)
            }
    }

    private func heroActionButton(_ action: HeroAction) -> some View {
        actionCardButton(
            title: action.title,
            systemIcon: action.icon,
            action: action.action
        )
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

    private func heroActions(for transaction: Transaction) -> [HeroAction] {
        [
            HeroAction(id: "move", icon: "arrowshape.turn.up.right", title: "להזיז את ההוצאה") {
                AppLogger.log("🔄 [HERO ACTION] Move tapped for tx=\(transaction.id)")
                pendingCategoryChange = transaction
            },
            HeroAction(id: "split", icon: "scissors", title: "לפצל את ההוצאה") {
                splitTransactionTarget = transaction
            },
            HeroAction(id: "delete", icon: "trash", title: "מחיקת עסקה") {
                Task {
                    await viewModel.delete(transaction)
                }
            }
        ]
    }

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
                        .multilineTextAlignment(.trailing)
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
                        moveFlowMonthText = resolvedFlowMonth(for: transaction)
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
                            .onChange(of: moveFlowMonthText) { newValue, _ in
                                let sanitized = FlowMonthInputValidator.sanitizeFlowMonthInput(newValue)
                                if sanitized != newValue {
                                    moveFlowMonthText = sanitized
                                }
                            }
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
                        .disabled(
                            !FlowMonthInputValidator.isValidFlowMonth(moveFlowMonthText) || isMovingFlowMonth
                        )
                        .opacity(!FlowMonthInputValidator.isValidFlowMonth(moveFlowMonthText) || isMovingFlowMonth ? 0.6 : 1)
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
        guard FlowMonthInputValidator.isValidFlowMonth(moveFlowMonthText) else {
            moveFlowMonthError = "הזן חודש תזרים תקין בפורמט yyyy-MM"
            return
        }
        moveFlowMonthError = nil
        isMovingFlowMonth = true
        Task {
            do {
                try await viewModel.move(transaction, toFlowMonth: moveFlowMonthText)
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
        if moveFlowMonthExpanded && FlowMonthInputValidator.isValidFlowMonth(moveFlowMonthText) {
            return moveFlowMonthText
        }
        return resolvedFlowMonth(for: transaction)
    }

    private func heroFooter(for transaction: Transaction) -> some View {
        let remaining = max(viewModel.transactions.count - 1, 0)
        let isProcessing = viewModel.processingTransactionID == transaction.id
        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("נותרו עוד")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Text("\(remaining)")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text("עסקאות ממתינות")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                footerActionButton(
                    title: "לערוך",
                    systemIcon: "square.and.pencil",
                    filled: false,
                    action: {
                        pendingCategoryChange = transaction
                    }
                )
                footerActionButton(
                    title: "להמשיך",
                    systemIcon: "arrowshape.turn.up.right",
                    filled: true,
                    action: {
                        guard !isProcessing else { return }
                        Task {
                            await viewModel.approve(transaction)
                        }
                    },
                    disabled: isProcessing
                )
            }

            Text("שמרנו את ההוצאה הזו בקטגוריית \(categoryLabel(for: transaction)).")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        )
    }

    private func footerActionButton(
        title: String,
        systemIcon: String,
        filled: Bool,
        action: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
                Spacer()
                Image(systemName: systemIcon)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                Group {
                    if filled {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
            )
            .foregroundColor(filled ? .white : .accentColor)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }

    private var heroLoadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accentColor))
            Text("טוען עסקאות ממתינות...")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 20)
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

    private func handleDragEnd(translationX: CGFloat, transaction: Transaction) {
        if translationX < -swipeThreshold {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                dragOffset = CGSize(width: max(translationX, -220), height: 0)
            }
            Task { await viewModel.approve(transaction) }
        } else {
            withAnimation(.spring()) {
                dragOffset = .zero
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

private struct HeroAction: Identifiable {
    let id: String
    let icon: String
    let title: String
    let action: () -> Void
}
