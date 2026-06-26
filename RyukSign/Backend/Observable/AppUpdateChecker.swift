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
        await Task.detached(priority: .userInitiated) {
            var newCache: [String: Bool] = [:]
            var updatesSet = Set<String>()
            var uniqueApps = Set<String>()

            // Read once off-main (UserDefaults is thread-safe); ignored apps don't count as updates.
            let ignored = SkippedUpdatesManager.persisted

            for source in sources {
                for app in source.apps {
                    let hasUpdate = self.computeUpdate(
                        app: app,
                        signedApps: signedApps,
                        importedApps: importedApps
                    ) && !ignored.contains(app.id ?? "")

                    newCache[app.currentUniqueId] = hasUpdate

                    if hasUpdate {
                        updatesSet.insert(app.currentUniqueId)
                        if let installedApp = self.findInstalledApp(
                            for: app,
                            signedApps: signedApps,
                            importedApps: importedApps
                        ) {
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

    private func computeUpdate(
        app: ASRepository.App,
        signedApps: FetchedResults<Signed>,
        importedApps: FetchedResults<Imported>
    ) -> Bool {
        guard let installed = findInstalledApp(
            for: app,
            signedApps: signedApps,
            importedApps: importedApps
        ) else {
            return false
        }
        
        return hasUpdate(
            installedVersion: installed.version,
            sourceVersion: app.currentVersion
        )
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
        let appBundleId = app.id ?? ""
        let appNameLower = app.currentName.lowercased()
        
        guard !appBundleId.isEmpty || !appNameLower.isEmpty else { return nil }

        func identifiersMatch(_ sourceId: String, _ storedId: String?, _ originalId: String?) -> Bool {
            if let originalId = originalId, sourceId == originalId { return true }
            if let storedId = storedId, sourceId == storedId { return true }
            return false
        }
        
        var allMatchingVersions: [String] = []
        var matchingUUID: String = ""

        for s in signedApps {
            let identifierMatch = !appBundleId.isEmpty &&
                identifiersMatch(appBundleId, s.identifier, s.originalIdentifier)
            let nameMatch = (s.name ?? "").lowercased() == appNameLower
            
            if identifierMatch || nameMatch {
                if let version = s.version {
                    allMatchingVersions.append(version)
                }
                if matchingUUID.isEmpty {
                    matchingUUID = s.uuid ?? ""
                }
            }
        }
        
        for i in importedApps {
            let identifierMatch = !appBundleId.isEmpty &&
                identifiersMatch(appBundleId, i.identifier, i.originalIdentifier)
            let nameMatch = (i.name ?? "").lowercased() == appNameLower
            
            if identifierMatch || nameMatch {
                if let version = i.version {
                    allMatchingVersions.append(version)
                }
                if matchingUUID.isEmpty {
                    matchingUUID = i.uuid ?? ""
                }
            }
        }
        
        guard !allMatchingVersions.isEmpty else { return nil }

        let highestVersion = allMatchingVersions.max { v1, v2 in
            return !isNewerVersion(v1, than: v2)
        }
        
        return (highestVersion, matchingUUID)
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
