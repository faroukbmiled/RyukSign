//
//  SourceAppsCoordinator+Data.swift
//  RyukSign
//
//  Extracted from SourceAppsTableRepresentableView.swift for maintainability.
//

import SwiftUI
import AltSourceKit
import CoreData

extension SourceAppsTableRepresentableView.Coordinator {
        // MARK: - Sorting & Filtering
        
        func calculateSortedApps() -> [(source: ASRepository, app: ASRepository.App)] {
            let allApps = allAppsWithSource
            
            let filtered = searchText.isEmpty ? allApps : filterBySearch(allApps)
            
            let updatesFiltered = showUpdatesOnly ? 
                filtered.filter { updateChecker.appsWithUpdates.contains($0.app.currentUniqueId) } : 
                filtered
            
            switch sortOption {
            case .default:
                clearGroupedData()
                return sortAscending ? updatesFiltered : updatesFiltered.reversed()
                
            case .name:
                return sortByName(updatesFiltered)
                
            case .date:
                return sortByDate(updatesFiltered)
            }
        }
        
        func filterBySearch(_ apps: [(source: ASRepository, app: ASRepository.App)]) -> [(source: ASRepository, app: ASRepository.App)] {
            let lowercaseSearch = searchText.lowercased()
            guard !lowercaseSearch.isEmpty else { return apps }

            return cache.searchableApps.compactMap { searchableApp in
                searchableApp.searchString.contains(lowercaseSearch) ? searchableApp.app : nil
            }
        }
        
        func sortByName(_ apps: [(source: ASRepository, app: ASRepository.App)]) -> [(source: ASRepository, app: ASRepository.App)] {
            let sorted = apps.sorted { lhs, rhs in
                let n1 = lhs.app.name ?? ""
                let n2 = rhs.app.name ?? ""
                let comparison = n1.localizedCaseInsensitiveCompare(n2) == .orderedAscending
                return sortAscending ? comparison : !comparison
            }
            
            cache.groupedByName = Dictionary(grouping: sorted) { entry in
                let first = entry.app.name?.trimmingCharacters(in: .whitespacesAndNewlines).first?.uppercased() ?? "#"
                return first.range(of: "[A-Z]", options: .regularExpression) != nil ? first : "#"
            }
            
            cache.sectionTitles = cache.groupedByName.keys.sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return sortAscending ? lhs < rhs : lhs > rhs
            }
            
