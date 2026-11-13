//
//  AppNavigationManager.swift
//  RyukSign
//
//  Navigation manager for handling app scrolling and tab switching
//

import Foundation
import SwiftUI
import Combine

// MARK: - App Navigation Manager
class AppNavigationManager: ObservableObject {
    static let shared = AppNavigationManager()
    
    @Published var pendingAppNavigation: PendingAppNavigation?
    
    private var navigationTimer: Timer?
    private var lastNavigationTime: Date = .distantPast
    private let navigationDebounceInterval: TimeInterval = 1.0
    
    private init() {}
    
    struct PendingAppNavigation: Equatable {
        let appId: String
        let appName: String
        let sourceIdentifier: String?
        var opensDetail = false
        let navigationId: String = UUID().uuidString
        let timestamp: Date = Date()
        
        static func == (lhs: PendingAppNavigation, rhs: PendingAppNavigation) -> Bool {
            return lhs.appId == rhs.appId
        }
    }
    
    func navigateToApp(appId: String, appName: String, sourceIdentifier: String? = nil, opensDetail: Bool = false) {
        let now = Date()
        guard now.timeIntervalSince(lastNavigationTime) > navigationDebounceInterval else {
            return
        }
        
        lastNavigationTime = now
        
        clearPendingNavigation()
        
        pendingAppNavigation = PendingAppNavigation(
            appId: appId,
            appName: appName,
            sourceIdentifier: sourceIdentifier,
            opensDetail: opensDetail
        )
        
        TabSelectionObserver.shared.selectedTab = .sources
        
        navigationTimer?.invalidate()
        navigationTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { [weak self] _ in
            self?.clearPendingNavigation()
        }
    }

    func navigationCompletedSuccessfully() {
        clearPendingNavigation()
    }
    
    func clearPendingNavigation() {
        pendingAppNavigation = nil
        navigationTimer?.invalidate()
        navigationTimer = nil
    }
    
    func forceNavigateToApp(appId: String, appName: String, sourceIdentifier: String? = nil) {
        clearPendingNavigation()
        navigateToApp(appId: appId, appName: appName, sourceIdentifier: sourceIdentifier)
    }
}
