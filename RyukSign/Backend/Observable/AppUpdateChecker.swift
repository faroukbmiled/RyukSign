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
        // Core Data objects can't leave the main actor.
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
                    let match = installed.match(for: app)
                    let hasUpdate = !ignored.contains(app.id ?? "")
                        && self.hasUpdate(installedVersion: match?.version, sourceVersion: app.currentVersion)

                    newCache[app.currentUniqueId] = hasUpdate

                    if hasUpdate, let match {
                        updatesSet.insert(app.currentUniqueId)
                        uniqueApps.insert(match.uuid)
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
        InstalledAppsIndex(signedApps: signedApps, importedApps: importedApps).match(for: app)
    }
    
    func hasUpdate(installedVersion: String?, sourceVersion: String?) -> Bool {
        guard let currentVersion = installedVersion,
              let newVersion = sourceVersion else { return false }
        
        return Self.isNewerVersion(newVersion, than: currentVersion)
    }
    
    static func isNewerVersion(_ new: String, than old: String) -> Bool {
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
        let installed = InstalledAppsIndex(signedApps: signedApps, importedApps: importedApps)

        for source in sources {
            for app in source.apps {
                if checkForUpdates(
                    app: app,
                    signedApps: signedApps,
                    importedApps: importedApps
                ), !ignored.contains(app.id ?? "") {
                    updatesSet.insert(app.currentUniqueId)

                    if let installedApp = installed.match(for: app) {
                        uniqueApps.insert(installedApp.uuid)
                    }
                }
            }
        }
        
        self.appsWithUpdates = updatesSet
        self.updateCount = uniqueApps.count
    }
}

// MARK: - Installed apps index
struct InstalledAppsIndex {
    private struct Entry {
        let version: String?
        let uuid: String
    }

    private var _entries: [Entry] = []
    private var _byIdentifier: [String: [Int]] = [:]
    private var _byName: [String: [Int]] = [:]

    init(signedApps: FetchedResults<Signed>, importedApps: FetchedResults<Imported>) {
        _entries.reserveCapacity(signedApps.count + importedApps.count)
        for app in signedApps { _add(app) }
        for app in importedApps { _add(app) }
    }

    private mutating func _add(_ app: AppInfoPresentable) {
        let index = _entries.count
        _entries.append(Entry(version: app.version, uuid: app.uuid ?? ""))

        for identifier in Set([app.identifier, app.originalIdentifier].compactMap { $0 }) where !identifier.isEmpty {
            _byIdentifier[identifier, default: []].append(index)
        }
        if let name = app.name?.lowercased(), !name.isEmpty {
            _byName[name, default: []].append(index)
        }
    }

    func match(for app: ASRepository.App) -> (version: String?, uuid: String)? {
        var indices = Set(_byIdentifier[app.id ?? ""] ?? [])
        indices.formUnion(_byName[app.currentName.lowercased()] ?? [])

        let matches = indices.sorted().map { _entries[$0] }
        let versions = matches.compactMap(\.version)
        guard let first = matches.first, !versions.isEmpty else { return nil }

        let highest = versions.max { AppUpdateChecker.isNewerVersion($1, than: $0) }
        return (highest, first.uuid)
    }
}
