import SwiftUI

struct CategorySelectionSheet: View {
    let transaction: Transaction
    let categories: [TransactionCategory]
    var onSelect: (String, String?) -> Void
    var onSelectForFuture: (String, String?) -> Void
    var onDelete: () -> Void
    var onHideBusiness: () -> Void

    @State private var searchText: String = ""
    @State private var selectedCategory: String?
    @State private var applyToAll = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var filteredCategories: [TransactionCategory] = []

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            HStack {
                Button("ביטול") { dismiss() }
                    .foregroundColor(.blue)
                Spacer()
                Text("החלפת קטגוריה").fontWeight(.semibold)
                Spacer()
                Button("ביטול") {}.opacity(0).disabled(true)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color(UIColor.systemGray3)), alignment: .bottom)

            // Content
            ScrollView {
                VStack(spacing: 24) {
                    Text(transaction.business_name ?? transaction.payment_method ?? "עסקה")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(16)

                    VStack(alignment: .trailing, spacing: 8) {
                        Text("חיפוש קטגוריה:")
                            .font(.subheadline.weight(.medium))
                        ZStack(alignment: .leading) {
                            TextField("חפש קטגוריה", text: $searchText)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .padding(.leading, 40) // Space for icon
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(14)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: searchText, perform: performSearch)
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                                .padding(.leading, 16)
                        }
                    }

                    if filteredCategories.isEmpty {
                        VStack {
                            Text(searchText.isEmpty ? "הזן טקסט לחיפוש קטגוריות..." : "לא נמצאו תוצאות")
                                .foregroundColor(.secondary)
                        }
                        .frame(minHeight: 200, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor.systemGray6))
                        )
                    } else {
                        LazyVStack(alignment: .trailing, spacing: 8) {
                            ForEach(filteredCategories) { category in
                                CategoryButtonView(
                                    category: category,
                                    isSelected: selectedCategory == category.name,
                                    onTap: { selectedCategory = category.name }
                                )
                            }
                        }
                        .padding(.top, 8)
                    }

                    VStack(spacing: 12) {
                        Button(action: {
                            guard let categoryName = selectedCategory else { return }
                            dismiss()
                            if applyToAll {
                                onSelectForFuture(categoryName, nil)
                            } else {
                                onSelect(categoryName, nil)
                            }
                        }) {
                            Text("אשר שינוי קטגוריה")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(selectedCategory != nil ? Color.accentColor : Color(UIColor.systemGray5))
                                .foregroundColor(selectedCategory != nil ? .white : Color(UIColor.systemGray))
                                .cornerRadius(14)
                        }
                        .disabled(selectedCategory == nil)
                        
                        Button(action: { applyToAll.toggle() }) {
                             HStack {
                                Text("החל על כל העסקאות העתידיות")
                                Spacer()
                                Image(systemName: applyToAll ? "checkmark.square.fill" : "square")
                                     .font(.body.weight(.semibold))
                                     .foregroundColor(applyToAll ? .accentColor : .secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.systemGray6))
                            .foregroundColor(.primary)
                            .cornerRadius(14)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        Button(role: .destructive, action: { dismiss(); onDelete() }) {
                            Text("מחק עסקה")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(14)
                        }

                        Button(action: { dismiss(); onHideBusiness() }) {
                            Text("הסר בית עסק")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(UIColor.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(14)
                        }
                    }
                }
                .padding()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if categories.count < 25 { filteredCategories = categories }
        }
    }
    
    private func performSearch(search: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                if !Task.isCancelled {
                    let lowercasedSearch = search.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if lowercasedSearch.isEmpty {
                        if categories.count < 25 { filteredCategories = categories }
                        else { filteredCategories = [] }
                    } else {
                        filteredCategories = categories.filter { $0.name.lowercased().contains(lowercasedSearch) }
                    }
                }
            }
        }
    }

    private struct CategoryButtonView: View {
        let category: TransactionCategory
        let isSelected: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack {
                    Text(category.name)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(isSelected ? Color.accentColor.opacity(0.1) : Color(UIColor.systemGray6))
                .cornerRadius(12)
                .foregroundColor(.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
