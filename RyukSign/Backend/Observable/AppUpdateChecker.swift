//
//  AppUpdateChecker.swift
//  RyukSign
//

import SwiftUI
import Combine
import AltSourceKit
import NimbleViews
import UIKit
import CoreData
import OSLog

// MARK: - Shared Update Checker
final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()
    
    @Published private(set) var appsWithUpdates: Set<String> = []
    @Published private(set) var updateCount: Int = 0
    
    private var updateCache: [String: Bool] = [:]
    private let cacheQueue = DispatchQueue(label: "com.feather.updatechecker", attributes: .concurrent)
    
    private init() {}
    
    func checkForUpdates(
        app: ASRepository.App,
        signedApps: FetchedResults<Signed>,
        importedApps: FetchedResults<Imported>
    ) -> Bool {
        let cacheKey = app.currentUniqueId
        // Cached only — never compute during scroll.
        return cacheQueue.sync(execute: { updateCache[cacheKey] }) ?? false
    }

    func precomputeAllUpdates(
        sources: [ASRepository],
        signedApps: FetchedResults<Signed>,
        importedApps: FetchedResults<Imported>
    ) async {
        // Core Data objects aren't thread-safe: snapshot them here, scan only the values off-main.
        let installed = await MainActor.run {
            InstalledAppsIndex(signedApps: signedApps, importedApps: importedApps)
        }

        await Task.detached(priority: .userInitiated) {
            var newCache: [String: Bool] = [:]
            var updatesSet = Set<String>()
            var uniqueApps = Set<String>()

            // Read once off-main (UserDefaults is thread-safe); ignored apps don't count as updates.
            let ignored = SkippedUpdatesManager.persisted

            for source in sources {
                for app in source.apps {
                    let installedApp = self.findInstalledApp(for: app, in: installed)
                    let hasUpdate = self.hasUpdate(
                        installedVersion: installedApp?.version,
                        sourceVersion: app.currentVersion
                    ) && !ignored.contains(app.id ?? "")

                    newCache[app.currentUniqueId] = hasUpdate

                    if hasUpdate {
                        updatesSet.insert(app.currentUniqueId)
                        if let installedApp {
                            uniqueApps.insert(installedApp.uuid)
                        }
                    }
                }
            }
            
            let finalUpdatesSet = updatesSet
            let finalUpdateCount = uniqueApps.count

            await MainActor.run {
                self.cacheQueue.async(flags: .barrier) {
                    self.updateCache = newCache
                }
                self.appsWithUpdates = finalUpdatesSet
                self.updateCount = finalUpdateCount
            }
        }.value
    }

    func clearCache() {
        cacheQueue.async(flags: .barrier) { [weak self] in
            self?.updateCache.removeAll()
        }
    }
    
    func findInstalledApp(
        for app: ASRepository.App,
        signedApps: FetchedResults<Signed>,
        importedApps: FetchedResults<Imported>
    ) -> (version: String?, uuid: String)? {
        findInstalledApp(for: app, in: InstalledAppsIndex(signedApps: signedApps, importedApps: importedApps))
    }

    func findInstalledApp(
        for app: ASRepository.App,
        in installed: InstalledAppsIndex
    ) -> (version: String?, uuid: String)? {
        let appBundleId = app.id ?? ""
        let appNameLower = app.currentName.lowercased()

        guard !appBundleId.isEmpty || !appNameLower.isEmpty else { return nil }

        guard let match = installed.matches(bundleId: appBundleId, nameLower: appNameLower),
              !match.versions.isEmpty
        else { return nil }

        let highestVersion = match.versions.max { v1, v2 in
            return !isNewerVersion(v1, than: v2)
        }

        return (highestVersion, match.uuid)
    }

    func hasUpdate(installedVersion: String?, sourceVersion: String?) -> Bool {
        guard let currentVersion = installedVersion,
              let newVersion = sourceVersion else { return false }
        
        return isNewerVersion(newVersion, than: currentVersion)
    }
    
    private func isNewerVersion(_ new: String, than old: String) -> Bool {
        let newComponents = new.split(separator: ".").compactMap { Int($0) }
        let oldComponents = old.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(newComponents.count, oldComponents.count)
        
        for i in 0..<maxCount {
            let newValue = i < newComponents.count ? newComponents[i] : 0
            let oldValue = i < oldComponents.count ? oldComponents[i] : 0
            
            if newValue > oldValue {
                return true
            } else if newValue < oldValue {
                return false
            }
        }
        
        return false
    }
    
    func refreshUpdateCount(
        sources: [ASRepository],
        signedApps: FetchedResults<Signed>,
        importedApps: FetchedResults<Imported>
    ) {
        Task {
            await performUpdateCheck(sources: sources, signedApps: signedApps, importedApps: importedApps)
        }
    }
    
    @MainActor
    private func performUpdateCheck(
        sources: [ASRepository],
        signedApps: FetchedResults<Signed>,
        importedApps: FetchedResults<Imported>
    ) async {
        var updatesSet = Set<String>()
        var uniqueApps = Set<String>()

        let ignored = SkippedUpdatesManager.shared.bundleIDs

        for source in sources {
            for app in source.apps {
                if checkForUpdates(
                    app: app,
                    signedApps: signedApps,
                    importedApps: importedApps
                ), !ignored.contains(app.id ?? "") {
                    updatesSet.insert(app.currentUniqueId)

                    if let installedApp = findInstalledApp(
                        for: app,
                        signedApps: signedApps,
                        importedApps: importedApps
                    ) {
                        uniqueApps.insert(installedApp.uuid)
                    }
                }
            }
        }
        
        self.appsWithUpdates = updatesSet
        self.updateCount = uniqueApps.count
    }
}

