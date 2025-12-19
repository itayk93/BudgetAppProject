import SwiftUI

struct EditBudgetView: View {
    let categoryName: String
    let monthName: String
    @Binding var budget: Double?
    @State private var tempValue: String = ""
    
    let onSave: (Double?) -> Void
    let onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("קטגוריה") {
                    Text(categoryName)
                }
                
                Section("חודש") {
                    Text(monthName)
                }
                
                Section("תקציב") {
                    HStack {
                        Text("₪")
                            .foregroundColor(.secondary)
                        TextField("סכום", text: $tempValue)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                    }
                }
            }
            .navigationTitle("הגדר תקציב")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ביטול") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("מחק תקציב", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("מחק תקציב", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
#endif
            }
            .onAppear {
                if let budget = budget {
                    tempValue = String(budget)
                }
            }
#if swift(>=5.9)
            // iOS 17+ syntax for onChange - get both old and new values
            .onChange(of: tempValue) { oldValue, newValue in
                // When the user enters a value, call onSave with the new value
                if let value = Double(newValue), !newValue.isEmpty {
                    onSave(value)
                } else if newValue.isEmpty {
                    onSave(nil)
                }
            }
#else
            // Pre-iOS 17 syntax
            .onChange(of: tempValue) { newValue in
                // When the user enters a value, call onSave with the new value
                if let value = Double(newValue), !newValue.isEmpty {
                    onSave(value)
                } else if newValue.isEmpty {
                    onSave(nil)
                }
            }
#endif
        }
    }
}