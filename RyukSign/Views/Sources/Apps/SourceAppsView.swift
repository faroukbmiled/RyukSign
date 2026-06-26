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
    }
}

// MARK: - View
struct SourceAppsView: View {
    @AppStorage("Feather.sortOptionRawValue") private var _sortOptionRawValue: String = SortOption.date.rawValue
    @AppStorage("Feather.sortAscending") private var _sortAscending: Bool = true
    @AppStorage("Feather.sourcesShowUpdatesAsTab") private var _sourcesShowUpdatesAsTab: Bool = false

    @State private var _sortOption: SortOption = .default
    @State private var _selectedRoute: SourceAppRoute?
    @State private var _scrollToAppId: String?

    @State var isLoading = true
    @State var hasLoadedOnce = false
    @State private var _searchText = ""
    @State private var _uiReadyForNavigation = false
    @State private var _isProcessingNavigation = false
    @State private var _lastProcessedNavigationId: String?
    @State private var showUpdatesOnly = false
    @State private var _selectedTab: SourceTab = .all
    @State private var _forceUpdateTrigger: Int = 0

    enum SourceTab {
        case all
        case updates
    }
    
    @ObservedObject var appNavigationManager = AppNavigationManager.shared
    @ObservedObject private var updateChecker = AppUpdateChecker.shared
    
    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: []
    ) private var signedApps: FetchedResults<Signed>
    
    @FetchRequest(
        entity: Imported.entity(),
        sortDescriptors: []
    ) private var importedApps: FetchedResults<Imported>

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
    @State private var _localUpdateCount: Int = 0
    // Bumped only on a real repository reload — lets the table detect a data change in O(1) instead of deep-comparing [ASRepository].
    @State private var _sourcesVersion: Int = 0
    var onRefresh: (() async -> Void)?
    
    /// True once a non-empty list is loaded — gates the search bar above skeleton/empty.
    private var _hasLoadedContent: Bool {
        if let sources = _sources, !sources.isEmpty { return true }
        return false
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            if let sources = _sources, !sources.isEmpty {
                tableView(for: sources)
                    .ignoresSafeArea(.container, edges: [.top, .bottom])
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
        }
        .navigationTitle(_navigationTitle)
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
                    Section(.localized("Sort by")) {
                        ForEach(SortOption.allCases, id: \.displayName) { option in
                            _sortButton(for: option)
                        }
                    }

                    if _localUpdateCount > 0 && !_sourcesShowUpdatesAsTab {
                        Divider()

                        Button {
                            showUpdatesOnly.toggle()
                        } label: {
                            HStack {
                                Text(.localized("Updates Only"))
                                Spacer()
                                if showUpdatesOnly {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")

                        if _localUpdateCount > 0 && !_sourcesShowUpdatesAsTab {
                            Text("\(_localUpdateCount)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                }
            }
        }
        .onAppear(perform: handleOnAppear)
        .onReceive(NotificationCenter.default.publisher(for: .skippedUpdatesChanged)) { _ in
            // An app was ignored/resumed — recompute update counts and refresh the list.
            Task { @MainActor in
                await refreshUpdateCountIfNeeded()
                _forceUpdateTrigger += 1
            }
        }
        .onChange(of: viewModel.isFinished, perform: handleViewModelFinished)
        .onChange(of: _sortOption, perform: handleSortOptionChange)
        .onChange(of: appNavigationManager.pendingAppNavigation, perform: handlePendingNavigation)
        .onChange(of: _sources, perform: handleSourcesChange)
        .onChange(of: _uiReadyForNavigation, perform: handleUIReadyChange)
        .onChange(of: signedApps.count) { _ in
            Task { @MainActor in
                await refreshUpdateCountIfNeeded()
            }
        }
        .onChange(of: importedApps.count) { _ in
            Task { @MainActor in
                await refreshUpdateCountIfNeeded()
            }
        }
        .onChange(of: updateChecker.updateCount) { newCount in
            if let sources = _sources {
                _localUpdateCount = calculateLocalUpdateCount(for: sources)
            }
        }
        .onChange(of: _localUpdateCount) { newCount in
            if newCount == 0 {
                if showUpdatesOnly {
                    showUpdatesOnly = false
                }
                if _selectedTab == .updates {
                    _selectedTab = .all
                }
            }
        }
        .onChange(of: _selectedTab) { newTab in
            _forceUpdateTrigger += 1
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
    }
    
    // MARK: - View Builders
    
    @ViewBuilder
    private func tableView(for sources: [ASRepository]) -> some View {
        let effectiveShowUpdatesOnly = _sourcesShowUpdatesAsTab ? (_selectedTab == .updates) : showUpdatesOnly

        SourceAppsTableRepresentableView(
            sources: sources,
            sourcesVersion: _sourcesVersion,
            searchText: $_searchText,
            sortOption: $_sortOption,
            sortAscending: $_sortAscending,
            scrollToAppId: $_scrollToAppId,
            signedApps: signedApps,
            importedApps: importedApps,
            updateChecker: updateChecker,
            showUpdatesOnly: effectiveShowUpdatesOnly,
            showTabBar: _sourcesShowUpdatesAsTab && _localUpdateCount > 0,
            selectedTab: $_selectedTab,
            localUpdateCount: _localUpdateCount,
            forceUpdateTrigger: _forceUpdateTrigger,
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
        if !hasLoadedOnce, viewModel.isFinished {
            _load()
            hasLoadedOnce = true
        }
        _sortOption = SortOption(rawValue: _sortOptionRawValue) ?? .default

        if _sources != nil {
            // Force a UI refresh so tab/filter state is correct on appear.
            _forceUpdateTrigger += 1

            Task { @MainActor in
                await refreshUpdateCountIfNeeded()
            }
        }
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

        Task { @MainActor in
            await refreshUpdateCountIfNeeded()
        }

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
    
    @MainActor
    private func refreshUpdateCountIfNeeded() async {
        guard let sources = _sources else { return }

        await updateChecker.precomputeAllUpdates(
            sources: sources,
            signedApps: signedApps,
            importedApps: importedApps
        )

        // Tab switching is handled by onChange(of: _localUpdateCount).
        _localUpdateCount = calculateLocalUpdateCount(for: sources)
    }
    
    // MARK: - Navigation Handling
    
    private func handlePendingNavigation(_ pendingNavigation: AppNavigationManager.PendingAppNavigation?) {
        guard let navigation = pendingNavigation else { return }
        
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

            await updateChecker.precomputeAllUpdates(
                sources: loadedSources,
                signedApps: signedApps,
                importedApps: importedApps
            )

            // Reuse the count precomputeAllUpdates just computed instead of re-walking
            // every app on the main actor (that second pass was part of the freeze).
            _localUpdateCount = updateChecker.updateCount

            withAnimation(.easeIn(duration: 0.2)) {
                isLoading = false
            }
        }
    }

    // Calculate update count only for apps in current sources
    private func calculateLocalUpdateCount(for sources: [ASRepository]) -> Int {
        var uniqueAppsWithUpdates = Set<String>()

        for source in sources {
            for app in source.apps {
                if updateChecker.appsWithUpdates.contains(app.currentUniqueId) {
                    if let installedApp = updateChecker.findInstalledApp(
                        for: app,
                        signedApps: signedApps,
                        importedApps: importedApps
                    ) {
                        uniqueAppsWithUpdates.insert(installedApp.uuid)
                    }
                }
            }
        }

        return uniqueAppsWithUpdates.count
    }
    
    struct SourceAppRoute: Identifiable, Hashable {
        let source: ASRepository
        let app: ASRepository.App
        let id: String = UUID().uuidString
    }
}

// MARK: - Extension: View (Sort)
extension SourceAppsView {
    private func _sortButton(for option: SortOption) -> some View {
        Button {
            if _sortOption == option {
                _sortAscending.toggle()
            } else {
                _sortOption = option
                _sortAscending = true
            }
        } label: {
            HStack {
                Text(option.displayName)
                Spacer()
                if _sortOption == option {
                    Image(systemName: _sortAscending ? "chevron.up" : "chevron.down")
                }
            }
        }
    }
}

extension View {
    @ViewBuilder
    func navigationDestinationIfAvailable<Item: Identifiable & Hashable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        if #available(iOS 17, *) {
            self.navigationDestination(item: item, destination: destination)
        } else {
            self
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
