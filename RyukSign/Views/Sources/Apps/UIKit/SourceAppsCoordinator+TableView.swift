//
//  SourceAppsCoordinator+TableView.swift
//  RyukSign
//
//  Extracted from SourceAppsTableRepresentableView.swift for maintainability.
//

import SwiftUI
import AltSourceKit
import CoreData

extension SourceAppsTableRepresentableView.Coordinator {
        // MARK: - TableView DataSource
        
        func numberOfSections(in tableView: UITableView) -> Int {
            // Materialize the list + section metrics (lazy default path), then render only the windowed sections.
            _ = sortedApps
            return visibleWindow().sections
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            let window = visibleWindow()
            guard section < window.sections else { return 0 }
            // The last visible section may be partially rendered.
            if section == window.sections - 1 {
                return window.lastRows
            }
            return cache.sectionRowCounts[safe: section] ?? 0
        }
        
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "AppCell", for: indexPath)

            cell.backgroundColor = .clear
            cell.selectionStyle = .default

            guard let entry = getEntry(at: indexPath) else {
                // Return empty cell if entry not found (prevents crashes)
                cell.contentConfiguration = nil
                return cell
            }

            cell.contentConfiguration = UIHostingConfiguration {
                SourceAppsCellView(source: entry.source, app: entry.app)
            }

            return cell
        }
        
        // MARK: - TableView Delegate
        
        func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            if #available(iOS 17, *) {
                tableView.deselectRow(at: indexPath, animated: true)
                guard let entry = getEntry(at: indexPath) else { return }
                onSelect(SourceAppsView.SourceAppRoute(source: entry.source, app: entry.app))
            }
        }

        func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            // Grow the render window as the user nears the end. Works for flat and sectioned layouts via the absolute (flattened) row.
            guard !isGrowingWindow, displayLimit < cache.sortedApps.count else { return }
            let absoluteRow = (cache.sectionCumulative[safe: indexPath.section] ?? 0) + indexPath.row
            guard absoluteRow >= displayLimit - 16 else { return }

            isGrowingWindow = true
            DispatchQueue.main.async { [weak self, weak tableView] in
                guard let self, let tableView else { return }
                defer { self.isGrowingWindow = false }
                let old = self.displayLimit
                let total = self.cache.sortedApps.count
                guard old < total else { return }
                self.displayLimit = min(old + self.pageSize, total)
                // The window can add rows and sections, so reloadData extends both layouts and preserves contentOffset.
                UIView.performWithoutAnimation {
                    tableView.reloadData()
                }
            }
        }
        
        func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeader")
            let title = getSectionTitle(for: section)
            
            headerView?.contentConfiguration = UIHostingConfiguration {
                HStack {
                    Text(verbatim: title)
                    Spacer()
                }
                .font(.headline)
                .padding(.vertical, 2)
            }
            
            return headerView
        }
        
        func sectionIndexTitles(for tableView: UITableView) -> [String]? {
            guard sortOption == .name else { return nil }
            // Only offer letters currently rendered, so an index tap can't hit an unrendered section.
            let sections = visibleWindow().sections
            return sections > 0 ? Array(cache.sectionTitles.prefix(sections)) : nil
        }
        
        func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
            cache.sectionTitles.firstIndex(of: title) ?? 0
        }
        
        func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
            guard let entry = getEntry(at: indexPath) else { return nil }

            return UIContextMenuConfiguration(
                identifier: nil,
                previewProvider: nil
            ) { _ in
                let versionsMenu = UIMenu(
                    title: .localized("Copy Download URLs"),
                    image: UIImage(systemName: "list.bullet"),
                    children: self.contextActions(for: entry.app, with: { version in
                        UIPasteboard.general.string = version?.absoluteString
                    }, image: UIImage(systemName: "doc.on.clipboard"))
                )

                let downloadsMenu = UIMenu(
                    title: .localized("Previous Versions"),
                    image: UIImage(systemName: "square.and.arrow.down.on.square"),
                    children: self.contextActions(for: entry.app, with: { version in
                        if let url = version {
                            _ = DownloadManager.shared.startDownload(
                                from: url,
                                id: entry.app.currentUniqueId,
                                appName: entry.app.name
                            )
                        }
                    }, image: UIImage(systemName: "arrow.down"))
                )

                var actions: [UIMenuElement] = []

                if let bundleId = entry.app.id {
                    let appStoreAction = UIAction(
                        title: .localized("View on App Store"),
                        image: UIImage(systemName: "bag")
                    ) { _ in
                        AppStoreHelper.openAppStore(for: bundleId) { result in
                            if case .failure(let error) = result {
                                DispatchQueue.main.async {
                                    let alert = UIAlertController(
                                        title: "App Store Error",
                                        message: error.localizedDescription,
                                        preferredStyle: .alert
                                    )
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))

                                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let viewController = windowScene.windows.first?.rootViewController {
                                        viewController.present(alert, animated: true)
                                    }
                                }
                            }
                        }
                    }
                    actions.append(appStoreAction)
                }

                actions.append(contentsOf: [downloadsMenu, versionsMenu])

                // Ignore/resume update checks — only for installed apps; placed at the bottom of the menu.
                if
                    let bundleId = entry.app.id, !bundleId.isEmpty,
                    self.updateChecker.findInstalledApp(
                        for: entry.app,
                        signedApps: self.signedApps,
                        importedApps: self.importedApps
                    ) != nil
                {
                    let isIgnored = SkippedUpdatesManager.shared.isIgnored(bundleId)
                    let ignoreAction = UIAction(
                        title: isIgnored ? .localized("Resume Updates") : .localized("Ignore Updates"),
                        image: UIImage(systemName: isIgnored ? "bell" : "bell.slash")
                    ) { _ in
                        SkippedUpdatesManager.shared.toggle(bundleId)
                    }
                    actions.append(ignoreAction)
                }

                return UIMenu(children: actions)
            }
        }
        
        // MARK: - Helper Methods
        
        func getEntry(at indexPath: IndexPath) -> (source: ASRepository, app: ASRepository.App)? {
            switch sortOption {
            case .default:
                return sortedApps[safe: indexPath.row]
            case .name:
                guard let sectionKey = cache.sectionTitles[safe: indexPath.section] else { return nil }
                return cache.groupedByName[sectionKey]?[safe: indexPath.row]
            case .date:
                guard let sectionKey = cache.sectionTitles[safe: indexPath.section] else { return nil }
                return cache.groupedByDate[sectionKey]?[safe: indexPath.row]
            }
        }
        
        func getSectionTitle(for section: Int) -> String {
            switch sortOption {
            case .default: 
                if showUpdatesOnly {
                    return .localized("%lld Updates", arguments: sortedApps.count)
                } else {
                    return .localized("%lld Apps", arguments: sortedApps.count)
                }
            case .name, .date: 
                return cache.sectionTitles[safe: section] ?? ""
            }
        }
        
        func contextActions(
            for app: ASRepository.App,
            with action: @escaping (URL?) -> Void,
            image: UIImage?
        ) -> [UIAction] {
            if let versions = app.versions, !versions.isEmpty {
                return versions.map { version in
                    UIAction(
                        title: version.version,
                        image: image
                    ) { _ in
                        action(version.downloadURL)
                    }
                }
            } else {
                return [
                    UIAction(
                        title: app.currentVersion ?? "",
                        image: image
                    ) { _ in
                        action(app.currentDownloadUrl)
                    }
                ]
            }
        }
}
