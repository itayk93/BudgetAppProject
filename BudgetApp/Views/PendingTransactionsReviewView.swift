import SwiftUI
import UIKit

struct PendingTransactionsReviewView: View {
    @StateObject private var viewModel = PendingTransactionsReviewViewModel()
    @State private var dragOffset: CGSize = .zero
    @State private var pendingCategoryChange: Transaction?
    @State private var heroNoteExpanded = false
    @State private var heroNoteText = ""
    @State private var toastMessage: String?
    @State private var startSplitFlow = false
    @Environment(\.dismiss) private var dismiss

    private let swipeThreshold: CGFloat = 110

    private var currentTransaction: Transaction? {
        viewModel.transactions.first
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.groupedBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroSection
                    Spacer().frame(height: 30)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 18)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("אישור עסקאות")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            print("📱 [DEBUG] PendingTransactionsReviewView appeared, refreshing")
            await viewModel.refresh()
        }
        .refreshable {
            print("📱 [DEBUG] Pull to refresh triggered")
            await viewModel.refresh()
        }
        .sheet(item: $pendingCategoryChange) { transaction in
            print("📦 [CATEGORY SHEET] Opening for tx=\\(transaction.id)")
            return CategorySelectionSheet(
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
                },
                onSplit: { originalTransactionId, splits in
                    Task {
                        do {
                            try await viewModel.splitTransaction(
                                transaction,
                                originalTransactionId: originalTransactionId,
                                splits: splits
                            )
                        } catch {
                        print("❌ splitTransaction failed:", error)
                        }
                    }
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
        .onChange(of: viewModel.actionMessage) { _, newValue in
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
        }
        .environment(\.layoutDirection, .rightToLeft)
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

    private func heroCardView(_ transaction: Transaction) -> some View {
        print("📋 [HERO CARD] Displaying transaction id=\\(transaction.id)")
        return VStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: 10) {
                HStack {
                    Spacer()
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
                }
                Text(categoryLabel(for: transaction))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("\(currencySymbol(for: transaction.currency))\(heroAmountText(transaction.absoluteAmount))")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(transaction.business_name ?? transaction.payment_method ?? "עסקה ממתינה")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.95))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(transaction.payment_method ?? "כרטיס • \(transaction.id.suffix(4))")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(formattedPaymentDate(for: transaction))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .background(heroYellowColor)

            VStack(spacing: 12) {
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
            heroNoteEditor(for: transaction)
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
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard viewModel.processingTransactionID == nil && pendingCategoryChange == nil else { return }
                if case .second(true, let drag?) = value {
                    dragOffset = CGSize(width: drag.translation.width, height: 0)
                }
            }
            .onEnded { value in
                guard viewModel.processingTransactionID == nil && pendingCategoryChange == nil else {
                    withAnimation(.spring()) {
                        dragOffset = .zero
                    }
                    return
                }
                if case .second(true, let drag?) = value {
                    handleDragEnd(translationX: drag.translation.width, transaction: transaction)
                } else {
                    withAnimation(.spring()) {
                        dragOffset = .zero
                    }
                }
            }
    }

    private func heroActionButton(_ action: HeroAction) -> some View {
        Button {
            action.action()
        } label: {
            HStack(spacing: 12) {
                Text(action.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: action.icon)
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .padding()
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
            HeroAction(id: "note", icon: "text.bubble", title: "הערה") {
                heroNoteExpanded = true
                heroNoteText = transaction.notes ?? ""
            },
            HeroAction(id: "move", icon: "arrowshape.turn.up.right", title: "להזיז את ההוצאה") {
                print("🔄 [HERO ACTION] Move tapped for tx=\\(transaction.id)")
                pendingCategoryChange = transaction
            },
            HeroAction(id: "split", icon: "scissors", title: "לפצל את ההוצאה") {
                startSplitFlow = true
                pendingCategoryChange = transaction
            },
            HeroAction(id: "savings", icon: "banknote", title: "הפקדה לחיסכון") {
                showToastMessage("סומן כהפקדה לחיסכון.")
            }
        ]
    }

    private func heroNoteEditor(for transaction: Transaction) -> some View {
        let trimmed = heroNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .trailing, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    heroNoteExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(heroNoteExpanded ? "סגור הערה" : (trimmed.isEmpty ? "הוסף הערה" : "ערוך הערה"))
                            .font(.body.weight(.semibold))
                        Text(trimmed.isEmpty ? "הוסיפו מידע שיעזור לכמה שורות" : "הערתך הנוכחית")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if heroNoteExpanded {
                ZStack(alignment: .topTrailing) {
                    if trimmed.isEmpty {
                        Text("לדוגמה: טלפון לשליח, בדיקת חשבונית")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
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
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
        .padding(.horizontal, 20)
    }

    private func handleDragEnd(translationX: CGFloat, transaction: Transaction) {
        if translationX > swipeThreshold {
            withAnimation {
                dragOffset = CGSize(width: translationX, height: 0)
            }
            Task { await viewModel.approve(transaction) }
        } else if translationX < -swipeThreshold {
            withAnimation {
                dragOffset = CGSize(width: translationX, height: 0)
            }
            pendingCategoryChange = transaction
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

private struct CategorySelectionSheet: View {
    let transaction: Transaction
    let categories: [TransactionCategory]
    var onSelect: (String, String?) -> Void
    var onSelectForFuture: (String, String?) -> Void
    var onDelete: () -> Void
    var onHideBusiness: () -> Void
    var onSplit: (String, [SplitTransactionEntry]) -> Void

    @State private var selectedCategory: String?
    @State private var noteText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: 16) {
                    Text(transaction.business_name ?? transaction.payment_method ?? "שינוי קטגוריה")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if categories.isEmpty {
                        Text("טוען קטגוריות זמינות...")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.vertical, 40)
                    } else {
                        LazyVStack(alignment: .trailing, spacing: 12) {
                            ForEach(categories) { category in
                                Button {
                                    selectedCategory = category.name
                                } label: {
                                    Text(category.name)
                                        .foregroundColor(selectedCategory == category.name ? .accentColor : .primary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(selectedCategory == category.name ? Color.accentColor.opacity(0.15) : Color(UIColor.systemGray5))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .trailing, spacing: 6) {
                        Text("הערה (אופציונלי)")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: $noteText)
                            .frame(minHeight: 100)
                            .padding(10)
                            .background(Color(UIColor.systemGray5))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button("אשר שינוי קטגוריה") {
                        guard let categoryName = selectedCategory else { return }
                        dismiss()
                        onSelect(categoryName, noteValue)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .disabled(selectedCategory == nil)

                    Button("החיל על כל העסקאות העתידיות") {
                        guard let categoryName = selectedCategory else { return }
                        dismiss()
                        onSelectForFuture(categoryName, noteValue)
                    }
                    .disabled(selectedCategory == nil)

                    Divider()

                    Button(role: .destructive) {
                        dismiss()
                        onDelete()
                    } label: {
                        Text("מחק עסקה")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button("הסר בית עסק") {
                        dismiss()
                        onHideBusiness()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(UIColor.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding()
            }
            .navigationTitle("החלפת קטגוריה")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("בטל") { dismiss() }
                }
            }
        }
    }

    private var noteValue: String? {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