// MARK: - Installed Apps Index
/// Value snapshot of the installed apps, keyed by identifier and lowercased name for O(1) matching.
struct InstalledAppsIndex {
    private struct Entry {
        let version: String?
        let uuid: String?
    }

    private var entries: [Entry] = []
    private var byIdentifier: [String: [Int]] = [:]
    private var byName: [String: [Int]] = [:]

    init(signedApps: FetchedResults<Signed>, importedApps: FetchedResults<Imported>) {
        entries.reserveCapacity(signedApps.count + importedApps.count)

        for s in signedApps {
            add(identifier: s.identifier, originalIdentifier: s.originalIdentifier, name: s.name, version: s.version, uuid: s.uuid)
        }
        for i in importedApps {
            add(identifier: i.identifier, originalIdentifier: i.originalIdentifier, name: i.name, version: i.version, uuid: i.uuid)
        }
    }

    private mutating func add(identifier: String?, originalIdentifier: String?, name: String?, version: String?, uuid: String?) {
        let index = entries.count
        entries.append(Entry(version: version, uuid: uuid))

        if let originalIdentifier {
            byIdentifier[originalIdentifier, default: []].append(index)
        }
        if let identifier, identifier != originalIdentifier {
            byIdentifier[identifier, default: []].append(index)
        }
        byName[(name ?? "").lowercased(), default: []].append(index)
    }

    /// Versions of every matching installed app and the uuid of the first match, in install-list order.
    func matches(bundleId: String, nameLower: String) -> (versions: [String], uuid: String)? {
        var indices = Set<Int>()
        if !bundleId.isEmpty, let ids = byIdentifier[bundleId] {
            indices.formUnion(ids)
        }
        if let ids = byName[nameLower] {
            indices.formUnion(ids)
        }
        guard !indices.isEmpty else { return nil }

        var versions: [String] = []
        var uuid = ""
        for index in indices.sorted() {
            let entry = entries[index]
            if let version = entry.version {
                versions.append(version)
            }
            if uuid.isEmpty {
                uuid = entry.uuid ?? ""
            }
        }
        return (versions, uuid)
    }
}
