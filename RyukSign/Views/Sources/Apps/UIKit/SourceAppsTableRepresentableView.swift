//
//  SourceAppsTableView.swift
//  RyukSign
//
//  Created by samara on 3.05.2025.
//

import SwiftUI
import AltSourceKit
import CoreData

// MARK: - Representable
struct SourceAppsTableRepresentableView: UIViewRepresentable {
    let sources: [ASRepository]
    let sourcesVersion: Int
    @Binding var searchText: String
    @Binding var sortOption: SourceAppsView.SortOption
    @Binding var sortAscending: Bool
    @Binding var scrollToAppId: String?
    let signedApps: FetchedResults<Signed>
    let importedApps: FetchedResults<Imported>
    let updateChecker: AppUpdateChecker
    let showUpdatesOnly: Bool
    let showTabBar: Bool
    @Binding var selectedTab: SourceAppsView.SourceTab
    let localUpdateCount: Int
    let forceUpdateTrigger: Int
    let onSelect: (SourceAppsView.SourceAppRoute) -> Void
    let onUIReady: (() -> Void)?
    let onRefresh: (() async -> Void)?
    
    func makeUIView(context: Context) -> UITableView {
        let tableView = UITableView(frame: .zero, style: .plain)
        configureTableView(tableView, context: context)
        setupTableHeader(tableView, context: context)
        setupRefreshControl(tableView, context: context)
        animateTableView(tableView, context: context)
        return tableView
    }
    
    func configureTableView(_ tableView: UITableView, context: Context) {
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AppCell")
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: "SectionHeader")

        tableView.isPrefetchingEnabled = false
        tableView.estimatedRowHeight = 80
        tableView.rowHeight = UITableView.automaticDimension

        tableView.contentInsetAdjustmentBehavior = .automatic

