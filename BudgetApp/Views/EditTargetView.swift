import SwiftUI

struct EditTargetView: View {
    let categoryName: String
    @Binding var target: Double?
    @State private var tempValue: String = ""
    
    let onSave: (Double) -> Void
    let onSuggest: () async -> Double
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var suggestedValue: Double?
    @State private var isLoadingSuggestion = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("קטגוריה") {
                    Text(categoryName)
                }
                
                Section("יעד חודשי") {
                    HStack {
                        TextField("סכום", text: $tempValue)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                        Text("₪")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let suggestedValue = suggestedValue {
                    Section("הצעה") {
                        HStack {
                            Text("ingly suggested")
                            Spacer()
                            Text(formatNumber(suggestedValue))
                                .foregroundColor(.blue)
                            Text("₪")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button("קבל הצעה") {
                        Task {
                            isLoadingSuggestion = true
                            suggestedValue = await onSuggest()
                            isLoadingSuggestion = false
                        }
                    }
                    .disabled(isLoadingSuggestion)
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("עדכן יעד")
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
                    Button("שמור") {
                        if let value = Double(tempValue) {
                            onSave(value)
                            dismiss()
                        }
                    }
                    .disabled(tempValue.isEmpty || Double(tempValue) == nil)
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("שמור") {
                        if let value = Double(tempValue) {
                            onSave(value)
                            dismiss()
                        }
                    }
                    .disabled(tempValue.isEmpty || Double(tempValue) == nil)
                }
#endif
            }
            .onAppear {
                if let target = target {
                    tempValue = String(target)
                }
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}