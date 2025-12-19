import SwiftUI

struct ReviewedTransactionsSearchView: View {
    @StateObject private var viewModel = ReviewedTransactionsSearchViewModel()
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var showingRevertConfirmation = false
    @State private var toastMessage: String?
    @State private var toastWorkItem: DispatchWorkItem?
    @State private var editingTransaction: Transaction?
    @EnvironmentObject private var vm: CashFlowDashboardViewModel
    // EditTransactionView expects `onSave` and `onDelete`. We can implement them using `viewModel`.


    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    searchBar
                    queryPreview
                    statusMessage
                    resultsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 140)
            }

            actionButton
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .navigationTitle("עסקאות שנבחנות מחדש")
        .environment(\.layoutDirection, .rightToLeft)
        .onChange(of: searchText) { newValue, _ in
            scheduleSearch(for: newValue)
        }
        .onChange(of: viewModel.actionMessage) { newValue, _ in
            guard let value = newValue else { return }
            toastWorkItem?.cancel()
            toastMessage = value
            let workItem = DispatchWorkItem {
                toastMessage = nil
                viewModel.actionMessage = nil
            }
            toastWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: workItem)
        }
        .onDisappear {
            searchTask?.cancel()
            toastWorkItem?.cancel()
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                toastView(message: toastMessage)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }
        }
        .overlay(alignment: .center) {
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
                        onSave: { _ in
                            withAnimation {
                                editingTransaction = nil
                            }
                            scheduleSearch(for: searchText)
                        },
                        onDelete: { deletedTx in
                            Task {
                                await vm.deleteTransaction(deletedTx)
                                await MainActor.run {
                                    withAnimation {
                                        editingTransaction = nil
                                    }
                                    scheduleSearch(for: searchText)
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
        .confirmationDialog(
            "החזרת עסקאות ל־pending",
            isPresented: $showingRevertConfirmation,
            titleVisibility: .visible
        ) {
            Button("החזר ל־pending", role: .destructive) {
                Task { await viewModel.revertSelected() }
            }
            Button("ביטול", role: .cancel) {}
        } message: {
            Text("אתה עומד להחזיר את העסקאות שנבחרו חזרה למצב pending.")
        }
    }

    private var searchBar: some View {
        TextField("חפש עסק לפי שם", text: $searchText)
            .textInputAutocapitalization(.words)
            .disableAutocorrection(true)
            .padding(.vertical, 14)
            .padding(.horizontal, 48)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .overlay(alignment: .trailing) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .padding(.trailing, 16)
            }
            .multilineTextAlignment(.trailing)
    }

    private var queryPreview: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .trailing, spacing: 6) {
            if trimmed.count >= 3 {
                Text("חיפוש פעיל")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text(trimmed)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color(UIColor.systemGray4), lineWidth: 0.8)
                    )
            } else {
                Text("הקלד לפחות 3 תווים כדי להתחיל בחיפוש")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var statusMessage: some View {
        Group {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var resultsSection: some View {
        Group {
            if viewModel.loading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if viewModel.transactions.isEmpty {
                Text("אין עסקאות צפויות להופיע עד להשלמת חיפוש עם לפחות 3 תווים.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.transactions, id: \.id) { transaction in
                        transactionCard(transaction)
                    }
                    if viewModel.canLoadOlderResults || viewModel.isLoadingOlderResults {
                        loadOlderButton
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var loadOlderButton: some View {
        Button {
            Task { await viewModel.loadOlderResults() }
        } label: {
            VStack(spacing: 6) {
                HStack {
                    Text("טען תוצאות ישנות יותר")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                    if viewModel.isLoadingOlderResults {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
                if let label = viewModel.earliestLoadedMonthLabel {
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
        .disabled(viewModel.isLoadingOlderResults)
        .opacity(viewModel.isLoadingOlderResults ? 0.8 : 1)
    }

    private func transactionCard(_ transaction: Transaction) -> some View {
        let isSelected = viewModel.selectedTransactionIDs.contains(transaction.id)
        return HStack(alignment: .top, spacing: 16) {
            selectionButton(isSelected: isSelected) {
                toggleSelection(transaction.id)
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(transaction.business_name ?? "עסק חסר שם")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                        Text(transaction.category_name ?? transaction.effectiveCategoryName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Spacer()
                    Text(formattedAmount(for: transaction))
                        .font(.headline)
                        .foregroundColor(transaction.absoluteAmount >= 0 ? .green : .primary)
                }
                HStack(spacing: 16) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("תאריך תשלום")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(transaction.payment_date ?? "לא נמסר")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("חודש תזרים")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(transaction.flow_month ?? "N/A")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            editingTransaction = transaction
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func selectionButton(isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ id: String) {
        if viewModel.selectedTransactionIDs.contains(id) {
            viewModel.selectedTransactionIDs.remove(id)
        } else {
            viewModel.selectedTransactionIDs.insert(id)
        }
    }

    private var actionButton: some View {
        Button {
            showingRevertConfirmation = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrowshape.turn.up.left")
                Text("החזר ל-pending")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(viewModel.selectedTransactionIDs.isEmpty || viewModel.processingReversion
                          ? Color.gray.opacity(0.4)
                          : Color.blue)
            )
        }
        .disabled(viewModel.selectedTransactionIDs.isEmpty || viewModel.processingReversion)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .overlay {
            if viewModel.processingReversion {
                ProgressView()
                    .progressViewStyle(.circular)
                    .foregroundColor(.white)
            }
        }
    }

    private func formattedAmount(for transaction: Transaction) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: abs(transaction.absoluteAmount))) ?? "\(abs(transaction.absoluteAmount))"
        let symbol = currencySymbol(for: transaction.currency)
        if transaction.absoluteAmount < 0 {
            return "-\(value)\(symbol)"
        }
        return "\(value)\(symbol)"
    }

    private func currencySymbol(for code: String?) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code ?? "ILS"
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.currencySymbol ?? "₪"
    }

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await viewModel.search(for: text)
        }
    }

    private func toastView(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(12)
            .background(Color.black.opacity(0.75))
            .cornerRadius(16)
            .frame(maxWidth: .infinity)
    }
}
