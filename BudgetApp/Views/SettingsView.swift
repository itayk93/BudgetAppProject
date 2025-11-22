//
//  SettingsView.swift
//  BudgetApp
//
//  Created by Itay Karkason on 21/11/2025.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            NavigationLink("ניהול קטגוריות") {
                ManageCategoriesView()
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
