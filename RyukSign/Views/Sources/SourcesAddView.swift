//
//  SourcesAddView.swift
//  RyukSign
//
//  Created by samara on 1.05.2025.
//

import SwiftUI
import NimbleViews
import AltSourceKit
import NimbleJSON
import OSLog
import UIKit.UIImpactFeedbackGenerator

// MARK: - View
struct SourcesAddView: View {
	typealias RepositoryDataHandler = Result<ASRepository, Error>
	@Environment(\.dismiss) var dismiss

	let _dataService = NBFetchService()

	@State private var _filteredRecommendedSourcesData: [(url: URL, data: ASRepository)] = []
	func _refreshFilteredRecommendedSourcesData() {
		let filtered = recommendedSourcesData
			.filter { (url, data) in
				let id = data.id ?? url.absoluteString
				return !Storage.shared.sourceExists(id)
			}
			.sorted { lhs, rhs in
				let lhsName = lhs.data.name ?? ""
				let rhsName = rhs.data.name ?? ""
				return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
			}
		_filteredRecommendedSourcesData = filtered
	}

	@State var recommendedSourcesData: [(url: URL, data: ASRepository)] = []
	let recommendedSources: [URL] = [
		"https://raw.githubusercontent.com/claration/Feather/refs/heads/main/app-repo.json",
		"https://raw.githubusercontent.com/Aidoku/Aidoku/altstore/apps.json",
		"https://github.com/chachillie/Flycast-iOS/raw/main/flycast-ios.json",
		"https://xitrix.github.io/iTorrent/AltStore.json",
		"https://altstore.oatmealdome.me/",
		"https://raw.githubusercontent.com/LiveContainer/LiveContainer/refs/heads/main/apps.json",
		"https://pokemmo.com/altstore/",
		"https://provenance-emu.com/apps.json",
		"https://community-apps.sidestore.io/sidecommunity.json",
		"https://alt.getutm.app",
		"https://raw.githubusercontent.com/paigely/Navic/refs/heads/master/app-repo.json",
		"https://stikdebug.xyz/index.json",
		"https://apps.manicemu.site/altstore",
		"https://alt.crystall1ne.dev"
	].map { URL(string: $0)! }

	// MARK: - Ryuk Repos Collection
	@State var ryukRepos: [URL] = []
	@State var ryukReposCount: Int = 0
	@State var ryukReposFetchError: String? = nil

	// MARK: - Premium RyukSign API
	@State var _showPremiumKeyPrompt = false
	@State var _premiumAPIKey = ""
	@State var _isValidatingAPIKey = false
	@State var _showPremiumError = false
	@State var _premiumErrorMessage = ""
	@State var _isPremium = RyukSignAPI.isPremium && !RyukSignAPI.premiumSourceHosts.isEmpty
	@State private var _showResetConfirmation = false
	@State private var _showRestorePrompt = false
	@State private var _showPremiumInfo = false

