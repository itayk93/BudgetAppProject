import SwiftUI
import Charts

struct EditTargetView: View {
    let categoryName: String
    @Binding var target: Double?
    var isSharedTarget: Bool = false
    var sharedCategoryName: String? = nil

    let onSave: (Double) async -> Void
    let onSuggest: () async -> Double?
    var onFetchHistory: (() async -> [(month: String, total: Double)])? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var mode: EditMode = .manual
    
    // Manual Input
    @State private var manualInputValue: String = ""
    @State private var isOneTimeUpdate: Bool = false
    @FocusState private var isInputFocused: Bool
    
    // Auto Data
    @State private var history: [(month: String, total: Double)] = []
    @State private var suggestedValue: Double?
    @State private var isLoadingHistory = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let accentColor = Color.blue

    enum EditMode {
        case auto
        case manual
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Header
                    headerView
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            autoSuggestionCard
                            manualEntryCard
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer()
                    
                    // Fixed Bottom Button
                    updateButton
                        .padding(20)
                        .background(Color.white)
                }
            }
            .navigationBarHidden(true)
        }
        .environment(\.layoutDirection, .rightToLeft) // Enforce RTL environment
        .onAppear {
            setupInitialState()
        }
    }
    
    private func setupInitialState() {
        if let t = target {
            manualInputValue = formatNumber(t)
        }
        isLoadingHistory = true
        Task {
            if let fetcher = onFetchHistory {
                history = await fetcher()
            }
            suggestedValue = await onSuggest()
            isLoadingHistory = false
        }
    }

    // MARK: - Components

    private var headerView: some View {
        // RTL Logic:
        // Start = Right. End = Left.
        // We want X on Left (End). Title Center.
        HStack(alignment: .top) {
            Spacer() // Push X to left? No, this is Start(Right). 
            // Actually: HStack(A, B, C). A=Right, B=Center, C=Left.
            // We want: [Spacer] [Title] [Spacer] [X]
            // Wait, Spacer at Start pushes content Left.
            // Let's rely on Spacer weighting.
            
            Spacer()
            
            VStack(spacing: 4) {
                Text("כמה כסף צפוי לצאת על")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(categoryName + "?")
                    .font(.system(size: 22, weight: .bold))
                    .multilineTextAlignment(.center)
                if isSharedTarget, let shared = sharedCategoryName {
                     Text("(\(shared))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.black)
                    .padding(10)
            }
        }
        .padding(.horizontal)
    }

    private var autoSuggestionCard: some View {
        Button(action: { 
            withAnimation { mode = .auto }
        }) {
            VStack(spacing: 16) {
                // RTL Logic: Radio needs to be on Right (Start).
                HStack {
                    RadioButton(isSelected: mode == .auto) // First = Right
                    Text("צפי אוטומטי לפי העבר")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(mode == .auto ? .black : .secondary)
                    Spacer()
                }
                
                if isLoadingHistory {
                    ProgressView()
                        .padding(.vertical, 20)
                } else if let val = suggestedValue {
                    // Chart & Value
                    VStack(spacing: 10) {
                         // Value
                        Text("₪ \(formatNumber(val))")
                             .font(.system(size: 40, weight: .bold))
                             .foregroundColor(mode == .auto ? .black : .gray.opacity(0.6))
                        
                        // Chart
                        if !history.isEmpty {
                            Chart(history, id: \.month) { item in
                                BarMark(
                                    x: .value("Month", item.month),
                                    y: .value("Total", item.total)
                                )
                                .foregroundStyle(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                                .annotation(position: .top) {
                                    Text("\(Int(item.total))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(height: 120)
                            .chartXAxis {
                                AxisMarks(values: .automatic) { _ in
                                    AxisValueLabel()
                                }
                            }
                            .chartYAxis(.hidden)
                            // In RTL environment, Charts usually handle X-axis correctly (Right-to-Left time? No, usually time runs LTR or RTL depending on locale.
                            // Standard Hebrew charts often have Oldest on Right, Newest on Left?
                            // Or Old->New (Right->Left)?
                            // Let's assume Charts handles direction based on environment/locale.
                        }
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(mode == .auto ? accentColor : Color.gray.opacity(0.2), lineWidth: mode == .auto ? 2 : 1)
                    .background(Color.white)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var manualEntryCard: some View {
        Button(action: {
            withAnimation { 
                mode = .manual 
                isInputFocused = true
            }
        }) {
            VStack(spacing: 20) {
                // RTL: Radio on Right
                HStack {
                    RadioButton(isSelected: mode == .manual)
                    Text("צפי שלי")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(mode == .manual ? .black : .secondary)
                    Spacer()
                }
                
                // Input Field
                // RTL logic:
                // We want: [Number] [Symbol] (Visually Right aligned)
                // Text aligned to right.
                // HStack { TextField, Symbol } -> TextField(Right), Symbol(Left).
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", text: $manualInputValue)
                        .font(.system(size: 48, weight: .bold))
                        .multilineTextAlignment(.leading)
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                        .foregroundColor(mode == .manual ? .black : .gray)
                        .fixedSize(horizontal: true, vertical: false) // Prevent expansion to keep packed with symbol
                        .onChange(of: manualInputValue) { _ in
                            if mode != .manual { mode = .manual }
                        }
                    
                    Text("₪")
                        .font(.system(size: 40, weight: .bold)) // Increased size & bold
                        .foregroundColor(mode == .manual ? .blue : .gray)
                    
                    Spacer()
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                // Remaining Text - Right Aligned
                // "נשאר להוציא..."
                Text("נשאר להוציא 0.0 ₪")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity, alignment: .leading) // .leading = Right
                
                // Checkbox - Right Aligned
                // [Box] [Text] -> Box(Right), Text(Left)
                Button(action: { isOneTimeUpdate.toggle() }) {
                    HStack {
                        Image(systemName: isOneTimeUpdate ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(isOneTimeUpdate ? .blue : .gray)
                        
                        Text("שמור את הצפי הזה רק לחודש הנוכחי")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(mode == .manual ? accentColor : Color.gray.opacity(0.2), lineWidth: mode == .manual ? 2 : 1)
                    .background(Color.white)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var updateButton: some View {
        Button(action: runSave) {
            Text("עדכון")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(accentColor)
                .cornerRadius(12)
        }
        .disabled(isSaving)
    }
    
    // MARK: - Logic
    
    private func runSave() {
        let valueToSave: Double
        if mode == .auto {
            valueToSave = suggestedValue ?? 0
        } else {
            valueToSave = Double(manualInputValue) ?? 0
        }
        
        isSaving = true
        Task {
            await onSave(valueToSave)
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
    
    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ""
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}

struct RadioButton: View {
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
                .frame(width: 24, height: 24)
            
            if isSelected {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 14, height: 14)
            }
        }
    }
}