            clearDateGrouping()
            return sorted
        }
        
        func sortByDate(_ apps: [(source: ASRepository, app: ASRepository.App)]) -> [(source: ASRepository, app: ASRepository.App)] {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"

            let grouped = Dictionary(grouping: apps) {
                $0.app.currentDate?.date.stripTime() ?? .distantPast
            }

            let sortedDates = grouped.keys.sorted(by: { sortAscending ? $0 > $1 : $0 < $1 })

            // Within each day, always sort newest-first regardless of sortAscending.
            cache.groupedByDate = grouped.reduce(into: [:]) { result, pair in
                let key = formatter.string(from: pair.key)
                let sortedApps = pair.value.sorted { lhs, rhs in
                    let d1 = lhs.app.currentDate?.date ?? .distantPast
                    let d2 = rhs.app.currentDate?.date ?? .distantPast
                    return d1 > d2
                }
                result[key] = sortedApps
            }

            cache.sectionTitles = sortedDates.map { formatter.string(from: $0) }

            let sorted = sortedDates.flatMap { date -> [(source: ASRepository, app: ASRepository.App)] in
                let key = formatter.string(from: date)
                return cache.groupedByDate[key] ?? []
            }

            clearNameGrouping()
            return sorted
        }
        
        func clearGroupedData() {
            cache.groupedByDate = [:]
            cache.groupedByName = [:]
            cache.sectionTitles = []
        }
        
        func clearNameGrouping() {
            cache.groupedByName = [:]
        }
        
        func clearDateGrouping() {
            cache.groupedByDate = [:]
        }
        
        // MARK: - Index Path Calculation
        
        func calculateIndexPath(for targetIndex: Int, in allApps: [(source: ASRepository, app: ASRepository.App)]) -> IndexPath {
            switch sortOption {
            case .default:
                return IndexPath(row: targetIndex, section: 0)
                
            case .name:
                return calculateNameIndexPath(for: targetIndex, in: allApps)
                
            case .date:
                return calculateDateIndexPath(for: targetIndex, in: allApps)
            }
        }
        
        func calculateNameIndexPath(for targetIndex: Int, in allApps: [(source: ASRepository, app: ASRepository.App)]) -> IndexPath {
            let targetApp = allApps[targetIndex]
            let firstLetter = targetApp.app.name?.trimmingCharacters(in: .whitespacesAndNewlines).first?.uppercased() ?? "#"
            let sectionKey = firstLetter.range(of: "[A-Z]", options: .regularExpression) != nil ? firstLetter : "#"
            
            guard let sectionIndex = cache.sectionTitles.firstIndex(of: sectionKey),
                  let appsInSection = cache.groupedByName[sectionKey],
                  let rowIndex = appsInSection.firstIndex(where: {
                      $0.app.currentUniqueId == targetApp.app.currentUniqueId
                  }) else {
                return IndexPath(row: 0, section: 0)
            }
            
            return IndexPath(row: rowIndex, section: sectionIndex)
        }
        
        func calculateDateIndexPath(for targetIndex: Int, in allApps: [(source: ASRepository, app: ASRepository.App)]) -> IndexPath {
            let targetApp = allApps[targetIndex]
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            let dateKey = formatter.string(from: targetApp.app.currentDate?.date.stripTime() ?? .distantPast)
            
            guard let sectionIndex = cache.sectionTitles.firstIndex(of: dateKey),
                  let appsInSection = cache.groupedByDate[dateKey],
                  let rowIndex = appsInSection.firstIndex(where: {
                      $0.app.currentUniqueId == targetApp.app.currentUniqueId
                  }) else {
                return IndexPath(row: 0, section: 0)
            }
            
            return IndexPath(row: rowIndex, section: sectionIndex)
        }
        
        // MARK: - Cache Management

        // MARK: - Render Window

        /// Caches rows-per-section and running offset for the current sort, so the window applies across sections in O(1).
        func rebuildSectionMetrics() {
            let counts: [Int]
            switch sortOption {
            case .default:
                counts = [cache.sortedApps.count]
            case .name:
                counts = cache.sectionTitles.map { cache.groupedByName[$0]?.count ?? 0 }
            case .date:
                counts = cache.sectionTitles.map { cache.groupedByDate[$0]?.count ?? 0 }
            }
            cache.sectionRowCounts = counts

            var cumulative = [Int]()
            cumulative.reserveCapacity(counts.count)
            var running = 0
            for c in counts {
                cumulative.append(running)
                running += c
            }
            cache.sectionCumulative = cumulative
        }

        /// Sections currently rendered and rows in the last (possibly partial) one, given `displayLimit`.
        func visibleWindow() -> (sections: Int, lastRows: Int) {
            let counts = cache.sectionRowCounts
            guard !counts.isEmpty else { return (0, 0) }

            var cum = 0
            for (i, c) in counts.enumerated() {
                if cum + c >= displayLimit {
                    let rows = displayLimit - cum
                    return rows > 0 ? (i + 1, min(rows, c)) : (i, 0)
                }
                cum += c
            }
            return (counts.count, counts.last ?? 0)
        }

        func invalidateCache(rebuildBase: Bool = true, resetWindow: Bool = true) {
            if rebuildBase {
                cache.clearBase()
            }
            cache.clearSorted()
            isBuilding = true

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let newSortedApps = self.calculateSortedApps()

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    self.cache.sortedApps = newSortedApps
                    self.rebuildSectionMetrics()
                    self.isBuilding = false
                    // Reset the window to top only when the list changed; cosmetic refreshes keep scroll position.
                    if resetWindow {
                        self.displayLimit = self.pageSize
                    } else {
                        // Keep covering the current scroll position.
                        self.displayLimit = min(max(self.displayLimit, self.pageSize), max(newSortedApps.count, self.pageSize))
                    }
                    self.isGrowingWindow = false

                    if let tableView = self.uiTableView {
                        // tableView may be gone during rapid search — guard against crashes.
                        guard tableView.window != nil else {
                            self.onUIReady?()
                            return
                        }

                        UIView.transition(with: tableView, duration: 0.3, options: [.transitionCrossDissolve], animations: {
                            tableView.reloadData()
                        }) { [weak self] _ in
                            self?.onUIReady?()
                        }
                    }
                }
            }
        }
        
}
