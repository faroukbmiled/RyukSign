//
//  SourceAppsView.swift
//  RyukSign
//
//  Created by samara on 1.05.2025.
//

import SwiftUI
import Combine
import AltSourceKit
import NimbleViews
import UIKit
import CoreData
import OSLog

// MARK: - Extension: View (Enum)
extension SourceAppsView {
    enum SortOption: String, CaseIterable {
        case `default` = "default"
        case name
        case date
        
        var displayName: String {
            switch self {
            case .default:  .localized("Default")
            case .name:     .localized("Name")
            case .date:     .localized("Date")
            }
        }

        static let rawValueKey = "Feather.sortOptionRawValue"

        static var saved: Self {
            UserDefaults.standard.string(forKey: rawValueKey).flatMap(Self.init) ?? .date
        }

        var systemImage: String {
            switch self {
            case .default:  "list.bullet"
            case .name:     "textformat"
            case .date:     "calendar"
            }
        }
    }
}

// MARK: - View
struct SourceAppsView: View {
    static let sortAscendingKey = "Feather.sortAscending"

    @AppStorage(SortOption.rawValueKey) private var _sortOptionRawValue: String = SortOption.date.rawValue
    @AppStorage(sortAscendingKey) private var _sortAscending: Bool = true
    @AppStorage("Feather.sourcesTabShowAllReposDirectly") private var _showsAllReposDirectly = false
    @AppStorage("Feather.sourcesShowUpdatesAsTab") private var _sourcesShowUpdatesAsTab: Bool = false

    @State private var _sortOption: SortOption = .default
    @State private var _selectedRoute: SourceAppRoute?
    @State private var _updateRoute: UpdateRoute?
    @State private var _scrollToAppId: String?

    @State var isLoading = true
    @State var hasLoadedOnce = false
    @State private var _searchText = ""
    @State private var _uiReadyForNavigation = false
    @State private var _isProcessingNavigation = false
    @State private var _lastProcessedNavigationId: String?
    @State private var showUpdatesOnly = false
    @State private var _selectedTab: SourceTab = .all

    enum SourceTab {
        case all
        case updates
    }
    
    @ObservedObject var appNavigationManager = AppNavigationManager.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared

    private var _navigationTitle: String {
        if object.count == 1 {
            object[0].name ?? .localized("Unknown")
        } else {
            .localized("%lld Sources", arguments: object.count)
        }
    }
    
    let object: [AltSource]
    @ObservedObject var viewModel: SourcesViewModel
    @State private var _sources: [ASRepository]?
    // Bumped only on a real repository reload — lets the table detect a data change in O(1) instead of deep-comparing [ASRepository].
    @State private var _sourcesVersion: Int = 0
    var onRefresh: (() async -> Void)?
    var isSourcesRoot = false
    
    /// True once a non-empty list is loaded — gates the search bar above skeleton/empty.
    private var _hasLoadedContent: Bool {
        if let sources = _sources, !sources.isEmpty { return true }
        return false
    }

    private var _updates: [AppUpdate] {
        updateChecker.updates(in: Set(object.compactMap(\.identifier)))
    }

    private var _searchedUpdates: [AppUpdate] {
        _searchText.isEmpty ? _updates : _updates.filter { $0.name.localizedCaseInsensitiveContains(_searchText) }
    }

    private var _showsTabBar: Bool {
        _sourcesShowUpdatesAsTab && !_updates.isEmpty
    }

