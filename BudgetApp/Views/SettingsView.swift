//
//  SettingsView.swift
//  BudgetApp
//
//  Created by Itay Karkason on 21/11/2025.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("dashboard.showWeeklyBudgetCard") private var showWeeklyBudgetCard = true
    @AppStorage("dashboard.showMonthlyTargetCard") private var showMonthlyTargetCard = true
    @AppStorage("dashboard.showMonthlyTrendCard") private var showMonthlyTrendCard = true

    var body: some View {
        Form {
            NavigationLink("ניהול קטגוריות") {
                ManageCategoriesView()
            }
            NavigationLink("עסקאות שנבחנות מחדש") {
                ReviewedTransactionsSearchView()
            }
            Section("תצוגת דשבורד") {
                Toggle("כמה נשאר להוציא השבוע", isOn: $showWeeklyBudgetCard)
                Toggle("היעד החודשי", isOn: $showMonthlyTargetCard)
                Toggle("מבט חודשי", isOn: $showMonthlyTrendCard)
            }
        }
        .navigationTitle("הגדרות")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView()
        }
    }
}
