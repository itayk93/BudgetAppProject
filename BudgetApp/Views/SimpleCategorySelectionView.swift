import SwiftUI

struct SimpleCategorySelectionView: View {
    let transaction: Transaction
    let categories: [TransactionCategory]
    var onCategorySelected: (String, String?) -> Void
    var onDelete: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: String = ""
    @State private var note: String = ""
    @State private var showConfirmation = false
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .trailing, spacing: 16) {
                // Transaction info
                VStack(alignment: .trailing, spacing: 8) {
                    Text(transaction.business_name ?? "עסקה ללא שם")
                        .font(.headline)
                    Text("בחר קטגוריה לעסקה זו:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                
                // Category selection
                VStack(alignment: .trailing, spacing: 8) {
                    Text("קטגוריה:")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    Picker("בחר קטגוריה", selection: $selectedCategory) {
                        ForEach(categories, id: \.name) { category in
                            Text(category.name).tag(category.name)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                // Note field
                VStack(alignment: .trailing, spacing: 8) {
                    Text("הערה (אופציונלי):")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    
                    TextField("הוסף הערה", text: $note)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 12) {
                    Button("מחק עסקה") {
                        showConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    
                    Button("עדכן") {
                        if !selectedCategory.isEmpty {
                            onCategorySelected(selectedCategory, note.isEmpty ? nil : note)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .navigationTitle("עריכת עסקה")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("סגור") {
                    dismiss()
                }
            )
#else
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("סגור") {
                        dismiss()
                    }
                }
            }
#endif
            .onAppear {
                // Set a default category if available
                if !categories.isEmpty && selectedCategory.isEmpty {
                    selectedCategory = categories[0].name
                }
            }
        }
        .alert("למחוק עסקה?", isPresented: $showConfirmation) {
            Button("מחק", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("בטל", role: .cancel) { }
        } message: {
            Text("האם אתה בטוח שברצונך למחוק עסקה זו?")
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
