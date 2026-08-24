//
//  ContentView.swift
//  RyukSign
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - View
struct LibraryView: View {
    @StateObject var downloadManager = DownloadManager.shared
    @ObservedObject private var tabSelection = TabSelectionObserver.shared
    
    @State private var _selectedInfoAppPresenting: AnyApp?
    @State private var _selectedSigningAppPresenting: AnyApp?
    @State private var _selectedInstallAppPresenting: AnyApp?
    @State private var _isImportingPresenting = false
    @State private var _isDownloadingPresenting = false
    @State private var _alertDownloadString: String = "" // for _isDownloadingPresenting
    
    // MARK: Selection State
    @State private var _selectedAppUUIDs: Set<String> = []
    @State private var _editMode: EditMode = .inactive
    @State private var _showDeleteConfirmation = false
    @State private var _batchRequest: BatchRequest?

    @State private var _searchText = ""
    @State private var _selectedScope: Scope = .all

    @State private var scrollProxy: ScrollViewProxy?
    
    @Namespace private var _namespace
    
    // MARK: Fetch
    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
        animation: .snappy
    ) private var _signedApps: FetchedResults<Signed>
    
    @FetchRequest(
        entity: Imported.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
        animation: .snappy
    ) private var _importedApps: FetchedResults<Imported>
    
    // MARK: Computed Properties
    private var filteredSignedApps: [Signed] {
        _signedApps.filter { app in
            _searchText.isEmpty ||
            (app.name?.localizedCaseInsensitiveContains(_searchText) ?? false)
        }
    }
    
    private var filteredImportedApps: [Imported] {
        _importedApps.filter { app in
            _searchText.isEmpty ||
            (app.name?.localizedCaseInsensitiveContains(_searchText) ?? false)
        }
    }
    
    private var shouldShowSignedSection: Bool {
        _selectedScope == .all || _selectedScope == .signed
    }
    
    private var shouldShowImportedSection: Bool {
        _selectedScope == .all || _selectedScope == .imported
    }
    
    private var hasNoContent: Bool {
        filteredSignedApps.isEmpty && filteredImportedApps.isEmpty
    }
    
    // MARK: Body
    var body: some View {
        NBNavigationView(.localized("Library")) {
            mainContent
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if _editMode.isEditing {
                            HStack(spacing: 12) {
                                Button("Done") {
                                    withAnimation {
                                        _editMode = .inactive
                                        _selectedAppUUIDs.removeAll()
                                    }
                                }
                                Button(action: selectAllApps) {
                                    Text("Select All")
                                }
                            }
                        } else {
                            Button("Edit") {
                                withAnimation {
                                    _editMode = .active
                                }
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if !_editMode.isEditing {
                            Menu {
                                importMenuActions
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if _editMode.isEditing {
                        selectionActionBar
                    }
                }
                .environment(\.editMode, $_editMode)
                .sheet(item: $_selectedInfoAppPresenting) { app in
                    LibraryInfoView(app: app.base)
                }
                .sheet(item: $_selectedInstallAppPresenting) { app in
                    InstallPreviewView(app: app.base, isSharing: app.archive)
                        .presentationDetents([.height(200)])
                        .presentationDragIndicator(.visible)
                }
                .fullScreenCover(item: $_batchRequest) { request in
                    BatchSignView(apps: request.apps, mode: request.mode)
                }
                .fullScreenCover(item: $_selectedSigningAppPresenting) { app in
                    SigningView(app: app.base)
                        .compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
                }
                .sheet(isPresented: $_isImportingPresenting) {
                    importerSheet
                }
                .alert(.localized("Import from URL"), isPresented: $_isDownloadingPresenting) {
                    urlImportAlert
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Feather.installApp"))) { _ in
                    if let latest = _signedApps.first {
                        _selectedInstallAppPresenting = AnyApp(base: latest)
                    }
                }
                .onChange(of: _editMode) { mode in
                    if mode == .inactive {
                        _selectedAppUUIDs.removeAll()
                    }
                }
                .alert(
                    deleteDialogTitle,
                    isPresented: $_showDeleteConfirmation
                ) {
                    Button("Delete", role: .destructive) {
                        bulkDeleteSelectedApps()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This action cannot be undone.")
                }
        }
    }

    private var deleteDialogTitle: String {
        let count = _selectedAppUUIDs.count
        return "Delete \(count) \(count == 1 ? "app" : "apps")?"
    }
    
    // MARK: Main Content View
    @ViewBuilder
    private var mainContent: some View {
        ScrollViewReader { proxy in
            NBListAdaptable {
                if !hasNoContent {
                    appsListContent
                }
            }
            .searchable(text: $_searchText, placement: .platform())
            .compatSearchScopes($_selectedScope) {
                ForEach(Scope.allCases, id: \.displayName) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: tabSelection.highlightedAppUUID) { newUUID in
                if let uuid = newUUID {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        proxy.scrollTo(uuid, anchor: .center)
                    }
                }
            }
        }
        .overlay {
            if hasNoContent {
                emptyStateView
            }
        }
    }
    
    // MARK: Apps List Content
    @ViewBuilder
    private var appsListContent: some View {
        if !filteredSignedApps.isEmpty, shouldShowSignedSection {
            signedAppsSection
        }

        if !filteredImportedApps.isEmpty, shouldShowImportedSection {
            importedAppsSection
        }
    }
    
    // MARK: Signed Apps Section
    @ViewBuilder
    private var signedAppsSection: some View {
        let selectedSignedCount = filteredSignedApps.filter { app in
            guard let uuid = app.uuid else { return false }
            return _selectedAppUUIDs.contains(uuid)
        }.count

        let sectionTitle = _editMode.isEditing && selectedSignedCount > 0
            ? "\(selectedSignedCount) selected"
            : filteredSignedApps.count.description

        NBSection(
            .localized("Signed"),
            secondary: sectionTitle
        ) {
            ForEach(filteredSignedApps, id: \.uuid) { app in
                LibraryCellView(
                    app: app,
                    selectedInfoAppPresenting: $_selectedInfoAppPresenting,
                    selectedSigningAppPresenting: $_selectedSigningAppPresenting,
                    selectedInstallAppPresenting: $_selectedInstallAppPresenting,
                    selectedAppUUIDs: $_selectedAppUUIDs,
                    isHighlighted: app.uuid == tabSelection.highlightedAppUUID,
                    onSelectMore: { _beginSelection(with: app) }
                )
                .compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
                .id(app.uuid)
            }
        }
    }
    
    // MARK: Imported Apps Section
    @ViewBuilder
    private var importedAppsSection: some View {
        let selectedImportedCount = filteredImportedApps.filter { app in
            guard let uuid = app.uuid else { return false }
            return _selectedAppUUIDs.contains(uuid)
        }.count

        let sectionTitle = _editMode.isEditing && selectedImportedCount > 0
            ? "\(selectedImportedCount) selected"
            : filteredImportedApps.count.description

        NBSection(
            .localized("Imported"),
            secondary: sectionTitle
        ) {
            ForEach(filteredImportedApps, id: \.uuid) { app in
                LibraryCellView(
                    app: app,
                    selectedInfoAppPresenting: $_selectedInfoAppPresenting,
                    selectedSigningAppPresenting: $_selectedSigningAppPresenting,
                    selectedInstallAppPresenting: $_selectedInstallAppPresenting,
                    selectedAppUUIDs: $_selectedAppUUIDs,
                    isHighlighted: app.uuid == tabSelection.highlightedAppUUID,
                    onSelectMore: { _beginSelection(with: app) }
                )
                .compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
                .id(app.uuid)
            }
        }
    }
    
    // MARK: Empty State View
    @ViewBuilder
    private var emptyStateView: some View {
        NBContentUnavailable(
            .localized("No Apps"),
            systemImage: "questionmark.app.fill",
            description: .localized("Get started by importing your first IPA file.")
        ) {
            Menu {
                importMenuActions
            } label: {
                NBButton(.localized("Import"), style: .text)
            }
        }
    }
    
    // MARK: Selection Action Bar
    @ViewBuilder
    private var selectionActionBar: some View {
        let selection = selectedApps()
        let canSign = selection.contains { !$0.isSigned }
        let canInstall = !selection.isEmpty && selection.allSatisfy { $0.isSigned }

        HStack(spacing: 10) {
            if canInstall {
                _actionButton(.localized("Install"), systemImage: "square.and.arrow.down") {
                    _startBatch(.install)
                }
            } else {
                _actionButton(.localized("Sign"), systemImage: "signature", isDisabled: !canSign) {
                    _startBatch(.sign)
                }
                _actionButton(.localized("Sign & Install"), systemImage: "square.and.arrow.down.on.square", isDisabled: !canSign) {
                    _startBatch(.signAndInstall)
                }
            }

            Button(role: .destructive) {
                _showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.medium))
                    .frame(height: 34)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(_selectedAppUUIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func _actionButton(
        _ title: String,
        systemImage: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDisabled || _selectedAppUUIDs.isEmpty)
    }

    // MARK: Import Menu Actions
    @ViewBuilder
    private var importMenuActions: some View {
        Button(.localized("Import from Files"), systemImage: "folder") {
            _isImportingPresenting = true
        }
        Button(.localized("Import from URL"), systemImage: "globe") {
            _isDownloadingPresenting = true
        }
    }
    
    // MARK: Importer Sheet
    private var importerSheet: some View {
        FileImporterRepresentableView(
            allowedContentTypes: [.ipa, .tipa],
            allowsMultipleSelection: true,
            folder: .apps,
            onDocumentsPicked: { urls in
                guard !urls.isEmpty else { return }
                
                for url in urls {
                    let id = "FeatherManualDownload_\(UUID().uuidString)"
                    let dl = downloadManager.startArchive(from: url, id: id)
                }
            }
        )
        .ignoresSafeArea()
    }
    
    // MARK: URL Import Alert
    @ViewBuilder
    private var urlImportAlert: some View {
        TextField(.localized("URL"), text: $_alertDownloadString)
            .textInputAutocapitalization(.never)
        Button(.localized("Cancel"), role: .cancel) {
            _alertDownloadString = ""
        }
        Button(.localized("OK")) {
            if let url = URL(string: _alertDownloadString) {
                _ = downloadManager.startDownload(
                    from: url,
                    id: "FeatherManualDownload_\(UUID().uuidString)"
                )
            }
        }
    }
}

// MARK: - Extension: Batch
extension LibraryView {
    struct BatchRequest: Identifiable {
        let id = UUID()
        let apps: [AppInfoPresentable]
        let mode: BatchJobRunner.Mode
    }

    private func selectedApps() -> [AppInfoPresentable] {
        getAllApps().filter { app in
            guard let uuid = app.uuid else { return false }
            return _selectedAppUUIDs.contains(uuid)
        }
    }

    private func _beginSelection(with app: AppInfoPresentable) {
        guard let uuid = app.uuid else { return }

        withAnimation {
            _editMode = .active
            _selectedAppUUIDs = [uuid]
        }
    }

    private func _startBatch(_ mode: BatchJobRunner.Mode) {
        let apps = selectedApps()
        guard !apps.isEmpty else { return }

        _batchRequest = BatchRequest(apps: apps, mode: mode)
        _selectedAppUUIDs.removeAll()
        _editMode = .inactive
    }
}

// MARK: - Extension: Bulk Delete
extension LibraryView {
    private func bulkDeleteSelectedApps() {
        for app in selectedApps() {
            Storage.shared.deleteApp(for: app)
        }

        _selectedAppUUIDs.removeAll()
        _editMode = .inactive
    }
    
    private func getAllApps() -> [AppInfoPresentable] {
        var allApps: [AppInfoPresentable] = []

        if shouldShowSignedSection {
            allApps.append(contentsOf: filteredSignedApps)
        }

        if shouldShowImportedSection {
            allApps.append(contentsOf: filteredImportedApps)
        }

        return allApps
    }

    private var areAllAppsSelected: Bool {
        let allApps = getAllApps()
        let allUUIDs = Set(allApps.compactMap { $0.uuid })
        return !allUUIDs.isEmpty && _selectedAppUUIDs == allUUIDs
    }

    private func selectAllApps() {
        if areAllAppsSelected {
            _selectedAppUUIDs.removeAll()
        } else {
            let allApps = getAllApps()
            _selectedAppUUIDs = Set(allApps.compactMap { $0.uuid })
        }
    }
}

// MARK: - Extension: View (Sort)
extension LibraryView {
    enum Scope: CaseIterable {
        case all
        case signed
        case imported
        
        var displayName: String {
            switch self {
            case .all: return .localized("All")
            case .signed: return .localized("Signed")
            case .imported: return .localized("Imported")
            }
        }
    }
}