        if #available(iOS 17, *) {
            tableView.allowsSelection = true
        } else {
            tableView.allowsSelection = false
        }
    }
    
    func setupTableHeader(_ tableView: UITableView, context: Context) {
        let hasNews = sources.count == 1 && sources.first?.news != nil && !(sources.first!.news!.isEmpty)

        guard showTabBar || hasNews else {
            tableView.tableHeaderView = nil
            context.coordinator.tabBarHostController = nil
            return
        }

        let container = UIView()
        container.backgroundColor = .clear
        var totalHeight: CGFloat = 0
        var currentY: CGFloat = 0

        if showTabBar {
            let tabBarView = SourceTabBarView(
                selectedTab: selectedTab,
                updateCount: localUpdateCount,
                onTabSelected: { tab in
                    self.selectedTab = tab
                }
            )
            let tabBarHost = UIHostingController(rootView: tabBarView)
            tabBarHost.view.translatesAutoresizingMaskIntoConstraints = false
            tabBarHost.view.backgroundColor = .clear

            container.addSubview(tabBarHost.view)

            let tabBarHeight: CGFloat = 44
            NSLayoutConstraint.activate([
                tabBarHost.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tabBarHost.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                tabBarHost.view.topAnchor.constraint(equalTo: container.topAnchor, constant: currentY),
                tabBarHost.view.heightAnchor.constraint(equalToConstant: tabBarHeight)
            ])

            currentY += tabBarHeight
            totalHeight += tabBarHeight

            context.coordinator.tabBarHostController = tabBarHost
        } else {
            context.coordinator.tabBarHostController = nil
        }

        if hasNews, let news = sources.first?.news {
            let newsView = SourceNewsView(news: news)
            let newsHost = UIHostingController(rootView: newsView)
            newsHost.view.translatesAutoresizingMaskIntoConstraints = false
            newsHost.view.backgroundColor = .clear

            container.addSubview(newsHost.view)

            let newsHeight: CGFloat = 161
            NSLayoutConstraint.activate([
                newsHost.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                newsHost.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                newsHost.view.topAnchor.constraint(equalTo: container.topAnchor, constant: currentY),
                newsHost.view.heightAnchor.constraint(equalToConstant: newsHeight)
            ])

            totalHeight += newsHeight
        }

        let width = tableView.bounds.width
        container.frame = CGRect(x: 0, y: 0, width: width, height: totalHeight)

        DispatchQueue.main.async {
            tableView.tableHeaderView = container
        }
    }
    
    func setupRefreshControl(_ tableView: UITableView, context: Context) {
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleRefresh(_:)),
            for: .valueChanged
        )
        tableView.refreshControl = refreshControl
        context.coordinator.refreshControl = refreshControl
    }
    
    func animateTableView(_ tableView: UITableView, context: Context) {
        tableView.alpha = 0
        
        UIView.transition(with: tableView, duration: 0.5, options: [.transitionCrossDissolve], animations: {
            tableView.alpha = 1
        }, completion: { _ in
            context.coordinator.onUIReady?()
        })
    }
    
    func updateUIView(_ tableView: UITableView, context: Context) {
        let coordinator = context.coordinator
        coordinator.uiTableView = tableView
        coordinator.onUIReady = onUIReady
        coordinator.onRefresh = onRefresh

        let changes = detectChanges(coordinator: coordinator)

        // Recreate the tab bar only on structural change, not tab/count change.
        let structureChanged = coordinator.showTabBar != showTabBar
        if structureChanged {
            setupTableHeader(tableView, context: context)
        } else if coordinator.selectedTab != selectedTab || coordinator.localUpdateCount != localUpdateCount {
            if let tabBarHost = coordinator.tabBarHostController {
                let updatedTabBarView = SourceTabBarView(
                    selectedTab: selectedTab,
                    updateCount: localUpdateCount,
                    onTabSelected: { tab in
                        self.selectedTab = tab
                    }
                )
                tabBarHost.rootView = updatedTabBarView
            }
        }

        coordinator.sources = sources
        coordinator.sourcesVersion = sourcesVersion
        coordinator.signedApps = signedApps
        coordinator.importedApps = importedApps
        coordinator.updateChecker = updateChecker
        coordinator.showUpdatesOnly = showUpdatesOnly
        coordinator.showTabBar = showTabBar
        coordinator.selectedTab = selectedTab
        coordinator.localUpdateCount = localUpdateCount
        coordinator.forceUpdateTrigger = forceUpdateTrigger

        if changes.searchChanged {
            coordinator.updateSearchText(searchText)
        }

        coordinator.sortOption = sortOption
        coordinator.sortAscending = sortAscending

        if changes.needsReload {
            // Rebuild the heavy base cache only when repositories change; tab/sort/
            // search/filter reuse it. Reset the render window only when the list
            // changed, so cosmetic refreshes keep scroll position.
            coordinator.invalidateCache(
                rebuildBase: changes.sourcesChanged,
                resetWindow: changes.listChanged || changes.searchChanged
            )
        } else if !changes.hasChanges {
            DispatchQueue.main.async {
                coordinator.onUIReady?()
            }
        }

        if let scrollId = scrollToAppId {
            coordinator.scrollToApp(withId: scrollId)
            coordinator.lastScrollToAppId = scrollId

            DispatchQueue.main.async {
                self.scrollToAppId = nil
            }
        }
    }
    
    func detectChanges(coordinator: Coordinator) -> (hasChanges: Bool, searchChanged: Bool, needsReload: Bool, sourcesChanged: Bool, listChanged: Bool) {
        // O(1) version check — avoids deep-comparing [ASRepository] value structs (O(N) main-thread stall on 100k+ apps).
        let sourcesChanged = coordinator.sourcesVersion != sourcesVersion
        let searchChanged = coordinator.searchText != searchText
        let sortOptionChanged = coordinator.sortOption != sortOption
        let sortDirectionChanged = coordinator.sortAscending != sortAscending
        let updatesFilterChanged = coordinator.showUpdatesOnly != showUpdatesOnly
        let forceTriggerChanged = coordinator.forceUpdateTrigger != forceUpdateTrigger

        let hasChanges = sourcesChanged || searchChanged || sortOptionChanged || sortDirectionChanged || updatesFilterChanged || forceTriggerChanged
        let needsReload = sourcesChanged || sortOptionChanged || sortDirectionChanged || updatesFilterChanged || forceTriggerChanged
        // Contents/order actually changed (not just a cosmetic forceUpdateTrigger bump) — decides whether to reset the render window to top.
        let listChanged = sourcesChanged || sortOptionChanged || sortDirectionChanged || updatesFilterChanged

        return (hasChanges, searchChanged, needsReload, sourcesChanged, listChanged)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            sources: sources,
            sourcesVersion: sourcesVersion,
            searchText: searchText,
            sortOption: sortOption,
            sortAscending: sortAscending,
            signedApps: signedApps,
            importedApps: importedApps,
            updateChecker: updateChecker,
            showUpdatesOnly: showUpdatesOnly,
            showTabBar: showTabBar,
            selectedTab: selectedTab,
            localUpdateCount: localUpdateCount,
            forceUpdateTrigger: forceUpdateTrigger,
            onSelect: onSelect,
            onRefresh: onRefresh
        )
    }
}

