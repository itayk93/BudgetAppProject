//
//  BudgetAppApp.swift
//  BudgetApp
//
//  Created by itay karkason on 19/10/2025.
//

import SwiftUI

@main
struct BudgetAppApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(appState.cashFlowDashboardVM)
                .environmentObject(appState.pendingTransactionsVM)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
