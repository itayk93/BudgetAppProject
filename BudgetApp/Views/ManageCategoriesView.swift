import SwiftUI

private enum StatusType {
    case info, success, error

    var backgroundColor: Color {
        switch self {
        case .info:
            return Color.blue.opacity(0.1)
        case .success:
            return Color.green.opacity(0.15)
        case .error:
            return Color.red.opacity(0.15)
        }
    }

    var borderColor: Color {
        switch self {
        case .info:
            return Color.blue.opacity(0.6)
        case .success:
            return Color.green.opacity(0.7)
        case .error:
            return Color.red.opacity(0.7)
        }
    }
}

private struct StatusMessage {
    let text: String
    let type: StatusType
}

struct ManageCategoriesView: View {
    @EnvironmentObject private var vm: CashFlowDashboardViewModel

    @State private var categoryOrders: [CategoryOrder] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var rowSavingIds: Set<String> = []
    @State private var isSavingOrder = false
    @State private var lastSaved: Date?
    @State private var saveTask: Task<Void, Never>?
    @State private var statusMessage: StatusMessage?
    @State private var editMode: EditMode = .inactive
    @State private var positionSheetCategory: CategoryOrder?
    @State private var positionInput: String = ""
    @State private var sharedCategorySheetContext: SharedCategorySheetContext?
    @State private var sharedCategoryInput: String = ""

    private let saveDelay: TimeInterval = 0.8

    private var categoryOrderService: CategoryOrderService {
        CategoryOrderService(apiClient: vm.apiClient)
    }

    private var uniqueSharedCategories: [String] {
        Array(Set(categoryOrders.compactMap {
            $0.sharedCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        }))
        .filter { !$0.isEmpty }
        .sorted()
    }

    private var transactionCounts: [String: Int] {
        Dictionary(grouping: vm.transactions, by: { $0.effectiveCategoryName })
            .mapValues { $0.count }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "he_IL")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    statusBar

                    if isLoading {
                        ProgressView("טוען קטגוריות...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(UIColor.systemGroupedBackground))
                    } else if let error = error {
                        errorView(error)
                    } else {
                        content
                    }
                }

