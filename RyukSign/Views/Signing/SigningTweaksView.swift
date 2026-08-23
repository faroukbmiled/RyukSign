//
//  SigningTweaksView.swift
//  RyukSign
//
//  Created by samara on 20.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningTweaksView: View {
	@State private var _isAddingPresenting = false
	@State private var _isLibraryPickerPresenting = false

	var app: AppInfoPresentable
	@Binding var options: Options

	/// Non-optional view over `options.tweakInjections`.
	private var _specs: Binding<[TweakInjectionSpec]> {
		Binding(
			get: { options.tweakInjections ?? [] },
			set: { options.tweakInjections = $0 }
		)
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Tweaks")) {
			_librarySection
			_manualSection
			_defaultsSection
		}
		.toolbar {
			NBToolbarButton(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing
			) {
				_isAddingPresenting = true
			}
		}
		.sheet(isPresented: $_isAddingPresenting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.dylib, .deb],
				allowsMultipleSelection: true,
				folder: .tweaks,
				onDocumentsPicked: { urls in
					guard !urls.isEmpty else { return }
					for url in urls {
						FileManager.default.moveAndStore(url, with: "FeatherTweak") { url in
							options.injectionFiles.append(url)
						}
					}
				}
			)
			.ignoresSafeArea()
		}
		.sheet(isPresented: $_isLibraryPickerPresenting) {
			SigningLibraryTweakPicker(existingIds: Set(_specs.wrappedValue.map { $0.id })) { tweak in
				_addFromLibrary(tweak)
			}
		}
		.animation(.smooth, value: options.injectionFiles)
		.animation(.smooth, value: options.tweakInjections)
	}
}

// MARK: - Sections
extension SigningTweaksView {
	@ViewBuilder
	private var _librarySection: some View {
		NBSection(
			.localized("From Library"),
			secondary: _specs.wrappedValue.isEmpty ? nil : "\(_specs.wrappedValue.count)"
		) {
			ForEach(_specs) { $spec in
				_libraryRow(spec: $spec)
			}

			Button {
				_isLibraryPickerPresenting = true
			} label: {
				Label(.localized("Add From Library"), systemImage: "books.vertical")
			}
		} footer: {
			Text(.localized("Tweaks pulled in by auto-inject rules. Tap one to choose exactly where it injects."))
		}
	}

	@ViewBuilder
	private func _libraryRow(spec: Binding<TweakInjectionSpec>) -> some View {
		NavigationLink {
			TweakInjectConfigView(app: app, spec: spec)
		} label: {
			HStack {
				Toggle(isOn: spec.enabled) {
					EmptyView()
				}
				.labelsHidden()

				VStack(alignment: .leading, spacing: 2) {
					Text(spec.wrappedValue.displayName)
						.lineLimit(1)
					Text(_specSummary(spec.wrappedValue))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			Button(role: .destructive) {
				options.tweakInjections?.removeAll { $0.id == spec.wrappedValue.id }
			} label: {
				Label(.localized("Remove"), systemImage: "minus.circle")
			}
		}
	}

	@ViewBuilder
	private var _manualSection: some View {
		NBSection(.localized("Manual Tweaks")) {
			if !options.injectionFiles.isEmpty {
				ForEach(options.injectionFiles, id: \.absoluteString) { tweak in
					_file(tweak: tweak)
				}
			} else {
				Text(verbatim: .localized("No files chosen. Use + to add one just for this sign."))
					.font(.footnote)
					.foregroundColor(.disabled())
			}

			Toggle(isOn: $options.injectIntoExtensions) {
				Label(.localized("Inject Into Extensions"), systemImage: "syringe")
			}
		} footer: {
			Text(.localized("Files added here apply only to this sign. The toggle injects these manual tweaks into every app extension — library tweaks above use their own per-tweak target instead."))
		}
	}

	@ViewBuilder
	private var _defaultsSection: some View {
		NBSection(.localized("Defaults")) {
			SigningOptionsView.picker(
				.localized("Injection Path"),
				systemImage: "doc.badge.gearshape",
				selection: $options.injectPath,
				values: Options.InjectPath.allCases
			)
			SigningOptionsView.picker(
				.localized("Injection Folder"),
				systemImage: "folder.badge.gearshape",
				selection: $options.injectFolder,
				values: Options.InjectFolder.allCases
			)
		} footer: {
			Text(.localized("Default injection path and folder. Library tweaks set to use custom settings override these."))
		}
	}

	@ViewBuilder
	private func _file(tweak: URL) -> some View {
		Label(tweak.lastPathComponent, systemImage: "folder.fill")
			.lineLimit(2)
			.frame(maxWidth: .infinity, alignment: .leading)
			.swipeActions(edge: .trailing, allowsFullSwipe: true) {
				_fileActions(tweak: tweak)
			}
			.contextMenu {
				_fileActions(tweak: tweak)
			}
	}

	@ViewBuilder
	private func _fileActions(tweak: URL) -> some View {
		Button(role: .destructive) {
			FileManager.default.deleteStored(tweak) { url in
				if let index = options.injectionFiles.firstIndex(where: { $0 == url }) {
					options.injectionFiles.remove(at: index)
				}
			}
		} label: {
			Label(.localized("Delete"), systemImage: "trash")
		}
	}

	private func _addFromLibrary(_ tweak: ManagedTweak) {
		guard !(_specs.wrappedValue.contains { $0.id == tweak.id }) else { return }
		let appex = AppExtensionEnumerator.appexNames(for: app)
		guard let spec = TweakManager.shared.injectionSpec(for: tweak, availableAppex: appex) else { return }
		options.tweakInjections = (options.tweakInjections ?? []) + [spec]
	}

	private func _specSummary(_ spec: TweakInjectionSpec) -> String {
		let files = spec.files
		let fileText = files.count == 1
			? files.first?.fileName ?? ""
			: String.localized("%lld files", arguments: files.count)
		let targetings = Set(files.filter { $0.enabled && $0.fileType.isInjectable }.map { _targetingLabel($0.config.targeting) })
		guard let target = targetings.first else { return fileText }
		let targetText = targetings.count == 1 ? target : .localized("mixed targets")
		return "\(fileText) · \(targetText)"
	}

	private func _targetingLabel(_ targeting: ExtensionTargeting) -> String {
		switch targeting {
		case .mainOnly: return .localized("Main app only")
		case .all: return .localized("All extensions")
		case .selected(let names):
			return names.isEmpty
			? .localized("No extensions selected")
			: .localized("%lld extensions", arguments: names.count)
		}
	}
}

// MARK: - Library picker (sign-time)
private struct SigningLibraryTweakPicker: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = TweakManager.shared

	let existingIds: Set<UUID>
	let onPick: (ManagedTweak) -> Void

	@State private var _selection: Set<UUID> = []
	@State private var _query = ""

	private var _available: [ManagedTweak] {
		manager.injectableTweaks
			.filter { !existingIds.contains($0.id) }
			.filter(_matches)
	}

	private func _matches(_ tweak: ManagedTweak) -> Bool {
		let q = _query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return true }
		return tweak.name.localizedCaseInsensitiveContains(q)
			|| (tweak.notes ?? "").localizedCaseInsensitiveContains(q)
	}

