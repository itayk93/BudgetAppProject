import SwiftUI

struct MoveTransactionFlowMonthSheet: View {
    let transaction: Transaction
    let onSubmit: @Sendable (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var flowMonthText: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var flowFieldFocused: Bool

    init(
        transaction: Transaction,
        onSubmit: @escaping @Sendable (String) async throws -> Void
    ) {
        self.transaction = transaction
        self.onSubmit = onSubmit
        let initial = MoveTransactionFlowMonthSheet.initialFlowMonth(for: transaction)
        _flowMonthText = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    transactionCard

                    VStack(alignment: .trailing, spacing: 8) {
                        Text("חודש תזרים חדש (yyyy-MM)")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                        TextField("2025-11", text: $flowMonthText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .padding(16)
                            .background(Color(UIColor.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .font(.title3.monospacedDigit())
                            .focused($flowFieldFocused)
                        .onChange(of: flowMonthText) { newValue, _ in
                            let sanitized = FlowMonthInputValidator.sanitizeFlowMonthInput(newValue)
                            if sanitized != newValue {
                                flowMonthText = sanitized
                            }
                            }
                        Text("לדוגמה: 2025-12")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("חודש תזרים אחר")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { flowFieldFocused = true }
    }

    private var transactionCard: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(transaction.business_name ?? transaction.payment_method ?? "עסקה")
                .font(.headline)
            Text("₪\(formattedAmount(abs(transaction.normalizedAmount)))")
                .font(.title3.bold())
                .foregroundColor(.accentColor)
            Text("חודש תזרים נוכחי: \(currentFlowMonthLabel)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding()
        .background(Color(UIColor.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var actionBar: some View {
        VStack(spacing: 12) {
            if isSubmitting {
                ProgressView("שומר...")
                    .frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                Button("סגור") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(UIColor.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    submitFlowMonthChange()
                } label: {
                    Text("שמור לחודש זה")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(!FlowMonthInputValidator.isValidFlowMonth(flowMonthText) || isSubmitting)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func submitFlowMonthChange() {
        guard FlowMonthInputValidator.isValidFlowMonth(flowMonthText) else {
            errorMessage = "הזן חודש תזרים תקין בפורמט yyyy-MM"
            return
        }
        errorMessage = nil
        isSubmitting = true
        let targetMonth = flowMonthText
        Task {
            do {
                try await onSubmit(targetMonth)
                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }

    private var currentFlowMonthLabel: String {
        if let raw = transaction.flow_month, !raw.isEmpty {
            return raw
        }
        if let date = transaction.parsedDate {
            return FlowMonthInputValidator.monthFormatter.string(from: date)
        }
        return FlowMonthInputValidator.monthFormatter.string(from: Date())
    }

    private static func initialFlowMonth(for transaction: Transaction) -> String {
        if let raw = transaction.flow_month, FlowMonthInputValidator.isValidFlowMonth(raw) {
            return raw
        }
        if let date = transaction.parsedDate {
            return FlowMonthInputValidator.monthFormatter.string(from: date)
        }
        return FlowMonthInputValidator.monthFormatter.string(from: Date())
    }

    private func formattedAmount(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }
}
