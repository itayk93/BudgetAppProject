import SwiftUI

struct TransactionDetailsView: View {
    let transaction: Transaction
    
    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 20) {
                transactionCard
                
                detailsSection
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("פרטי עסקה")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
    
    private var transactionCard: some View {
        let theme = transactionCardTheme(for: transaction)
        return VStack(alignment: .trailing, spacing: 28) {
            categoryHeader
            heroAmountSection
            heroDetailsSection
        }
        .multilineTextAlignment(.trailing)
        .padding(.vertical, 32)
        .padding(.horizontal, 30)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(theme.gradient)
        )
        .overlay(alignment: .topTrailing) {
            iconStamp
        }
    }
    
    private var categoryHeader: some View {
        VStack(alignment: .trailing, spacing: 6) {
            let effectiveCategory = transaction.effectiveCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !effectiveCategory.isEmpty {
                Text(effectiveCategory)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 16)
                    .background(
                        Capsule()
                            .fill(theme.accentSoft.opacity(0.4))
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    private var heroAmountSection: some View {
        VStack(spacing: 10) {
            Text(transaction.isIncome ? "נכנס" : "יצא")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Text(transaction.currency ?? "₪")
                    .font(.title3.weight(.medium))
                Text(formatAmount(transaction.absoluteAmount))
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.accent)
                    .monospacedDigit()
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var heroDetailsSection: some View {
        let lines = heroDetailLines
        return VStack(spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { detail in
                Text(detail.element)
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.primary.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
    
    private var heroDetailLines: [String] {
        var lines: [String] = []
        if let merchant = merchantLine { lines.append(merchant) }
        if let paymentDate = formattedPaymentDate { lines.append(paymentDate) }
        if let reference = referenceLine { lines.append(reference) }
        return lines
    }
    
    private var merchantLine: String? {
        guard let name = transaction.business_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return nil
        }
        return name
    }
    
    private var referenceLine: String? {
        if let method = transaction.payment_method?.trimmingCharacters(in: .whitespacesAndNewlines), !method.isEmpty {
            return method
        }
        return formattedCreatedAt
    }
    
    private var iconStamp: some View {
        Circle()
            .fill(Color.white.opacity(0.7))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: theme.symbol)
                    .foregroundColor(theme.accent)
            )
            .padding(16)
    }
    
    private var theme: TransactionCardTheme {
        return transactionCardTheme(for: transaction)
    }
    
    private var formattedPaymentDate: String? {
        guard let parsed = transaction.parsedDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateStyle = .medium
        return formatter.string(from: parsed)
    }
    
    private var formattedCreatedAt: String? {
        guard let created = transaction.createdAtDate else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: created)
    }
    
    private func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func transactionCardTheme(for transaction: Transaction) -> TransactionCardTheme {
        if transaction.isIncome {
            return TransactionCardTheme(
                topColor: Color(red: 0.9, green: 0.96, blue: 0.84),
                bottomColor: Color(red: 0.99, green: 0.96, blue: 0.9),
                accent: Color(red: 0.2, green: 0.55, blue: 0.3),
                accentSoft: Color(red: 0.78, green: 0.9, blue: 0.72),
                symbol: "arrow.down.circle.fill"
            )
        } else {
            return TransactionCardTheme(
                topColor: Color(red: 0.88, green: 0.93, blue: 1.0),
                bottomColor: Color(red: 0.95, green: 0.98, blue: 1.0),
                accent: Color(red: 0.2, green: 0.35, blue: 0.74),
                accentSoft: Color(red: 0.76, green: 0.85, blue: 1.0),
                symbol: "arrow.up.circle.fill"
            )
        }
    }
    
    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .trailing, spacing: 12) {
            GroupBox("פרטי העסקה") {
                VStack(alignment: .trailing, spacing: 8) {
                    if let businessName = transaction.business_name, !businessName.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("שם בית העסק:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(businessName)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let paymentMethod = transaction.payment_method, !paymentMethod.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("אמצעי תשלום:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(paymentMethod)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let notes = transaction.notes, !notes.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("הערות:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(notes)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let parsedDate = transaction.parsedDate {
                        HStack(alignment: .top, spacing: 8) {
                            Text("תאריך:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formattedDateLong(parsedDate))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if let createdAt = transaction.createdAtDate {
                        HStack(alignment: .top, spacing: 8) {
                            Text("תאריך יצירה:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formattedDateTime(createdAt))
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text("סכום:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatCurrency(transaction.absoluteAmount))
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    HStack(alignment: .top, spacing: 8) {
                        Text("валוטה:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(transaction.currency ?? "ILS")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    HStack(alignment: .top, spacing: 8) {
                        Text("מזהה עסקה:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(transaction.id)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = transaction.currency ?? "ILS"
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func formattedDateLong(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct TransactionCardTheme {
    let topColor: Color
    let bottomColor: Color
    let accent: Color
    let accentSoft: Color
    let symbol: String

    var gradient: LinearGradient {
        LinearGradient(colors: [topColor, bottomColor], startPoint: .top, endPoint: .bottom)
    }
}