	private var _isSearching: Bool { !_query.trimmingCharacters(in: .whitespaces).isEmpty }

	private func _inFolder(_ id: UUID?) -> [ManagedTweak] {
		_available.filter { $0.folderId == id }
	}

	private var _folders: [TweakFolder] {
		manager.folders
			.filter { !_inFolder($0.id).isEmpty }
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	private var _allIds: Set<UUID> { Set(_available.map { $0.id }) }

	var body: some View {
		NBNavigationView(.localized("Add From Library")) {
			Group {
				if manager.injectableTweaks.allSatisfy({ existingIds.contains($0.id) }) {
					NBContentUnavailable(
						.localized("Nothing to Add"),
						systemImage: "books.vertical",
						description: .localized("Every tweak in your library is already added, disabled, or has no files.")
					)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.background(Color(.systemGroupedBackground).ignoresSafeArea())
				} else {
					NBList(.localized("Add From Library")) {
						_pickerContent
					}
					.searchable(text: $_query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(.localized("Search tweaks")))
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button(.localized("Cancel")) { dismiss() }
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button(_selection.isEmpty ? .localized("Add") : String.localized("Add %lld", arguments: _selection.count)) {
						_addSelected()
					}
					.fontWeight(.semibold)
					.disabled(_selection.isEmpty)
				}
				ToolbarItem(placement: .bottomBar) {
					HStack {
						Button(_selection == _allIds && !_allIds.isEmpty ? .localized("Deselect All") : .localized("Select All")) {
							withAnimation(.smooth) {
								_selection = (_selection == _allIds) ? [] : _allIds
							}
						}
						.disabled(_available.isEmpty)
						Spacer()
						Text(verbatim: .localized("%lld selected", arguments: _selection.count))
							.font(.footnote)
							.foregroundStyle(Color.primary.opacity(0.6))
					}
				}
			}
		}
	}

	@ViewBuilder
	private var _pickerContent: some View {
		if _isSearching {
			NBSection(.localized("Results"), secondary: "\(_available.count)") {
				if _available.isEmpty {
					Text(verbatim: .localized("No matches."))
						.font(.footnote)
						.foregroundColor(.disabled())
				} else {
					ForEach(_available) { _row($0) }
				}
			}
		} else {
			ForEach(_folders) { folder in
				let tweaks = _inFolder(folder.id)
				NBSection(folder.name, secondary: "\(tweaks.count)") {
					ForEach(tweaks) { _row($0) }
				}
			}

			let loose = _inFolder(nil)
			NBSection(.localized("Tweaks"), secondary: loose.isEmpty ? nil : "\(loose.count)") {
				if loose.isEmpty {
					Text(verbatim: .localized("Nothing here. Tweaks you add land here unless filed in a folder."))
						.font(.footnote)
						.foregroundColor(.disabled())
				} else {
					ForEach(loose) { _row($0) }
				}
			}
		}
	}

	@ViewBuilder
	private func _row(_ tweak: ManagedTweak) -> some View {
		let isOn = _selection.contains(tweak.id)
		Button {
			if isOn { _selection.remove(tweak.id) } else { _selection.insert(tweak.id) }
		} label: {
			HStack(spacing: 12) {
				Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
				TweakRowLabel(tweak: tweak)
			}
		}
	}

	private func _addSelected() {
		// Preserve library order for a predictable result.
		for tweak in _available where _selection.contains(tweak.id) {
			onPick(tweak)
		}
		dismiss()
	}
}
