//
//  TweakExtractionView.swift
//  RyukSign
//
//  Lets the user pull tweaks (.dylib/.framework/.bundle/.deb) out of an IPA or an
//  installed Library app, pick which to keep, and import them into the Tweak Manager.
//

import SwiftUI
import NimbleViews
import CoreData

// MARK: - Selection + import

struct TweakExtractionView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = TweakManager.shared

	let candidates: [TweakCandidate]
	// Temp dir to remove when done (IPA scans); nil for in-place library scans.
	let cleanupURL: URL?

	@State private var _selection: Set<UUID> = []
	@State private var _expanded: Set<String> = []
	@State private var _query = ""
	@State private var _seeded = false
	@State private var _showImportConfirm = false
	@State private var _pendingCombine = false
	@State private var _movePrompt: MovePrompt?

	private struct MovePrompt: Identifiable { let id = UUID(); let ids: Set<UUID> }

	// Above this many selected, confirm before importing.
	private let _confirmThreshold = 10

	// Grouped by containing folder, root first then alphabetical.
	private var _groups: [(folder: String, items: [TweakCandidate])] {
		Dictionary(grouping: candidates, by: { $0.folder })
			.map { (folder: $0.key, items: $0.value) }
			.sorted {
				if $0.folder.isEmpty != $1.folder.isEmpty { return $0.folder.isEmpty }
				return $0.folder.localizedCaseInsensitiveCompare($1.folder) == .orderedAscending
			}
	}

	private var _isSearching: Bool { !_query.trimmingCharacters(in: .whitespaces).isEmpty }

	private var _filtered: [TweakCandidate] {
		let q = _query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return [] }
		return candidates.filter {
			$0.name.localizedCaseInsensitiveContains(q)
			|| $0.folder.localizedCaseInsensitiveContains(q)
			|| $0.type.rawValue.localizedCaseInsensitiveContains(q)
		}
	}

	var body: some View {
		NBNavigationView(.localized("Extract Tweaks")) {
			Group {
				if candidates.isEmpty {
					NBContentUnavailable(
						.localized("Nothing Found"),
						systemImage: "magnifyingglass",
						description: .localized("No dylibs, frameworks or bundles were found inside.")
					)
				} else {
					NBList(.localized("Extract Tweaks")) {
						if _isSearching {
							_searchResults
						} else {
							_groupedList
						}
					}
					.searchable(text: $_query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(.localized("Search tweaks")))
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button(.localized("Cancel")) { _finish() }
				}
				if !candidates.isEmpty {
					ToolbarItem(placement: .topBarTrailing) {
						if _selection.count > 1 {
							Menu {
								Button {
									_confirmOrImport(combine: false)
								} label: {
									Label(.localized("Import as Separate Tweaks"), systemImage: "square.on.square")
								}
								Button {
									_confirmOrImport(combine: true)
								} label: {
									Label(.localized("Combine Into One Tweak"), systemImage: "square.stack.3d.down.right")
								}
							} label: {
								Text(.localized("Import")).fontWeight(.semibold)
							}
						} else {
							Button(.localized("Import")) { _confirmOrImport(combine: false) }
								.fontWeight(.semibold)
								.disabled(_selection.isEmpty)
						}
					}
					if !_isSearching && _groups.count > 1 {
						ToolbarItem(placement: .topBarTrailing) {
							Menu {
								Button {
									withAnimation(.smooth) { _expanded = Set(_groups.map { $0.folder }) }
								} label: {
									Label(.localized("Expand All"), systemImage: "chevron.down")
								}
								Button {
									withAnimation(.smooth) { _expanded = [] }
								} label: {
									Label(.localized("Collapse All"), systemImage: "chevron.right")
								}
							} label: {
								Image(systemName: "list.bullet.indent")
							}
						}
					}
					ToolbarItem(placement: .bottomBar) {
						HStack {
							Button(_selection.count == candidates.count ? .localized("Deselect All") : .localized("Select All")) {
								withAnimation(.smooth) {
									if _selection.count == candidates.count { _selection.removeAll() }
									else { _selection = Set(candidates.map { $0.id }) }
								}
							}
							Spacer()
							Text(verbatim: .localized("%lld selected", arguments: _selection.count))
								.font(.footnote)
								.foregroundStyle(Color.primary.opacity(0.6))
						}
					}
				}
			}
		}
		.interactiveDismissDisabled(true)
		.sheet(item: $_movePrompt, onDismiss: { _finish() }) { prompt in
			TweakFolderPickerView(currentFolderId: nil) { target in
				manager.moveTweaks(prompt.ids, toFolder: target)
				if let folder = manager.folder(target) {
					Toast.success(.localized("Moved %lld to %@", arguments: prompt.ids.count, folder.name), systemImage: "folder.fill")
				}
				// Picker dismisses itself; onDismiss runs _finish().
			}
		}
		.alert(.localized("Add Tweaks?"), isPresented: $_showImportConfirm) {
			Button(.localized("Cancel"), role: .cancel) {}
			Button(String.localized("Add %lld", arguments: _selection.count)) { _import(combine: _pendingCombine) }
		} message: {
			Text(verbatim: .localized("You're about to add %lld items to your Tweak Manager. Many of these are usually part of the app, not tweaks.", arguments: _selection.count))
		}
		.onAppear {
			guard !_seeded else { return }
			// Open small folders by default; keep big ones (e.g. the app's Frameworks) collapsed.
			_expanded = Set(_groups.filter { $0.items.count <= 10 }.map { $0.folder })
			_seeded = true
		}
	}

	// MARK: Lists

	private func _expansion(_ folder: String) -> Binding<Bool> {
		Binding(
			get: { _expanded.contains(folder) },
			set: { open in
				withAnimation(.smooth(duration: 0.25)) {
					if open { _expanded.insert(folder) } else { _expanded.remove(folder) }
				}
			}
		)
	}

	@ViewBuilder
	private var _groupedList: some View {
		NBSection(.localized("Found"), secondary: "\(candidates.count)") {
			ForEach(_groups, id: \.folder) { group in
				DisclosureGroup(isExpanded: _expansion(group.folder)) {
					ForEach(group.items) { candidate in
						_row(candidate, showFolder: false)
							.padding(.leading, 4)
					}
				} label: {
					_folderLabel(group)
				}
			}
		} footer: {
			Text(.localized("Tap a folder to expand it, then pick the tweaks to import. Most items here are part of the app — choose only what you need."))
		}
	}

	@ViewBuilder
	private var _searchResults: some View {
		if _filtered.isEmpty {
			NBSection(.localized("Results")) {
				Text(verbatim: .localized("No matches."))
					.font(.footnote)
					.foregroundColor(.disabled())
			}
		} else {
			NBSection(.localized("Results"), secondary: "\(_filtered.count)") {
				ForEach(_filtered) { _row($0, showFolder: true) }
			}
		}
	}

	@ViewBuilder
	private func _folderLabel(_ group: (folder: String, items: [TweakCandidate])) -> some View {
		let selectedInFolder = group.items.filter { _selection.contains($0.id) }.count
		let allSelected = selectedInFolder == group.items.count
		HStack(spacing: 10) {
			Button {
				withAnimation(.smooth) {
					if allSelected { group.items.forEach { _selection.remove($0.id) } }
					else { group.items.forEach { _selection.insert($0.id) } }
				}
			} label: {
				Image(systemName: allSelected ? "checkmark.circle.fill" : (selectedInFolder > 0 ? "minus.circle.fill" : "circle"))
					.font(.system(size: 18))
					.foregroundStyle(selectedInFolder > 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
			}
			.buttonStyle(.plain)

			Image(systemName: _expanded.contains(group.folder) ? "folder.fill" : "folder")
				.foregroundStyle(.tint)
				.frame(width: 24)

			VStack(alignment: .leading, spacing: 1) {
				Text(group.folder.isEmpty ? .localized("Root") : _folderName(group.folder))
					.foregroundStyle(.primary)
					.lineLimit(1)
					.truncationMode(.middle)
				Text(verbatim: _folderSubtitle(count: group.items.count, selected: selectedInFolder))
					.font(.caption2)
					.foregroundStyle(Color.primary.opacity(0.55))
			}
		}
	}

	private func _folderName(_ folder: String) -> String {
		folder.split(separator: "/").last.map(String.init) ?? folder
	}

	private func _folderSubtitle(count: Int, selected: Int) -> String {
		let items = String.localized("%lld items", arguments: count)
		guard selected > 0 else { return items }
		return items + " · " + String.localized("%lld selected", arguments: selected)
	}

	@ViewBuilder
	private func _row(_ candidate: TweakCandidate, showFolder: Bool) -> some View {
		let isOn = _selection.contains(candidate.id)
		Button {
			if isOn { _selection.remove(candidate.id) } else { _selection.insert(candidate.id) }
		} label: {
			HStack(spacing: 12) {
				Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
				Image(systemName: candidate.type.systemImage)
					.foregroundStyle(.tint)
					.frame(width: 26)
				VStack(alignment: .leading, spacing: 2) {
					Text(candidate.name)
						.foregroundStyle(.primary)
						.lineLimit(1)
					Text(verbatim: _subtitle(candidate, showFolder: showFolder))
						.font(.caption)
						.foregroundStyle(Color.primary.opacity(0.6))
						.lineLimit(1)
						.truncationMode(.middle)
				}
				Spacer()
			}
		}
	}

	private func _subtitle(_ candidate: TweakCandidate, showFolder: Bool) -> String {
		let size = candidate.size.formattedFileSize
		if showFolder {
			let folder = candidate.folder.isEmpty ? String.localized("Root") : candidate.folder
			return "\(folder) · \(size)"
		}
		return size
	}

	private func _confirmOrImport(combine: Bool) {
		_pendingCombine = combine
		if _selection.count >= _confirmThreshold {
			_showImportConfirm = true
		} else {
			_import(combine: combine)
		}
	}

	private func _import(combine: Bool) {
		let chosen = candidates.filter { _selection.contains($0.id) }
		guard !chosen.isEmpty else { _finish(); return }

		var addedIds: Set<UUID> = []
		if combine {
			let name = chosen.first?.url.deletingPathExtension().lastPathComponent ?? .localized("Tweak")
			if let tweak = manager.addTweak(name: name, fromFiles: chosen.map { $0.url }) {
				addedIds.insert(tweak.id)
			}
		} else {
			for candidate in chosen {
				if let tweak = manager.addTweak(name: candidate.url.deletingPathExtension().lastPathComponent, from: candidate.url) {
					addedIds.insert(tweak.id)
				}
			}
		}

		guard !addedIds.isEmpty else {
			Toast.error(.localized("Couldn't import tweak"), duration: .sticky)
			_finish()
			return
		}
		let message = combine
			? String.localized("Imported %@", arguments: manager.tweak(addedIds.first!)?.name ?? "")
			: (addedIds.count == 1
				? String.localized("Imported %@", arguments: chosen.first?.name ?? "")
				: String.localized("Imported %lld tweaks", arguments: addedIds.count))
		Toast.success(message, systemImage: "wrench.and.screwdriver.fill")

		// Offer to file the new tweaks if folders exist.
		if !manager.folders.isEmpty {
			_movePrompt = MovePrompt(ids: addedIds)
		} else {
			_finish()
		}
	}

	private func _finish() {
		if let cleanupURL { try? FileManager.default.removeItem(at: cleanupURL) }
		dismiss()
	}
}