// MARK: - Representable Extension: Coordinator
extension SourceAppsTableRepresentableView {
    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var sources: [ASRepository]
        var sourcesVersion: Int = 0
        var searchText: String
        var sortOption: SourceAppsView.SortOption
        var sortAscending: Bool
        var signedApps: FetchedResults<Signed>
        var importedApps: FetchedResults<Imported>
        var updateChecker: AppUpdateChecker
        var showUpdatesOnly: Bool
        var showTabBar: Bool
        var selectedTab: SourceAppsView.SourceTab
        var localUpdateCount: Int
        var forceUpdateTrigger: Int
        let onSelect: (SourceAppsView.SourceAppRoute) -> Void
        var onUIReady: (() -> Void)?
        var onRefresh: (() async -> Void)?
        var refreshControl: UIRefreshControl?
        var tabBarHostController: UIHostingController<SourceTabBarView>?

        var lastScrollToAppId: String?
        weak var uiTableView: UITableView?
        
        struct Cache {
            var allApps: [(source: ASRepository, app: ASRepository.App)] = []
            var sortedApps: [(source: ASRepository, app: ASRepository.App)] = []
            var searchableApps: [(app: (source: ASRepository, app: ASRepository.App), searchString: String)] = []
            var groupedByName: [String: [(source: ASRepository, app: ASRepository.App)]] = [:]
            var groupedByDate: [String: [(source: ASRepository, app: ASRepository.App)]] = [:]
            var sectionTitles: [String] = []
            // Rows per section + running offset before each; drives the cross-section render window.
            var sectionRowCounts: [Int] = []
            var sectionCumulative: [Int] = []

            /// Clears the heavy base arrays; rebuild only when repositories change.
            mutating func clearBase() {
                allApps = []
                searchableApps = []
            }

            mutating func clearSorted() {
                sortedApps = []
                groupedByName = [:]
                groupedByDate = [:]
                sectionTitles = []
                sectionRowCounts = []
                sectionCumulative = []
            }
        }
        
        var cache = Cache()
        var highlightState = HighlightState()
        var searchWorkItem: DispatchWorkItem?
        // True while the cache rebuilds off-main. Stops duplicate builds and keeps
        // `numberOfSections` from forcing a synchronous build on first mount (~1s freeze).
        var isBuilding = false

        // Incremental render window for the flat (.default) list: render a page,
        // grow on scroll — keeps reloadData/tab-switches cheap on huge sources.
        // Sectioned (.name/.date) lists stay fully rendered.
        let pageSize = 200
        var displayLimit = 200
        var isGrowingWindow = false
        
        struct HighlightState {
            var currentCell: UITableViewCell?
            var currentIndexPath: IndexPath?
            var timer: Timer?
            var isScrolling = false
            
            mutating func clear() {
                timer?.invalidate()
                timer = nil
                
                if let cell = currentCell {
                    UIView.animate(withDuration: 0.2) {
                        cell.backgroundColor = .clear
                    }
                }
                
                currentCell = nil
                currentIndexPath = nil
            }
        }
        
        // MARK: - Initialization
        
        init(
            sources: [ASRepository],
            sourcesVersion: Int,
            searchText: String,
            sortOption: SourceAppsView.SortOption,
            sortAscending: Bool,
            signedApps: FetchedResults<Signed>,
            importedApps: FetchedResults<Imported>,
            updateChecker: AppUpdateChecker,
            showUpdatesOnly: Bool,
            showTabBar: Bool,
            selectedTab: SourceAppsView.SourceTab,
            localUpdateCount: Int,
            forceUpdateTrigger: Int,
            onSelect: @escaping (SourceAppsView.SourceAppRoute) -> Void,
            onRefresh: (() async -> Void)? = nil
        ) {
            self.sources = sources
            self.searchText = searchText
            self.sortOption = sortOption
            self.sortAscending = sortAscending
            self.signedApps = signedApps
            self.importedApps = importedApps
            self.updateChecker = updateChecker
            self.showUpdatesOnly = showUpdatesOnly
            self.showTabBar = showTabBar
            self.selectedTab = selectedTab
            self.localUpdateCount = localUpdateCount
            self.forceUpdateTrigger = forceUpdateTrigger
            self.onSelect = onSelect
            self.onRefresh = onRefresh
            self.sourcesVersion = sourcesVersion
            super.init()

            if sortOption != .default {
                invalidateCache()
            }
        }
        
        @objc func handleRefresh(_ refreshControl: UIRefreshControl) {
            Task { @MainActor in
                // Keep the refresh control pinned to the top during refresh.
                if let tableView = self.uiTableView {
                    tableView.setContentOffset(CGPoint(x: 0, y: tableView.contentOffset.y), animated: false)
                }

                if let onRefresh = self.onRefresh {
                    await onRefresh()
                }
                self.invalidateCache()

                await Task.yield()
                refreshControl.endRefreshing()
            }
        }
        
