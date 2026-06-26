//
//  TabbarView.swift
//  feather
//
//  Created by samara on 23.03.2025.
//
import SwiftUI

struct TabbarView: View {
    // @ObservedObject (not @StateObject) so we share DownloadButtonView's instance
    @ObservedObject private var tabSelection = TabSelectionObserver.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    @ObservedObject private var _tweakManager = TweakManager.shared
    @ObservedObject private var _tabPrefs = TabBarPreferences.shared
    @AppStorage("Feather.showSourcesUpdateBadge") private var _showSourcesUpdateBadge: Bool = true

    private var _visibleDefaultTabs: [TabEnum] {
        _tabPrefs.visibleTabs
    }

    private var tabSelectionBinding: Binding<TabEnum> {
        Binding(
            get: { _visibleDefaultTabs.contains(tabSelection.selectedTab) ? tabSelection.selectedTab : .library },
            set: { newValue in
                if newValue == tabSelection.selectedTab && newValue == .sources {
                    tabSelection.sourcesRetapped.toggle()
                }
                tabSelection.selectedTab = newValue
            }
        )
    }

    private func _badge(for tab: TabEnum) -> Int {
        if tab == .sources && _showSourcesUpdateBadge { return updateChecker.updateCount }
        if tab == .tweaks { return _tweakManager.defaultInjectCount }
        return 0
    }

    var body: some View {
        TabView(selection: tabSelectionBinding) {
            ForEach(_visibleDefaultTabs, id: \.self) { tab in
                TabEnum.view(for: tab)
                    .environmentObject(tabSelection)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .badge(_badge(for: tab))
                    .tag(tab)
            }
        }
    }
}