// MARK: - IPA extraction loader

// Extracts an IPA off-main, then hands the candidates to TweakExtractionView.
struct TweakIPAExtractView: View {
	@Environment(\.dismiss) private var dismiss

	let ipaURL: URL

	@State private var _phase: Phase = .loading
	@State private var _progress: Double = 0

	private enum Phase {
		case loading
		case done(candidates: [TweakCandidate], workDir: URL)
		case failed(String)
	}

	var body: some View {
		switch _phase {
		case .loading:
			VStack(spacing: 16) {
				if _progress > 0 && _progress < 1 {
					ProgressView(value: _progress)
						.progressViewStyle(.linear)
						.frame(maxWidth: 220)
				} else {
					ProgressView()
				}
				Text(verbatim: .localized("Scanning %@…", arguments: ipaURL.lastPathComponent))
					.font(.callout)
					.foregroundStyle(Color.primary.opacity(0.6))
			}
			.task { await _run() }
		case let .done(candidates, workDir):
			TweakExtractionView(candidates: candidates, cleanupURL: workDir)
		case let .failed(message):
			NBContentUnavailable(
				.localized("Couldn't Read IPA"),
				systemImage: "exclamationmark.triangle",
				description: message
			) {
				Button(.localized("Close")) { dismiss() }
			}
		}
	}

	private func _run() async {
		do {
			let result = try await TweakExtractor.extract(fromIPA: ipaURL) { p in
				DispatchQueue.main.async { _progress = p }
			}
			await MainActor.run { _phase = .done(candidates: result.candidates, workDir: result.workDir) }
		} catch {
			await MainActor.run { _phase = .failed(error.localizedDescription) }
		}
	}
}

// MARK: - Library app picker (for extraction)

struct TweakAppExtractPickerView: View {
	@State private var _scanned: ScannedApp?

	private struct ScannedApp: Identifiable { let id = UUID(); let candidates: [TweakCandidate] }

	var body: some View {
		AppLibraryPicker(showsChevron: true, dismissOnSelect: false) { app in
			_scan(app)
		}
		.sheet(item: $_scanned) { scan in
			TweakExtractionView(candidates: scan.candidates, cleanupURL: nil)
		}
	}

	private func _scan(_ app: AppInfoPresentable) {
		guard let appURL = Storage.shared.getAppDirectory(for: app) else {
			Toast.error(.localized("Couldn't open that app"), duration: .long)
			return
		}
		_scanned = ScannedApp(candidates: TweakExtractor.candidates(inApp: appURL))
	}
}
