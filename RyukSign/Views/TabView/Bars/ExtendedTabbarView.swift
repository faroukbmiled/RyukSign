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
            get: { _selectableTab },
            set: { newValue in
                if newValue == _selectableTab, case .main(.sources) = newValue {
                    tabSelection.sourcesRetapped.toggle()
                }
                selectedTab = newValue
            }
        )
    }

    // UIKit aborts when the selected tab is hidden.
    private var _selectableTab: TabSelection {
        guard horizontalSizeClass == .compact else { return selectedTab }

        let fallback: TabEnum
        switch selectedTab {
        case .main:
            return selectedTab
        case .customizable(let tab):
            fallback = tab
        case .allRepositories, .source:
            fallback = .sources
        }
        return .main(_visibleDefaultTabs.contains(fallback) ? fallback : _tabPrefs.resolvedLaunchTab)
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
                        if _sources.isEmpty {
                            NoRepositoriesView { _isAddingPresenting = true }
                                .navigationTitle(.localized("All Repositories"))
                        } else {
                            _sourceApps(Array(_sources))
                        }
                    }
                }
                
                ForEach(_sources, id: \.identifier) { source in
                    Tab(value: TabSelection.source(source.identifier ?? "")) {
                        NavigationStack {
                            _sourceApps([source])
                        }
                    } label: {
                        _icon(source.name ?? .localized("Unknown"), iconUrl: source.iconURL)
                    }
                    .swipeActions {
                        Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
                            Storage.shared.deleteSource(for: source)
                        }
                    }
                    // The Duo's tab rail renders repo icons as blank tinted circles.
                    .hidden(UIDevice.current.userInterfaceIdiom == .phone)
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
                .adaptiveSheetSizing(phone: [.medium])
        }
        .onAppear {
            selectedTab = _selection(for: tabSelection.selectedTab)
        }
        .onChange(of: _tabPrefs.hidden) { _, _ in
            if case .main(let tab) = selectedTab, !_visibleDefaultTabs.contains(tab) {
                selectedTab = .main(_tabPrefs.resolvedLaunchTab)
            }
        }
        .onChange(of: tabSelection.selectedTab) { _, newValue in
            guard _tab(of: selectedTab) != newValue else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedTab = _selection(for: newValue)
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if let tab = _tab(of: newValue), tabSelection.selectedTab != tab {
                tabSelection.selectedTab = tab
            }
        }
    }

    private func _tab(of selection: TabSelection) -> TabEnum? {
        switch selection {
        case .main(let tab), .customizable(let tab): tab
        case .allRepositories, .source: nil
        }
    }

    private func _selection(for tab: TabEnum) -> TabSelection {
        if _visibleDefaultTabs.contains(tab) { return .main(tab) }
        return TabEnum.customizableTabs.contains(tab) ? .customizable(tab) : .main(_tabPrefs.resolvedLaunchTab)
    }
    
    // The sidebar can open these before the Sources tab has loaded anything.
    private func _sourceApps(_ sources: [AltSource]) -> some View {
        SourceAppsView(
            object: sources,
            viewModel: viewModel,
            onRefresh: { await viewModel.fetchSources(_sources, refresh: true) }
        )
        .task { await viewModel.fetchSources(_sources) }
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