        // MARK: - Computed Properties
        
        var allAppsWithSource: [(source: ASRepository, app: ASRepository.App)] {
            if !cache.allApps.isEmpty {
                return cache.allApps
            }
            
            cache.allApps = sources.flatMap { source in
                source.apps.map { (source: source, app: $0) }
            }
            
            cache.searchableApps = cache.allApps.map { entry in
                let searchComponents = [
                    entry.app.name,
                    entry.app.description,
                    entry.app.subtitle,
                    entry.app.localizedDescription,
                    entry.app.id // bundle identifier
                ].compactMap { $0?.lowercased() }
                
                return (app: entry, searchString: searchComponents.joined(separator: " "))
            }
            
            return cache.allApps
        }
        
        var sortedApps: [(source: ASRepository, app: ASRepository.App)] {
            // Never build synchronously on main — the flatten+sort over 100k+ apps is
            // the tab-open freeze. If cold, schedule off-main and return what we have;
            // the build reloads the table when it lands.
            if cache.sortedApps.isEmpty {
                scheduleSortedAppsBuild()
            }
            return cache.sortedApps
        }

        /// Builds the sorted/base cache off-main, then reloads on main. No-op if already building or empty.
        func scheduleSortedAppsBuild() {
            guard !isBuilding, !sources.isEmpty else { return }
            isBuilding = true

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let newSorted = self.calculateSortedApps()

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.cache.sortedApps = newSorted
                    self.rebuildSectionMetrics()
                    self.isBuilding = false

                    guard let tableView = self.uiTableView, tableView.window != nil else {
                        self.onUIReady?()
                        return
                    }
                    tableView.reloadData()
                    self.onUIReady?()
                }
            }
        }
        
        // MARK: - Search Handling

        func updateSearchText(_ newSearchText: String) {
            searchWorkItem?.cancel()

            if newSearchText.isEmpty {
                self.searchText = newSearchText
                invalidateCache(rebuildBase: false)
                return
            }

            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.searchText = newSearchText
                    self.invalidateCache(rebuildBase: false)
                }
            }

            searchWorkItem = workItem
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.2, execute: workItem)
        }
        
        // MARK: - Scrolling & Highlighting
        
        func scrollToApp(withId appId: String) {
            guard let tableView = uiTableView, !highlightState.isScrolling else { return }
            
            highlightState.isScrolling = true
            highlightState.clear()
            
            let allApps = sortedApps
            
            guard let targetIndex = allApps.firstIndex(where: { $0.app.currentUniqueId == appId }) else {
                highlightState.isScrolling = false
                retryScrollAfterDelay(appId: appId)
                return
            }
            
            let indexPath = calculateIndexPath(for: targetIndex, in: allApps)

            // Grow the window to the target row before scrolling — targetIndex is the flattened position displayLimit measures.
            if targetIndex >= displayLimit {
                displayLimit = min(targetIndex + pageSize, allApps.count)
            }

            tableView.reloadData()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performScroll(to: indexPath, in: tableView)
            }
        }
        
        func retryScrollAfterDelay(appId: String) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                if self.sortedApps.firstIndex(where: { $0.app.currentUniqueId == appId }) != nil {
                    self.scrollToApp(withId: appId)
                } else {
                    AppNavigationManager.shared.clearPendingNavigation()
                }
            }
        }
        
        func performScroll(to indexPath: IndexPath, in tableView: UITableView) {
            guard tableView.numberOfSections > indexPath.section,
                  tableView.numberOfRows(inSection: indexPath.section) > indexPath.row else {
                highlightState.isScrolling = false
                AppNavigationManager.shared.clearPendingNavigation()
                return
            }
            
            tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
            highlightState.currentIndexPath = indexPath
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.highlightCell(at: indexPath)
                self?.highlightState.isScrolling = false
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    AppNavigationManager.shared.navigationCompletedSuccessfully()
                }
            }
        }
        
        func highlightCell(at indexPath: IndexPath) {
            guard let tableView = uiTableView,
                  let cell = tableView.cellForRow(at: indexPath) else { return }
            
            highlightState.clear()
            highlightState.currentIndexPath = indexPath
            highlightState.currentCell = cell
            
            UIView.animate(withDuration: 0.3, animations: {
                cell.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
            }) { [weak self] _ in
                self?.highlightState.timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    self?.highlightState.clear()
                }
            }
        }
        
    }
}
