import SwiftUI
import Foundation

struct TransactionMenuView: View {
    let transaction: Transaction
    let onEdit: (Transaction) -> Void
    let onDelete: (Transaction) -> Void
    let onApprove: (Transaction) -> Void
    let onViewDetails: (Transaction) -> Void

    var body: some View {
        Menu {
            Button("פרטים") {
                onViewDetails(transaction)
            }
            Button("לערוך") {
                onEdit(transaction)
            }
            Button("למחוק") {
                onDelete(transaction)
            }
            if transaction.status == "pending" {
                Button("לאשר") {
                    onApprove(transaction)
                }
            }
        } label: {
            Image(systemName: "ellipsis").foregroundColor(.secondary).frame(width: 30)
        }
    }
}