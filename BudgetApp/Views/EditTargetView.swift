import SwiftUI

struct EditTargetView: View {
    let categoryName: String
    @Binding var target: Double?
    @State private var tempValue: String = ""
    
    let onSave: (Double) -> Void
    let onSuggest: () async -> Double
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection
    
    @State private var suggestedValue: Double?
    @State private var isLoadingSuggestion = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("קטגוריה") {
                    Text(categoryName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Section("יעד חודשי") {
                    HStack {
                        TextField("סכום", text: $tempValue)
                            .multilineTextAlignment(.leading) // In RTL, leading is Right
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                        Text("₪")
                            .foregroundColor(.secondary)
                    }
                }
                
                if let suggestedValue = suggestedValue {
                    Section {
                        Button {
                            tempValue = String(format: "%.0f", suggestedValue)
                        } label: {
                            HStack {
                                Text("יעד מוצע: \(formatNumber(suggestedValue)) ₪")
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("החל")
                                    .foregroundColor(.blue)
                            }
                        }
                    } header: {
                        Text("הצעה")
                    } footer: {
                        Text("מבוסס על ממוצע הוצאות ב-3 החודשים האחרונים")
                    }
                }
                
                Section {
                    Button(action: {
                        Task {
                            isLoadingSuggestion = true
                            let value = await onSuggest()
                            suggestedValue = value
                            isLoadingSuggestion = false
                        }
                    }) {
                        if isLoadingSuggestion {
                            ProgressView()
                        } else {
                            Text("בדוק הצעה ליעד")
                        }
                    }
                    .disabled(isLoadingSuggestion)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .environment(\.layoutDirection, .rightToLeft) // Enforce RTL for the form
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
                        save()
                    }
                    .disabled(tempValue.isEmpty || Double(tempValue) == nil)
                    .fontWeight(.bold)
                }
#else
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("שמור") {
                        save()
                    }
                    .disabled(tempValue.isEmpty || Double(tempValue) == nil)
                }
#endif
            }
            .onAppear {
                if let target = target {
                    tempValue = String(format: "%.0f", target)
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft) // Enforce RTL for the stack
    }
    
    private func save() {
        if let value = Double(tempValue) {
            onSave(value)
            dismiss()
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