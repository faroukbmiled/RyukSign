//
//  SourceTabBarView.swift
//  RyukSign
//
//  Extracted from SourceAppsTableRepresentableView.swift for maintainability.
//

import SwiftUI
import AltSourceKit
import CoreData

// MARK: - Tab Bar View
struct SourceTabBarView: View {
    let selectedTab: SourceAppsView.SourceTab
    let updateCount: Int
    let onTabSelected: (SourceAppsView.SourceTab) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { selectedTab },
            set: { onTabSelected($0) }
        )) {
            Text(.localized("All")).tag(SourceAppsView.SourceTab.all)
            Text(.localized("Updates") + " (\(updateCount))").tag(SourceAppsView.SourceTab.updates)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}