	@State private var _isImporting = false
	@State var _isAddingRyukRepos = false
	@State private var _isSavingSource = false
	@State private var _sourceURL = ""
	@State private var _showRyukErrorAlert = false

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Add Source"), displayMode: .inline) {
			formContent
				.toolbar { toolbarContent }
				.animation(.default, value: _filteredRecommendedSourcesData.map { $0.data.id ?? "" })
				.alert("Failed to Load Ryuk Repos", isPresented: $_showRyukErrorAlert) {
					Button("OK", role: .cancel) { }
					Button("Retry") {
						Task {
							await _fetchRyukReposList()
						}
					}
				} message: {
					Text(ryukReposFetchError ?? "An unknown error occurred")
				}
				.alert("Premium Access", isPresented: $_showPremiumKeyPrompt) {
					TextField("RYK-XXXX-XXXX-XXXX", text: $_premiumAPIKey)
						.textInputAutocapitalization(.characters)
						.autocorrectionDisabled()
						.font(.system(.body, design: .monospaced))

					Button("Redeem Key") {
						_validatePremiumAPIKey()
					}
					.disabled(_premiumAPIKey.isEmpty || _isValidatingAPIKey)

					Button("Cancel", role: .cancel) {
						_premiumAPIKey = ""
					}
				} message: {
					Text("Enter your RyukSign API key to unlock premium repositories.")
				}
				.alert("Error", isPresented: $_showPremiumError) {
					Button("Contact \(RyukSignAPI.telegramUsername)") {
						RyukSignAPI.openTelegram()
					}
					Button("OK", role: .cancel) { }
				} message: {
					Text(_premiumErrorMessage)
				}
				.alert("Premium RyukSign", isPresented: $_showPremiumInfo) {
					Button("Reset Premium", role: .destructive) {
						_showResetConfirmation = true
					}
					Button("Dismiss", role: .cancel) { }
				} message: {
					Text("Your premium access is active. Premium repositories are protected and cannot be deleted individually. Swipe left or tap Reset to deactivate.")
				}
				.alert("Reset Premium?", isPresented: $_showResetConfirmation) {
					Button("Reset", role: .destructive) {
						_resetPremium()
					}
					Button("Cancel", role: .cancel) { }
				} message: {
					Text("This will remove all RyukSign premium repositories and clear your activation. You will need a new key to reactivate.")
				}
				.alert("Premium Found", isPresented: $_showRestorePrompt) {
					Button("Restore") {
						_restorePremiumFromKeychain()
					}
					Button("No Thanks", role: .destructive) {
						RyukSignAPI.clearPremiumKeychain()
					}
				} message: {
					Text("A previous RyukSign premium activation was found on this device. Would you like to restore your premium repositories?")
				}
				.task {
					// Restore premium state if UserDefaults still has premium hosts (keychain cleared but UserDefaults wasn't).
					if !RyukSignAPI.premiumSourceHosts.isEmpty && !RyukSignAPI.isPremium {
						RyukSignAPI.isPremium = true
						_isPremium = true
					}
					await _fetchRecommendedRepositories()
					await _fetchRyukReposList()
				}
		}
	}

	@AppStorage("Feather.sourcesTabShowAllReposDirectly")
	var _sourcesTabShowAllReposDirectly: Bool = false

	@ViewBuilder
	var formContent: some View {
		Form {
			sourceURLSection
			importExportSection
			premiumRyukSignSection
			ryukReposSection
			displaySection
			featuredSection
		}
		.dismissableKeyboard()
	}

	@ViewBuilder
	var sourceURLSection: some View {
		NBSection(.localized("Source URL")) {
			TextField(.localized("Enter Source URL"), text: $_sourceURL)
				.keyboardType(.URL)
				.textInputAutocapitalization(.never)
		} footer: {
			Text(.localized("The only supported repositories are AltStore repositories."))
			Text(verbatim: "[\(String.localized("Learn more about how to setup a repository..."))](https://faq.altstore.io/developers/make-a-source)")
		}
	}

	@ViewBuilder
	var importExportSection: some View {
		Section {
			Button(.localized("Import"), systemImage: "square.and.arrow.down") {
				_isImporting = true
				_fetchImportedRepositories(UIPasteboard.general.string) { success, count in
					_isImporting = false
					if success {
						Toast.success("Successfully imported \(count) source\(count == 1 ? "" : "s")")
					} else {
						Toast.error("No valid sources found in clipboard", duration: .sticky)
					}
				}
			}

			Button(.localized("Export"), systemImage: "doc.on.doc") {
				let sources = Storage.shared.getSources()
				if sources.isEmpty {
					Toast.error("No sources to export", duration: .sticky)
				} else {
					UIPasteboard.general.string = sources.map {
						$0.sourceURL!.absoluteString
					}.joined(separator: "\n")
					Toast.success("Successfully exported \(sources.count) source\(sources.count == 1 ? "" : "s") to clipboard")
				}
			}
		} footer: {
			Text(.localized("Supports importing from KravaSign/MapleSign and ESign."))
		}
	}

	@ViewBuilder
	var premiumRyukSignSection: some View {
		Section {
			if _isPremium {
				// Already premium — tap for info, swipe left for reset
				Button(action: {
					_showPremiumInfo = true
				}) {
					HStack {
						Image(systemName: "crown.fill")
							.foregroundColor(.yellow)
						VStack(alignment: .leading, spacing: 2) {
							Text("Premium RyukSign")
								.font(.headline)
								.foregroundColor(.primary)
							Text("Premium activated")
								.font(.caption)
								.foregroundColor(.green)
						}
						Spacer()
						Image(systemName: "checkmark.seal.fill")
							.foregroundColor(.green)
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(PlainButtonStyle())
				.swipeActions(edge: .trailing) {
					Button("Reset", role: .destructive) {
						_showResetConfirmation = true
					}
				}
			} else {
				Button(action: {
					// Check for reinstall recovery (keychain has premium but UserDefaults wiped)
					if RyukSignAPI.hasKeychainPremiumButNotLocal {
						_showRestorePrompt = true
					} else {
						_premiumAPIKey = ""
						_showPremiumKeyPrompt = true
					}
				}) {
					HStack {
						Image(systemName: "crown.fill")
							.foregroundColor(.yellow)
						VStack(alignment: .leading, spacing: 2) {
							Text("Premium RyukSign")
								.font(.headline)
								.foregroundColor(.primary)
							Text("Redeem API key for premium repos")
								.font(.caption)
								.foregroundColor(.secondary)
						}
						Spacer()
						if _isValidatingAPIKey {
							ProgressView()
								.scaleEffect(0.8)
						} else {
							Image(systemName: "key.fill")
								.foregroundColor(.secondary)
								.font(.caption)
						}
					}
					.contentShape(Rectangle())
				}
				.buttonStyle(PlainButtonStyle())
				.disabled(_isValidatingAPIKey)
			}

			Button(action: {
				RyukSignAPI.openTelegram()
			}) {
				HStack {
					Image(systemName: "paperplane.fill")
						.foregroundColor(.blue)
					VStack(alignment: .leading, spacing: 2) {
						Text("Get a Key")
							.font(.headline)
							.foregroundColor(.primary)
						Text("\(RyukSignAPI.contactSuffix)")
							.font(.caption)
							.foregroundColor(.secondary)
					}
					Spacer()
					Image(systemName: "arrow.up.right")
						.foregroundColor(.secondary)
						.font(.caption)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(PlainButtonStyle())
		} footer: {
			if _isPremium {
				Text("Swipe left to reset. Premium repos cannot be deleted individually.")
			} else {
				Text("API keys are single-use.")
			}
		}
	}

	@ViewBuilder
	var ryukReposSection: some View {
		Section {
			Button(action: {
				if ryukRepos.isEmpty {
					Task {
						await _fetchRyukReposList()
						if !ryukRepos.isEmpty {
							_isAddingRyukRepos = true
							_addRyukRepos()
						}
					}
				} else {
					_isAddingRyukRepos = true
					_addRyukRepos()
				}
			}) {
				HStack {
					Image(systemName: "bolt.fill")
						.foregroundColor(.orange)
					VStack(alignment: .leading, spacing: 2) {
						Text("Ryuk Repos")
							.font(.headline)
							.foregroundColor(.primary)
						if ryukReposCount > 0 {
							Text("Add \(ryukReposCount) Ryuk crafted repositories")
								.font(.caption)
								.foregroundColor(.secondary)
						} else if ryukReposFetchError != nil {
							Text("Tap to retry loading repositories")
								.font(.caption)
								.foregroundColor(.red)
						} else {
							Text("Loading repositories...")
								.font(.caption)
								.foregroundColor(.secondary)
						}
					}
					Spacer()
					if _isAddingRyukRepos || (ryukReposCount == 0 && ryukReposFetchError == nil) {
						ProgressView()
							.scaleEffect(0.8)
					} else if ryukReposFetchError != nil {
						Image(systemName: "exclamationmark.triangle")
							.foregroundColor(.red)
							.font(.caption)
					} else {
						Image(systemName: "chevron.right")
							.foregroundColor(.secondary)
							.font(.caption)
					}
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(PlainButtonStyle())
			.disabled(_isPremium || _isAddingRyukRepos || (ryukReposCount == 0 && ryukReposFetchError == nil))
			.opacity(_isPremium ? 0.4 : 1.0)
		} footer: {
			if _isPremium {
				Text("Already included in your premium repositories.")
			} else if let error = ryukReposFetchError {
				Text(error)
					.foregroundColor(.red)
			} else {
				Text("Add a collection of popular repositories crafted by Ryuk.")
			}
		}
	}

	@ViewBuilder
	var displaySection: some View {
		Section {
			Toggle(isOn: $_sourcesTabShowAllReposDirectly) {
				Label(.localized("Show All Repos by Default"), systemImage: "square.stack")
			}
		} footer: {
			Text(.localized("When enabled, the Sources tab shows all apps directly. Toggle off to manage sources."))
		}
	}

	@ViewBuilder
	var featuredSection: some View {
		if !_filteredRecommendedSourcesData.isEmpty {
			NBSection(.localized("Featured")) {
				ForEach(_filteredRecommendedSourcesData, id: \.url) { (url, source) in
					HStack(spacing: 2) {
						FRIconCellView(
							title: source.name ?? .localized("Unknown"),
							subtitle: url.absoluteString,
							iconUrl: source.currentIconURL
						)
						Button {
							Storage.shared.addSource(url, repository: source) { error in
								_refreshFilteredRecommendedSourcesData()
								if let error = error {
									Toast.error(error.localizedDescription, duration: .sticky)
								} else {
									let sourceName = source.name ?? "Repository"
									Toast.success("Successfully added \(sourceName)")
								}
							}
						} label: {
							NBButton(.localized("Add"), systemImage: "arrow.down", style: .text)
						}
					}
				}
			} footer: {
				Text(.localized("Open an [issue](https://github.com/claration/Feather/issues) on GitHub if you want your source to be featured."))
			}
		}
	}

	@ToolbarContentBuilder
	var toolbarContent: some ToolbarContent {
		NBToolbarButton(role: .cancel)

		if !_isImporting && !_isAddingRyukRepos && !_isSavingSource {
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .confirmationAction
			) {
				if _sourceURL.isEmpty {
					dismiss()
					return
				}

				_isSavingSource = true
				FR.handleSource(_sourceURL, showAlerts: false) { result in
					_isSavingSource = false
					switch result {
					case .success(let sourceName):
						Toast.success("Successfully added \(sourceName)")
						dismiss()
					case .failure(let error):
						Toast.error(error.localizedDescription, duration: .sticky)
					}
				}
			}
		} else {
			ToolbarItem(placement: .confirmationAction) {
				ProgressView()
			}
		}
	}

}
