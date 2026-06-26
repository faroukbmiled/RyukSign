//
//  SourcesView.swift
//  RyukSign
//
//  Created by samara on 10.04.2025.
//
import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.scenePhase) private var scenePhase
	#if !NIGHTLY && !DEBUG
	@AppStorage("Feather.shouldStar") private var _shouldStar: Int = 0
	#endif
	@StateObject var viewModel = SourcesViewModel.shared
	@State private var _isAddingPresenting = false
	@State private var _addingSourceLoading = false
	@State private var _searchText = ""
	@State private var _shouldNavigateToAllRepos = false
	@State private var _activeIndividualSource: AltSource? = nil
	@State private var _isEditMode = false
	@State private var _selectedSources: Set<AltSource> = []
	@State private var _showDeleteConfirmation = false

	@AppStorage("Feather.sourcesTabShowAllReposDirectly")
	private var _sourcesTabShowAllReposDirectly: Bool = false

	/// Sources not excluded from "All Repositories"
	private var _nonExcludedSources: [AltSource] {
		_sources.filter { source in
			let id = source.identifier ?? source.sourceURL?.absoluteString ?? ""
			return !RyukSignAPI.isSourceExcluded(id)
		}
	}

	@ObservedObject var appNavigationManager = AppNavigationManager.shared

	private var _filteredSources: [AltSource] {
		_sources.filter { _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false) }
	}

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Sources")) {
			mainContent
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
		.onChange(of: appNavigationManager.pendingAppNavigation) { pendingNavigation in
			handlePendingNavigation(pendingNavigation)
		}
		.onChange(of: _isEditMode) { isEditing in
			if !isEditing {
				_selectedSources.removeAll()
			}
		}
		.onChange(of: scenePhase) { newPhase in
			if newPhase == .active {
				Task {
					await viewModel.fetchSources(_sources)
				}
			}
		}
	}

	@ViewBuilder
	private var mainContent: some View {
		if _sourcesTabShowAllReposDirectly && !_filteredSources.isEmpty {
			allRepositoriesDirectView
		} else {
			sourcesListView
		}
	}

	@ViewBuilder
	private var allRepositoriesDirectView: some View {
		SourceAppsView(
			object: _nonExcludedSources,
			viewModel: viewModel,
			onRefresh: {
				await self.viewModel.fetchSources(self._sources, refresh: true)
			}
		)
		.toolbar {
			NBToolbarButton(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing,
				isDisabled: _addingSourceLoading
			) {
				_isAddingPresenting = true
			}
		}
		.sheet(isPresented: $_isAddingPresenting) {
			SourcesAddView()
		}
	}

	@ViewBuilder
	private var sourcesListView: some View {
		NBListAdaptable {
			if !_filteredSources.isEmpty {
				allRepositoriesSection
				repositoriesSection
			}
		}
		.searchable(text: $_searchText, placement: .platform())
		.overlay {
			emptyStateView
		}
		.toolbar {
			toolbarContent
		}
		.refreshable {
			await viewModel.fetchSources(_sources, refresh: true)
		}
		.sheet(isPresented: $_isAddingPresenting) {
			SourcesAddView()
		}
		.alert(
			deleteDialogTitle,
			isPresented: $_showDeleteConfirmation
		) {
			Button("Delete", role: .destructive) {
				deleteSelectedSources()
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This action cannot be undone.")
		}
	}

	private var deleteDialogTitle: String {
		let count = _selectedSources.count
		return "Delete \(count) \(count == 1 ? "repository" : "repositories")?"
	}

	@ViewBuilder
	private var allRepositoriesSection: some View {
		Section {
			NavigationLink(isActive: $_shouldNavigateToAllRepos) {
				SourceAppsView(
					object: _nonExcludedSources,
					viewModel: viewModel,
					onRefresh: {
						await self.viewModel.fetchSources(self._sources, refresh: true)
					}
				)
			} label: {
				allRepositoriesLabel
			}
			.buttonStyle(.plain)
			.onChange(of: _shouldNavigateToAllRepos) { isActive in
				if isActive {
					_activeIndividualSource = nil
				}
			}
		}
		.disabled(_isEditMode)
	}

	@ViewBuilder
	private var allRepositoriesLabel: some View {
		let isRegular = horizontalSizeClass != .compact
		HStack(spacing: 18) {
			Image("Repositories").appIconStyle()
			NBTitleWithSubtitleView(
				title: .localized("All Repositories"),
				subtitle: .localized("See all apps from your sources")
			)
		}
		.padding(isRegular ? 12 : 0)
		.background(
			isRegular
			? RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(Color(.quaternarySystemFill))
			: nil
		)
	}

	@ViewBuilder
	private var repositoriesSection: some View {
		let sectionTitle = _isEditMode ? "\(_selectedSources.count) selected" : "\(_filteredSources.count)"
		NBSection(
			.localized("Repositories"),
			secondary: sectionTitle
		) {
			ForEach(_filteredSources) { source in
				if _isEditMode {
					editModeRow(for: source)
				} else {
					normalModeRow(for: source)
				}
			}
		}
	}

	@ViewBuilder
	private func editModeRow(for source: AltSource) -> some View {
		HStack(spacing: 12) {
			selectionButton(for: source)
			SourcesCellView(source: source, isEditMode: true)
		}
		.contentShape(Rectangle())
		.onTapGesture {
			toggleSelection(for: source)
		}
	}

	@ViewBuilder
	private func selectionButton(for source: AltSource) -> some View {
		let isPremium = source.sourceURL.map { RyukSignAPI.isPremiumSource($0) } ?? false
		Button {
			toggleSelection(for: source)
		} label: {
			let isSelected = _selectedSources.contains(source)
			if isPremium {
				Image(systemName: "lock.fill")
					.font(.title3)
					.foregroundColor(.secondary.opacity(0.5))
			} else {
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.font(.title3)
					.foregroundColor(isSelected ? .accentColor : .secondary)
			}
		}
		.buttonStyle(.plain)
		.disabled(isPremium)
	}

	@ViewBuilder
	private func normalModeRow(for source: AltSource) -> some View {
		let isActive = Binding(
			get: { _activeIndividualSource == source },
			set: { isActive in
				if isActive {
					_activeIndividualSource = source
					_shouldNavigateToAllRepos = false
				} else if _activeIndividualSource == source {
					_activeIndividualSource = nil
				}
			}
		)

		NavigationLink(isActive: isActive) {
			SourceAppsView(
				object: [source],
				viewModel: viewModel,
				onRefresh: {
					await self.viewModel.fetchSources(self._sources, refresh: true)
				}
			)
		} label: {
			SourcesCellView(source: source, isEditMode: false)
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private var emptyStateView: some View {
		if _filteredSources.isEmpty {
			NBContentUnavailable(
				.localized("No Repositories"),
				systemImage: "globe.desk.fill",
				description: .localized("Get started by adding your first repository.")
			) {
				Button {
					_isAddingPresenting = true
				} label: {
					NBButton(.localized("Add Source"), style: .text)
				}
			}
		}
	}

	@ToolbarContentBuilder
	private var toolbarContent: some ToolbarContent {
		ToolbarItem(placement: .topBarLeading) {
			if _isEditMode {
				HStack(spacing: 12) {
					Button("Done") {
						withAnimation {
							_isEditMode = false
							_selectedSources.removeAll()
						}
					}
					Button(action: selectAllSources) {
						Text("Select All")
					}
				}
			} else {
				if !_filteredSources.isEmpty {
					Button("Edit") {
						withAnimation {
							_isEditMode = true
						}
					}
				}
			}
		}

		ToolbarItem(placement: .topBarTrailing) {
			if _isEditMode {
				Button(role: .destructive) {
					if !_selectedSources.isEmpty {
						_showDeleteConfirmation = true
					}
				} label: {
					Image(systemName: "trash")
				}
				.disabled(_selectedSources.isEmpty)
			} else {
				Button {
					_isAddingPresenting = true
				} label: {
					Image(systemName: "plus")
				}
				.disabled(_addingSourceLoading)
			}
		}
	}

	// MARK: - Selection Methods
	private var _deletableSources: [AltSource] {
		_filteredSources.filter { source in
			guard let url = source.sourceURL else { return true }
			return !RyukSignAPI.isPremiumSource(url)
		}
	}

	private func toggleSelection(for source: AltSource) {
		// Don't allow selecting premium sources
		if let url = source.sourceURL, RyukSignAPI.isPremiumSource(url) { return }
		if _selectedSources.contains(source) {
			_selectedSources.remove(source)
		} else {
			_selectedSources.insert(source)
		}
	}

	private var areAllSourcesSelected: Bool {
		let all = Set(_deletableSources)
		return !all.isEmpty && _selectedSources == all
	}

	private func selectAllSources() {
		if areAllSourcesSelected {
			_selectedSources.removeAll()
		} else {
			_selectedSources = Set(_deletableSources)
		}
	}

	private func deleteSelectedSources() {
		withAnimation {
			for source in _selectedSources {
				// Skip premium sources — they can only be removed via Reset Premium
				if let url = source.sourceURL, RyukSignAPI.isPremiumSource(url) {
					continue
				}
				Storage.shared.deleteSource(for: source)
			}
			_selectedSources.removeAll()
			_isEditMode = false
		}
	}

	// MARK: - Navigation Handler
	private func handlePendingNavigation(_ pendingNavigation: AppNavigationManager.PendingAppNavigation?) {
		guard let navigation = pendingNavigation else { return }

		if let activeSource = _activeIndividualSource {
			if let repository = viewModel.sources[activeSource],
			   appExistsInRepository(appId: navigation.appId, repository: repository) {
				// Already in the right source — let it handle scrolling.
				return
			} else {
				_activeIndividualSource = nil

				// Let the source close before opening All Repositories.
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
					self._shouldNavigateToAllRepos = true
				}
				return
			}
		}

		if !_shouldNavigateToAllRepos {
			_shouldNavigateToAllRepos = true
		}
	}

	private func appExistsInRepository(appId: String, repository: ASRepository) -> Bool {
		for app in repository.apps {
			if app.currentUniqueId == appId {
				return true
			}
		}
		return false
	}
}
