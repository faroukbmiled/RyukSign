//
//  TabbarController.swift / ExtendedTabbarView.swift
//  feather
//
//  Created by samara on 5/17/24.
//  Copyright (c) 2024 Samara M (khcrysalis)
//
import SwiftUI
import NukeUI

@available(iOS 18, *)
struct ExtendedTabbarView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @AppStorage("Feather.tabCustomization") var customization = TabViewCustomization()
    @StateObject var viewModel = SourcesViewModel.shared

    @ObservedObject private var tabSelection = TabSelectionObserver.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    @ObservedObject private var _tweakManager = TweakManager.shared
    @ObservedObject private var _tabPrefs = TabBarPreferences.shared
    @AppStorage("Feather.showSourcesUpdateBadge") private var _showSourcesUpdateBadge: Bool = true

    private var _visibleDefaultTabs: [TabEnum] {
        _tabPrefs.visibleTabs
    }

    @State private var _isAddingPresenting = false

    @State private var selectedTab: TabSelection = .main(.library)
    
    @FetchRequest(
        entity: AltSource.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
        animation: .snappy
    ) private var _sources: FetchedResults<AltSource>

    enum TabSelection: Hashable {
        case main(TabEnum)
        case customizable(TabEnum)
        case allRepositories
        case source(String)
    }
        
    private var tabSelectionBinding: Binding<TabSelection> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == selectedTab, case .main(.sources) = newValue {
                    tabSelection.sourcesRetapped.toggle()
                }
                selectedTab = newValue
            }
        )
    }

    private func _badgeCount(for tab: TabEnum) -> Int {
        if tab == .sources && _showSourcesUpdateBadge { return updateChecker.updateCount }
        if tab == .tweaks { return _tweakManager.defaultInjectCount }
        return 0
    }

    var body: some View {
        TabView(selection: tabSelectionBinding) {
            ForEach(_visibleDefaultTabs, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: TabSelection.main(tab)) {
                    TabEnum.view(for: tab)
                }
                .badge(_badgeCount(for: tab))
            }

            ForEach(TabEnum.customizableTabs, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.icon, value: TabSelection.customizable(tab)) {
                    TabEnum.view(for: tab)
                }
                .customizationID("tab.\(tab.rawValue)")
                .defaultVisibility(.hidden, for: .tabBar)
                .customizationBehavior(.reorderable, for: .tabBar, .sidebar)
                .hidden(horizontalSizeClass == .compact)
            }

            TabSection("Sources") {
                Tab(.localized("All Repositories"), systemImage: "globe.desk", value: TabSelection.allRepositories) {
                    NavigationStack {
                        SourceAppsView(object: Array(_sources), viewModel: viewModel)
                    }
                }
                
                ForEach(_sources, id: \.identifier) { source in
                    Tab(value: TabSelection.source(source.identifier ?? "")) {
                        NavigationStack {
                            SourceAppsView(object: [source], viewModel: viewModel)
                        }
                    } label: {
                        _icon(source.name ?? .localized("Unknown"), iconUrl: source.iconURL)
                    }
                    .swipeActions {
                        Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
                            Storage.shared.deleteSource(for: source)
                        }
                    }
                }
            }
            .sectionActions {
                Button(.localized("Add Source"), systemImage: "plus") {
                    _isAddingPresenting = true
                }
            }
            .defaultVisibility(.hidden, for: .tabBar)
            .hidden(horizontalSizeClass == .compact)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($customization)
        .sheet(isPresented: $_isAddingPresenting) {
            SourcesAddView()
                .presentationDetents([.medium])
        }
        .onAppear {
            selectedTab = .main(tabSelection.selectedTab)
        }
        .onChange(of: _tabPrefs.hidden) { _, _ in
            if case .main(let tab) = selectedTab, !_visibleDefaultTabs.contains(tab) {
                selectedTab = .main(_tabPrefs.resolvedLaunchTab)
            }
        }
        .onChange(of: tabSelection.selectedTab) { _, newValue in
            // When TabSelectionObserver changes (from "Installed" button), update our selection
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = .main(newValue)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            // Update TabSelectionObserver when user manually changes tabs
            switch newValue {
            case .main(let tab):
                if tabSelection.selectedTab != tab {
                    tabSelection.selectedTab = tab
                }
            case .customizable(let tab):
                if tabSelection.selectedTab != tab {
                    tabSelection.selectedTab = tab
                }
            default:
                break // Don't update for source tabs
            }
        }
    }
    
    @ViewBuilder
    private func _icon(_ title: String, iconUrl: URL?) -> some View {
        Label {
            Text(title)
        } icon: {
            if let iconURL = iconUrl {
                LazyImage(url: iconURL) { state in
                    if let image = state.image {
                        image
                    } else {
                        standardIcon
                    }
                }
                .processors([.resize(width: 14), .circle()])
            } else {
                standardIcon
            }
        }
    }
    
    var standardIcon: some View {
        Image(systemName: "app.dashed")
    }
}
