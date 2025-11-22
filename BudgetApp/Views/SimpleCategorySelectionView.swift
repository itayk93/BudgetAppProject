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
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .trailing, spacing: 16) {
                // Transaction info
                VStack(alignment: .trailing, spacing: 8) {
                    Text(transaction.business_name ?? "עסקה ללא שם")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    Text("בחר קטגוריה לעסקה זו:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(10)

                // Search field for categories
                VStack(alignment: .trailing, spacing: 8) {
                    Text("חיפוש קטגוריה:")
                        .font(.subheadline)
                        .foregroundColor(.purple)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    TextField("חפש קטגוריה...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 8)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.purple.opacity(0.7), lineWidth: 2)
                        )
                }

                // Category selection - only show matching categories when user types
                VStack(alignment: .trailing, spacing: 8) {
                    Text("קטגוריה:")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if searchText.isEmpty {
                        // Show message when no search text
                        Text("הזן טקסט לחיפוש קטגוריות...")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        // Filter categories based on search text
                        let filteredCategories = categories.filter { category in
                            category.name.localizedCaseInsensitiveContains(searchText)
                        }

                        if filteredCategories.isEmpty {
                            Text("לא נמצאו תוצאות")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding()
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(8)
                        } else {
                            ScrollView {
                                LazyVStack(alignment: .trailing, spacing: 8) {
                                    ForEach(filteredCategories, id: \.name) { category in
                                        Button(action: {
                                            selectedCategory = category.name
                                        }) {
                                            HStack {
                                                Text(category.name)
                                                    .foregroundColor(.primary)
                                                if selectedCategory == category.name {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.green)
                                                }
                                            }
                                            .padding()
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                            .background(selectedCategory == category.name ? Color.blue.opacity(0.2) : Color.clear)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(selectedCategory == category.name ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(maxHeight: 200)
                        }
                    }
                }

                // Note field
                VStack(alignment: .trailing, spacing: 8) {
                    Text("הערה (אופציונלי):")
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    TextField("הוסף הערה", text: $note)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green.opacity(0.7), lineWidth: 2)
                        )
                }

                Spacer()

                // Action buttons
                HStack(spacing: 12) {
                    Button("מחק עסקה") {
                        showConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)

                    Button("עדכן") {
                        if !selectedCategory.isEmpty {
                            onCategorySelected(selectedCategory, note.isEmpty ? nil : note)
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green) // Green tint for update button
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding()
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    // For RTL layout, using a custom view to ensure the title appears on the right
                    HStack {
                        Spacer()
                        Text("עריכת עסקה")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("סגור") {
                        dismiss()
                    }
                }
            }
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