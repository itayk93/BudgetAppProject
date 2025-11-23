import SwiftUI
import Foundation

struct TransactionMenuView: View {
    let transaction: Transaction
    let onEdit: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    let onApprove: (Transaction) -> Void
    let onViewDetails: (Transaction) -> Void

    var body: some View {
        Button {
            onEdit(transaction)
        } label: {
            Image(systemName: "ellipsis")
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ערוך עסקה")
    }
}