                if let banner = statusMessage {
                    statusBanner(for: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle("ניהול קטגוריות")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .environment(\.editMode, $editMode)
            .onAppear(perform: loadCategoryOrders)
            .onDisappear {
                saveTask?.cancel()
            }
            .sheet(isPresented: Binding(
                get: { positionSheetCategory != nil },
                set: { if !$0 { positionSheetCategory = nil } }
            )) {
                if let category = positionSheetCategory {
                    PositionPickerSheet(
                        title: category.categoryName,
                        maxPosition: categoryOrders.count,
                        selection: $positionInput,
                        onSave: { newPosition in
                            if let index = index(of: category) {
                                moveCategory(from: index, to: newPosition)
                            }
                            positionSheetCategory = nil
                        },
                        onCancel: {
                            positionSheetCategory = nil
                        }
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { sharedCategorySheetContext != nil },
                set: { if !$0 { sharedCategorySheetContext = nil } }
            )) {
                if let context = sharedCategorySheetContext {
                    SharedCategoryInputSheet(
                        title: context.categoryName,
                        text: $sharedCategoryInput,
                        onSave: {
                            let trimmed = sharedCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            assignSharedCategory(trimmed.isEmpty ? nil : trimmed, toCategoryId: context.categoryId)
                            sharedCategorySheetContext = nil
                        },
                        onCancel: {
                            sharedCategorySheetContext = nil
                        }
                    )
                }
            }
        }
    }

    private var statusBar: some View {
        HStack {
            if isSavingOrder {
                ProgressView()
                Text("שומר...")
                    .font(.subheadline)
            } else if let lastSaved = lastSaved {
                Text("נשמר לאחרונה: \(Self.timeFormatter.string(from: lastSaved))")
                    .font(.subheadline)
            } else {
                Text("טרם נשמרו שינויים")
                    .font(.subheadline)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var content: some View {
        VStack(spacing: 12) {
            existingGroupsHeader

            if categoryOrders.isEmpty {
                emptyStateView
            } else {
                List {
                    Section(header: Text("קטגוריות").font(.headline)) {
                        ForEach(categoryOrders, id: \.stableId) { category in
                            categoryRow(for: category)
                        }
                        .onMove(perform: move(from:to:))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .padding(.top, 8)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var existingGroupsHeader: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("קטגוריות משותפות קיימות:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueSharedCategories, id: \.self) { shared in
                        Text(shared)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }

                    if uniqueSharedCategories.isEmpty {
                        Text("אין קטגוריות משותפות")
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func categoryRow(for category: CategoryOrder) -> some View {
        let currentIndex = index(of: category) ?? 0
        let transactionCount = transactionCounts[category.categoryName] ?? 0
        let weeklyEnabled = category.weeklyDisplay ?? false
        let isRowSaving = rowSavingIds.contains(category.stableId)

        return VStack(alignment: .trailing, spacing: 10) {
            HStack {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(category.categoryName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("מיקום: #\(currentIndex + 1)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let shared = category.sharedCategory, !shared.isEmpty {
                    Text("🏷️ \(shared)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }

            HStack {
                Text("\(transactionCount) עסקאות")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if isRowSaving {
                    ProgressView()
                        .scaleEffect(0.7, anchor: .center)
                }
            }

            sharedCategoryMenu(for: category)

            Toggle(isOn: Binding(
                get: { weeklyEnabled },
                set: { newValue in
                    toggleWeeklyDisplay(for: category, enabled: newValue)
                }
            )) {
                Text("תצוגה שבועית")
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .disabled(isRowSaving)
            .toggleStyle(.switch)

            reorderButtons(for: category, currentIndex: currentIndex)
        }
        .padding(.vertical, 8)
    }

    private func sharedCategoryMenu(for category: CategoryOrder) -> some View {
        Menu {
            Button("ללא קטגוריה משותפת") {
                assignSharedCategory(nil, toCategoryId: category.id)
            }
            Divider()
            ForEach(uniqueSharedCategories, id: \.self) { shared in
                Button(shared) {
                    assignSharedCategory(shared, toCategoryId: category.id)
                }
            }
            Divider()
            Button("➕ הוסף חדש") {
                guard let id = category.id else {
                    showStatusMessage("ללא מזהה לקטגוריה זו", type: .error)
                    return
                }
                sharedCategoryInput = ""
                sharedCategorySheetContext = SharedCategorySheetContext(
                    categoryId: id,
                    categoryName: category.categoryName
                )
            }
        } label: {
            Label {
                Text(category.sharedCategory ?? "בחר קטגוריה משותפת")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func reorderButtons(for category: CategoryOrder, currentIndex: Int) -> some View {
        HStack(spacing: 10) {
            moveButton(label: "⬆️⬆️", disabled: currentIndex == 0) {
                moveCategory(from: currentIndex, to: 0)
            }
            moveButton(label: "⬆️", disabled: currentIndex == 0) {
                moveCategory(from: currentIndex, to: max(0, currentIndex - 1))
            }
            moveButton(label: "⬇️", disabled: currentIndex >= categoryOrders.count - 1) {
                moveCategory(from: currentIndex, to: min(categoryOrders.count - 1, currentIndex + 1))
            }
            moveButton(label: "⬇️⬇️", disabled: currentIndex >= categoryOrders.count - 1) {
                moveCategory(from: currentIndex, to: categoryOrders.count - 1)
            }
            moveButton(label: "📍") {
                positionInput = "\(currentIndex + 1)"
                positionSheetCategory = category
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func moveButton(label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(disabled ? Color.gray.opacity(0.2) : Color.accentColor.opacity(0.1))
                .foregroundColor(disabled ? .gray : .primary)
                .clipShape(Circle())
        }
        .disabled(disabled)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Text("שגיאה")
                .font(.title2)
                .bold()
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
            Button("נסה שוב") {
                loadCategoryOrders()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Text("📋")
                .font(.system(size: 60))
                .opacity(0.6)
            Text("אין קטגוריות")
                .font(.title3)
                .fontWeight(.semibold)
            Text("נראה שאין לך קטגוריות להציג כרגע.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadCategoryOrders() {
        isLoading = true
        error = nil
        Task {
            do {
                let orders = try await categoryOrderService.getCategoryOrders()
                let sorted = orders.sorted {
                    ($0.displayOrder ?? Int.max) < ($1.displayOrder ?? Int.max)
                }
                categoryOrders = sorted
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }

    private func scheduleOrderSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(saveDelay * 1_000_000_000))
            await persistOrder()
        }
    }

    @MainActor
    private func persistOrder() async {
        guard !Task.isCancelled else { return }
        isSavingOrder = true
        defer { isSavingOrder = false }
        do {
            try await categoryOrderService.reorderCategories(orderData: categoryOrders)
            lastSaved = Date()
            showStatusMessage("הסדר נשמר בהצלחה", type: .success)
            await vm.refreshCategoryOrders()
            await vm.refreshData()
        } catch {
            showStatusMessage("שגיאה בשמירת הסדר: \(error.localizedDescription)", type: .error)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var updated = categoryOrders
        updated.move(fromOffsets: source, toOffset: destination)
        reorderAndScheduleSave(with: updated)
    }

    private func moveCategory(from: Int, to: Int) {
        guard from != to, categoryOrders.indices.contains(from), categoryOrders.indices.contains(to) else { return }
        var updated = categoryOrders
        let item = updated.remove(at: from)
        updated.insert(item, at: to)
        reorderAndScheduleSave(with: updated)
    }

    private func reorderAndScheduleSave(with updated: [CategoryOrder]) {
        categoryOrders = updated.enumerated().map { index, original in
            CategoryOrder(
                id: original.id,
                categoryName: original.categoryName,
                displayOrder: index,
                weeklyDisplay: original.weeklyDisplay,
                monthlyTarget: original.monthlyTarget,
                sharedCategory: original.sharedCategory,
                useSharedTarget: original.useSharedTarget
            )
        }
        scheduleOrderSave()
    }

    private func index(of category: CategoryOrder) -> Int? {
        categoryOrders.firstIndex { $0.stableId == category.stableId }
    }

    private func assignSharedCategory(_ sharedCategory: String?, toCategoryId categoryId: String?) {
        guard let categoryId = categoryId else {
            showStatusMessage("ללא מזהה לקטגוריה זו", type: .error)
            return
        }
        addRowSavingState(for: categoryId, saving: true)
        Task {
            do {
                try await categoryOrderService.updateSharedCategory(
                    categoryId: categoryId,
                    sharedCategoryName: sharedCategory
                )
                if let stableId = categoryOrders.first(where: { $0.id == categoryId })?.stableId {
                    updateRow(stableId: stableId) { current in
                        CategoryOrder(
                            id: current.id,
                            categoryName: current.categoryName,
                            displayOrder: current.displayOrder,
                            weeklyDisplay: current.weeklyDisplay,
                            monthlyTarget: current.monthlyTarget,
                            sharedCategory: sharedCategory,
                            useSharedTarget: current.useSharedTarget
                        )
                    }
                }
                showStatusMessage("קטגוריה משותפת עודכנה", type: .success)
                await vm.refreshCategoryOrders()
                await vm.refreshData()
            } catch {
                showStatusMessage("שגיאה בעדכון קטגוריה משותפת", type: .error)
            }
            addRowSavingState(for: categoryId, saving: false)
        }
    }

    private func toggleWeeklyDisplay(for category: CategoryOrder, enabled: Bool) {
        guard let categoryId = category.id else {
            showStatusMessage("ללא מזהה לקטגוריה זו", type: .error)
            return
        }
        addRowSavingState(for: categoryId, saving: true)
        Task {
            do {
                try await categoryOrderService.updateWeeklyDisplay(
                    categoryId: categoryId,
                    showInWeeklyView: enabled
                )
                updateRow(stableId: category.stableId) { current in
                    CategoryOrder(
                        id: current.id,
                        categoryName: current.categoryName,
                        displayOrder: current.displayOrder,
                        weeklyDisplay: enabled,
                        monthlyTarget: current.monthlyTarget,
                        sharedCategory: current.sharedCategory,
                        useSharedTarget: current.useSharedTarget
                    )
                }
                showStatusMessage(enabled ? "תצוגה שבועית הופעלה" : "תצוגה שבועית בוטלה", type: .success)
                await vm.refreshCategoryOrders()
                await vm.refreshData()
            } catch {
                showStatusMessage("שגיאה בעדכון תצוגה שבועית", type: .error)
            }
            addRowSavingState(for: categoryId, saving: false)
        }
    }

    private func addRowSavingState(for stableId: String, saving: Bool) {
        if saving {
            rowSavingIds.insert(stableId)
        } else {
            rowSavingIds.remove(stableId)
        }
    }

    private func updateRow(stableId: String, transformer: (CategoryOrder) -> CategoryOrder) {
        guard let index = categoryOrders.firstIndex(where: { $0.stableId == stableId }) else { return }
        categoryOrders[index] = transformer(categoryOrders[index])
    }

    private func showStatusMessage(_ text: String, type: StatusType) {
        let newMessage = StatusMessage(text: text, type: type)
        statusMessage = newMessage
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if statusMessage?.text == newMessage.text {
                statusMessage = nil
            }
        }
    }

    private func statusBanner(for message: StatusMessage) -> some View {
        HStack {
            Text(message.text)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding()
        .background(message.type.backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(message.type.borderColor, lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

private struct SharedCategorySheetContext {
    let categoryId: String
    let categoryName: String
}

private struct PositionPickerSheet: View {
    let title: String
    let maxPosition: Int
    @Binding var selection: String
    let onSave: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("הזינו מיקום חדש")) {
                    TextField("1-\(maxPosition)", text: $selection)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ביטול", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("שמור") {
                        guard
                            let value = Int(selection),
                            value >= 1,
                            value <= maxPosition
                        else { return }
                        onSave(value - 1)
                    }
                }
            }
        }
    }
}

private struct SharedCategoryInputSheet: View {
    let title: String
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("שם הקבוצה המשותפת")) {
                    TextField("שם חדש", text: $text)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("ביטול", action: onCancel)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("שמור", action: onSave)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