    private var _showsUpdates: Bool {
        !_updates.isEmpty && (_sourcesShowUpdatesAsTab ? _selectedTab == .updates : showUpdatesOnly)
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            if let sources = _sources, !sources.isEmpty {
                tableView(for: sources)
                    .ignoresSafeArea(.container, edges: _showsTabBar ? .bottom : [.top, .bottom])
                    .background(Color(.systemBackground))
            } else if _sources == nil || isLoading || !viewModel.isFinished {
                // Loading or a load in flight — show skeleton, never the empty/error
                // state, so the mid-load window can't flash "Couldn't load apps".
                NBSkeletonList()
                    .padding(.top, 16)
            } else {
                // Load finished and genuinely empty (e.g. premium auth rejected) — actionable empty state, not an infinite spinner.
                _emptyStateView
            }

            // Overlay keeps table state across switches.
            if _showsUpdates {
                SourceUpdatesView(updates: _searchedUpdates, sort: _sortOption, ascending: _sortAscending) { update in
                    _updateRoute = UpdateRoute(key: update.id, sourceIDs: Set(object.compactMap(\.identifier)))
                } onOpen: { candidate in
                    _selectedRoute = SourceAppRoute(source: candidate.repository, app: candidate.app)
                }
                .background(Color(.systemBackground))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: _showsUpdates)
        .safeAreaInset(edge: .top, spacing: 0) {
            if _showsTabBar {
                SourceTabBarView(selectedTab: _selectedTab, updateCount: _updates.count) { _selectedTab = $0 }
            }
        }
        .navigationTitle(_navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .legacyOpaqueNavigationBar()
        // Attach the search bar only once a real list exists, else it floats above skeleton/empty.
        .if(_hasLoadedContent) { $0.searchable(text: $_searchText, placement: .platform()) }
        .refreshable {
            if let refreshCallback = onRefresh {
                await refreshCallback()
            }
            _load()
        }
        .toolbarTitleMenu {
            toolbarMenuContent
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    _viewMenu
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                }
            }
        }
        .onAppear(perform: handleOnAppear)
        .onChange(of: viewModel.isFinished, perform: handleViewModelFinished)
        .onChange(of: _sortOption, perform: handleSortOptionChange)
        .onChange(of: appNavigationManager.pendingAppNavigation, perform: handlePendingNavigation)
        .onChange(of: _sources, perform: handleSourcesChange)
        .onChange(of: _uiReadyForNavigation, perform: handleUIReadyChange)
        .onChange(of: _updates.isEmpty) { isEmpty in
            if isEmpty {
                showUpdatesOnly = false
                _selectedTab = .all
            }
        }
        .onReceive(TabSelectionObserver.shared.$sourcesRetapped.dropFirst()) { _ in
            if _selectedTab != .all {
                _selectedTab = .all
            }
            if showUpdatesOnly {
                showUpdatesOnly = false
            }
        }
        .navigationDestinationIfAvailable(item: $_selectedRoute) { route in
            SourceAppsDetailView(source: route.source, app: route.app)
        }
        .navigationDestinationIfAvailable(item: $_updateRoute) { route in
            UpdatePickerView(route: route)
        }
    }

    @ViewBuilder
    private var _viewMenu: some View {
        SortPicker(selection: $_sortOption)

        if _sortOption != .default {
            SortOrderPicker(ascending: $_sortAscending)
        }

        Section {
            if !_updates.isEmpty && !_sourcesShowUpdatesAsTab {
                Toggle(isOn: $showUpdatesOnly) {
                    Label(.localized("Updates Only"), systemImage: "arrow.down.circle")
                }
            }
            if isSourcesRoot {
                Toggle(isOn: $_showsAllReposDirectly) {
                    Label(.localized("Show All Repos by Default"), systemImage: "square.stack")
                }
            }
        }
    }

    // MARK: - View Builders
    
    @ViewBuilder
    private func tableView(for sources: [ASRepository]) -> some View {
        SourceAppsTableRepresentableView(
            sources: sources,
            sourcesVersion: _sourcesVersion,
            searchText: $_searchText,
            sortOption: $_sortOption,
            sortAscending: $_sortAscending,
            scrollToAppId: $_scrollToAppId,
            onSelect: { route in
                _selectedRoute = route
            },
            onUIReady: {
                _uiReadyForNavigation = true
                handlePendingNavigationWhenReady()
            },
            onRefresh: onRefresh
        )
    }

    @ViewBuilder
    private var toolbarMenuContent: some View {
        if let sources = _sources, sources.count == 1 {
            if let url = sources[0].website {
                Button(.localized("Visit Website"), systemImage: "globe") {
                    UIApplication.open(url)
                }
            }

            if let url = sources[0].patreonURL {
                Button(.localized("Visit Patreon"), systemImage: "dollarsign.circle") {
                    UIApplication.open(url)
                }
            }
        }

        Divider()

        Button(.localized("Copy"), systemImage: "doc.on.doc") {
            guard !object.isEmpty else {
                UIAlertController.showAlertWithOk(
                    title: .localized("Error"),
                    message: .localized("No sources to copy")
                )
                return
            }
            UIPasteboard.general.string = object.map {
                $0.sourceURL!.absoluteString
            }.joined(separator: "\n")
            UIAlertController.showAlertWithOk(
                title: .localized("Success"),
                message: .localized("Sources copied to clipboard")
            )
        }
    }

    // MARK: - Event Handlers
    
    private func handleOnAppear() {
        if !hasLoadedOnce, viewModel.isFinished || object.contains(where: { viewModel.sources[$0] != nil }) {
            _load()
            hasLoadedOnce = true
        }
        _sortOption = SortOption(rawValue: _sortOptionRawValue) ?? .default
        _ = _openPendingDetail()
    }
    
    private func handleViewModelFinished(_ isFinished: Bool) {
        if isFinished {
            _load()
        }
    }
    
    private func handleSortOptionChange(_ newValue: SortOption) {
        _sortOptionRawValue = newValue.rawValue
    }
    
    private func handleSourcesChange(_ sources: [ASRepository]?) {
        guard sources != nil, !isLoading else { return }

        if appNavigationManager.pendingAppNavigation != nil && !_isProcessingNavigation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                handlePendingNavigationWhenReady()
            }
        }
    }
    
    private func handleUIReadyChange(_ isReady: Bool) {
        if isReady && appNavigationManager.pendingAppNavigation != nil && !_isProcessingNavigation {
            handlePendingNavigationWhenReady()
        }
    }
    
    // MARK: - Navigation Handling
    
    private func _openPendingDetail() -> Bool {
        guard let navigation = appNavigationManager.pendingAppNavigation, navigation.opensDetail else { return false }

        for source in object where navigation.sourceIdentifier.map({ $0 == source.identifier }) ?? true {
            guard
                let repository = viewModel.sources[source],
                let app = repository.apps.first(where: { $0.currentUniqueId == navigation.appId })
            else { continue }

            appNavigationManager.clearPendingNavigation()
            _selectedTab = .all
            showUpdatesOnly = false
            _selectedRoute = SourceAppRoute(source: repository, app: app)
            return true
        }
        return false
    }

    private func handlePendingNavigation(_ pendingNavigation: AppNavigationManager.PendingAppNavigation?) {
        guard let navigation = pendingNavigation, !_openPendingDetail() else { return }
        
        if _lastProcessedNavigationId == navigation.navigationId && _isProcessingNavigation {
            return
        }
        
        let shouldHandle: Bool
        if let sourceId = navigation.sourceIdentifier {
            shouldHandle = object.contains { $0.identifier == sourceId }
        } else {
            shouldHandle = object.count >= 1
        }
        
        if shouldHandle {
            _lastProcessedNavigationId = navigation.navigationId
            _isProcessingNavigation = true
            
            if _sources != nil && !isLoading && _uiReadyForNavigation {
                processNavigation(navigation)
            }
        } else {
            _isProcessingNavigation = false
        }
    }
    
    private func handlePendingNavigationWhenReady() {
        guard let navigation = appNavigationManager.pendingAppNavigation,
              !_isProcessingNavigation,
              _lastProcessedNavigationId != navigation.navigationId else {
            return
        }
        
        _lastProcessedNavigationId = navigation.navigationId
        _isProcessingNavigation = true
        processNavigation(navigation)
    }
    
    private func processNavigation(_ navigation: AppNavigationManager.PendingAppNavigation) {
        guard !_searchText.isEmpty || _scrollToAppId != navigation.appId else {
            _isProcessingNavigation = false
            return
        }
        
        _searchText = ""
        _scrollToAppId = navigation.appId
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self._isProcessingNavigation && self._scrollToAppId == navigation.appId {
                self._isProcessingNavigation = false
                AppNavigationManager.shared.clearPendingNavigation()
            }
        }
    }
    
    // MARK: - Empty / Error State

    @ViewBuilder
    private var _emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(.localized("Couldn't load apps"))
                .font(.headline)
            Text(.localized("The source returned no data. If this is a premium source, your access may have expired or failed to authenticate."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    if let refreshCallback = onRefresh {
                        await refreshCallback()
                    }
                    _load()
                }
            } label: {
                Text(.localized("Retry"))
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .padding(40)
    }

    // MARK: - Data Loading

    private func _load() {
        isLoading = true
        _uiReadyForNavigation = false

        Task { @MainActor in
            let loadedSources = object.compactMap { viewModel.sources[$0] }
            Logger.misc.info("SourceAppsView _load: \(loadedSources.count, privacy: .public)/\(object.count, privacy: .public) repositories available")
            _sources = loadedSources
            _sourcesVersion += 1

            withAnimation(.easeIn(duration: 0.2)) {
                isLoading = false
            }
        }
    }

    struct SourceAppRoute: Identifiable, Hashable {
        let source: ASRepository
        let app: ASRepository.App
        let id: String = UUID().uuidString
    }
}

extension View {
    @ViewBuilder
    func legacyOpaqueNavigationBar() -> some View {
        if #unavailable(iOS 26) {
            self.toolbarBackground(.visible, for: .navigationBar)
        } else {
            self
        }
    }

    @ViewBuilder
    func navigationDestinationIfAvailable<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 17, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self.navigationDestination(isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            )) {
                if let value = item.wrappedValue {
                    destination(value)
                }
            }
        }
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct SortPicker: View {
    @Binding var selection: SourceAppsView.SortOption

    var body: some View {
        Picker(.localized("Sort by"), selection: $selection) {
            ForEach(SourceAppsView.SortOption.allCases, id: \.self) { option in
                Label(option.displayName, systemImage: option.systemImage).tag(option)
            }
        }
    }
}

struct SortOrderPicker: View {
    @Binding var ascending: Bool

    var body: some View {
        Picker(.localized("Order"), selection: $ascending) {
            Label(.localized("Ascending"), systemImage: "arrow.up").tag(true)
            Label(.localized("Descending"), systemImage: "arrow.down").tag(false)
        }
    }
}
