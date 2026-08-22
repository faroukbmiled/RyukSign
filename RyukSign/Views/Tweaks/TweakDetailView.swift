//
//  TweakDetailView.swift
//  RyukSign
//
//  Edit a managed tweak: versions, auto-inject rules and injection settings.
//

import SwiftUI
import UIKit
import NimbleViews
import NimbleExtensions

// MARK: - View
struct TweakDetailView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject var manager = TweakManager.shared

	let tweakId: UUID

	@State private var _isAddingVersion = false
	@State private var _isAddingFile = false
	@State private var _isPickingFromLibrary = false
	@State private var _newBundleId = ""
	@State private var _exportURLs: _ExportURLs?
	@State private var _expandedComponents: Set<UUID> = []

	private struct _ExportURLs: Identifiable { let id = UUID(); let urls: [URL] }

	// MARK: Body
	var body: some View {
		Group {
			if let tweak = manager.tweak(tweakId) {
				NBList(tweak.name) {
					_infoSection(tweak)
					_versionsSection(tweak)
					_filesSection(tweak)
					_autoInjectSection(tweak)
					_injectionSettingsSection(tweak)
				}
				.dismissableKeyboard()
			} else {
				// Deleted while open
				Color.clear.onAppear { dismiss() }
			}
		}
		.sheet(isPresented: $_isAddingVersion) {
			FileImporterRepresentableView(
				allowedContentTypes: [.dylib, .deb],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in
					guard !urls.isEmpty else { return }
					let next = (manager.tweak(tweakId)?.versions.count ?? 0) + 1
					if manager.addVersion(to: tweakId, fromFiles: urls, label: "v\(next)") != nil {
						Toast.success(.localized("Version added"), systemImage: "plus.circle.fill")
					}
				}
			)
			.ignoresSafeArea()
		}
		.sheet(isPresented: $_isAddingFile) {
			FileImporterRepresentableView(
				allowedContentTypes: [.dylib, .deb],
				allowsMultipleSelection: true,
				onDocumentsPicked: { urls in
					guard
						!urls.isEmpty,
						let versionId = manager.tweak(tweakId)?.activeVersion?.id
					else { return }
					let added = manager.addComponents(to: tweakId, versionId: versionId, fromFiles: urls)
					if !added.isEmpty {
						Toast.success(.localized("Added %lld files", arguments: added.count), systemImage: "plus.circle.fill")
					}
				}
			)
			.ignoresSafeArea()
		}
		.sheet(isPresented: $_isPickingFromLibrary) {
			AppLibraryPicker { app in
				guard let identifier = app.identifier, !identifier.isEmpty else { return }
				manager.mutate(tweakId) {
					if !$0.autoInjectBundleIds.contains(identifier) {
						$0.autoInjectBundleIds.append(identifier)
					}
				}
			}
		}
		.sheet(item: $_exportURLs) { item in
			DocumentExporterView(urls: item.urls)
				.ignoresSafeArea()
		}
	}

	// MARK: Export helpers

	private func _exportable(_ version: TweakVersion) -> URL? {
		guard
			let tweak = manager.tweak(tweakId),
			let url = manager.exportableURL(for: tweak, version: version)
		else {
			Toast.error(.localized("Couldn't prepare the file"), duration: .long)
			return nil
		}
		return url
	}

	private func _share(_ version: TweakVersion) {
		guard let url = _exportable(version) else { return }
		UIActivityViewController.show(activityItems: [url])
	}

	private func _exportToFiles(_ version: TweakVersion) {
		guard let url = _exportable(version) else { return }
		_exportURLs = _ExportURLs(urls: [url])
	}
}

// MARK: - Sections
extension TweakDetailView {
	@ViewBuilder
	private func _infoSection(_ tweak: ManagedTweak) -> some View {
		NBSection(.localized("Info")) {
			TextField(.localized("Name"), text: Binding(
				get: { tweak.name },
				set: { v in manager.mutate(tweakId) { $0.name = v } }
			))

			TextField(.localized("Notes"), text: Binding(
				get: { tweak.notes ?? "" },
				set: { v in manager.mutate(tweakId) { $0.notes = v.isEmpty ? nil : v } }
			), axis: .vertical)

			Toggle(isOn: Binding(
				get: { tweak.isEnabled },
				set: { v in manager.mutate(tweakId) { $0.isEnabled = v } }
			)) {
				Label(.localized("Enabled"), systemImage: "power")
			}
		}
	}

	@ViewBuilder
	private func _versionsSection(_ tweak: ManagedTweak) -> some View {
		NBSection(.localized("Versions"), secondary: "\(tweak.versions.count)") {
			if tweak.versions.isEmpty {
				Text(verbatim: .localized("No versions."))
					.font(.footnote)
					.foregroundColor(.disabled())
			} else {
				ForEach(tweak.versions.sorted { $0.dateAdded > $1.dateAdded }) { version in
					_versionRow(tweak: tweak, version: version)
				}
			}

			Button {
				_isAddingVersion = true
			} label: {
				Label(.localized("Add Version"), systemImage: "plus")
			}
		}
	}

	@ViewBuilder
	private func _versionRow(tweak: ManagedTweak, version: TweakVersion) -> some View {
		let isActive = tweak.activeVersion?.id == version.id
		Button {
			manager.setSelectedVersion(version.id, for: tweakId)
		} label: {
			HStack(spacing: 12) {
				Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

				VStack(alignment: .leading, spacing: 2) {
					Text(version.label)
						.foregroundStyle(.primary)
					Text(verbatim: "\(version.displaySummary) · \(_size(version.fileSize))")
						.font(.caption)
						.foregroundStyle(Color.primary.opacity(0.6))
						.lineLimit(1)
				}
				Spacer()
				Image(systemName: version.fileType.systemImage)
					.foregroundStyle(.tint)
			}
		}
		.swipeActions(edge: .trailing) {
			Button(role: .destructive) {
				manager.deleteVersion(version.id, from: tweakId)
			} label: {
				Label(.localized("Delete"), systemImage: "trash")
			}
			Button {
				_share(version)
			} label: {
				Label(.localized("Share"), systemImage: "square.and.arrow.up")
			}
			.tint(.blue)
		}
		.contextMenu {
			Button {
				_share(version)
			} label: {
				Label(.localized("Share"), systemImage: "square.and.arrow.up")
			}
			Button {
				_exportToFiles(version)
			} label: {
				Label(.localized("Save to Files"), systemImage: "folder")
			}
		}
	}

	// MARK: Files (components of the active version)

	@ViewBuilder
	private func _filesSection(_ tweak: ManagedTweak) -> some View {
		if let version = tweak.activeVersion {
			NBSection(.localized("Files"), secondary: "\(version.components.count)") {
				ForEach(version.components) { component in
					_componentRow(tweak: tweak, version: version, component: component)
				}
				Button {
					_isAddingFile = true
				} label: {
					Label(.localized("Add File"), systemImage: "plus")
				}
			} footer: {
				Text(.localized("A tweak can bundle several files (e.g. a .deb plus dylibs). Each one can be turned off or given its own injection settings. Add frameworks, bundles and extensions via Extract or Web Manager."))
			}
		}
	}

	@ViewBuilder
	private func _componentRow(tweak: ManagedTweak, version: TweakVersion, component: TweakComponent) -> some View {
		let isInjectable = component.fileType.isInjectable
		DisclosureGroup(isExpanded: _componentExpansion(component.id)) {
			Toggle(isOn: _componentEnabled(version: version, component: component)) {
				Label(.localized("Include When Injecting"), systemImage: "syringe")
			}

			if isInjectable {
				Toggle(isOn: _componentOverride(tweak: tweak, version: version, component: component)) {
					Label(.localized("Custom Settings For This File"), systemImage: "slider.horizontal.3")
				}
				if component.config != nil {
					TweakConfigFields(
						config: _componentConfig(tweak: tweak, version: version, component: component),
						availableExtensions: nil
					)
				}
			}

			// Full analysis on its own screen so it doesn't crowd this list.
			NavigationLink {
				TweakInfoView(
					title: component.fileName,
					fileURL: manager.fileURL(forTweak: tweak.id, version: version, component: component),
					type: component.fileType,
					onApplyRecommendation: isInjectable ? { path, folder in
						manager.mutateComponent(component.id, versionId: version.id, in: tweakId) {
							var config = $0.config ?? tweak.config
							config.useCustom = true
							config.injectPath = path
							config.injectFolder = folder
							$0.config = config
						}
					} : nil,
					currentConfig: component.config ?? tweak.config
				)
			} label: {
				Label(.localized("File Info & Dependencies"), systemImage: "info.circle")
			}

			Button(role: .destructive) {
				manager.deleteComponent(component.id, versionId: version.id, from: tweakId)
			} label: {
				Label(.localized("Remove File"), systemImage: "trash")
			}
		} label: {
			HStack(spacing: 12) {
				Image(systemName: component.fileType.systemImage)
					.foregroundStyle(component.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
					.frame(width: 26)
				VStack(alignment: .leading, spacing: 2) {
					Text(component.fileName)
						.foregroundStyle(component.isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.primary.opacity(0.45)))
						.lineLimit(1)
					Text(verbatim: "\(component.fileType.displayName) · \(_size(component.fileSize))")
						.font(.caption)
						.foregroundStyle(Color.primary.opacity(0.6))
				}
			}
		}
	}

	// MARK: Component bindings

	private func _componentExpansion(_ id: UUID) -> Binding<Bool> {
		Binding(
			get: { _expandedComponents.contains(id) },
			set: { open in
				if open { _expandedComponents.insert(id) } else { _expandedComponents.remove(id) }
			}
		)
	}

	private func _componentEnabled(version: TweakVersion, component: TweakComponent) -> Binding<Bool> {
		Binding(
			get: { component.isEnabled },
			set: { v in manager.mutateComponent(component.id, versionId: version.id, in: tweakId) { $0.isEnabled = v } }
		)
	}

	// On = override the tweak defaults with a config copy; off = inherit.
	private func _componentOverride(tweak: ManagedTweak, version: TweakVersion, component: TweakComponent) -> Binding<Bool> {
		Binding(
			get: { component.config != nil },
			set: { on in
				manager.mutateComponent(component.id, versionId: version.id, in: tweakId) {
					$0.config = on ? ($0.config ?? tweak.config) : nil
				}
			}
		)
	}

	private func _componentConfig(tweak: ManagedTweak, version: TweakVersion, component: TweakComponent) -> Binding<TweakInjectConfig> {
		Binding(
			get: { component.config ?? tweak.config },
			set: { v in manager.mutateComponent(component.id, versionId: version.id, in: tweakId) { $0.config = v } }
		)
	}

	@ViewBuilder
	private func _autoInjectSection(_ tweak: ManagedTweak) -> some View {
		NBSection(.localized("Auto-Inject")) {
			Toggle(isOn: Binding(
				get: { tweak.injectByDefault },
				set: { v in manager.mutate(tweakId) { $0.injectByDefault = v } }
			)) {
				Label(.localized("Inject Into Every App"), systemImage: "infinity")
			}
		} footer: {
			Text(.localized("When on, this tweak is added to every app you sign (still editable per-sign)."))
		}

		NBSection(tweak.injectByDefault ? .localized("Excluded Bundle IDs") : .localized("Bundle ID Rules")) {
			ForEach(tweak.autoInjectBundleIds, id: \.self) { id in
				Text(id)
					.swipeActions(edge: .trailing) {
						Button(role: .destructive) {
							manager.mutate(tweakId) { $0.autoInjectBundleIds.removeAll { $0 == id } }
						} label: {
							Label(.localized("Delete"), systemImage: "trash")
						}
					}
			}

			HStack {
				TextField(.localized("com.example.app"), text: $_newBundleId)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
				Button {
					_addBundleId()
				} label: {
					Image(systemName: "plus.circle.fill")
				}
				.disabled(_newBundleId.trimmingCharacters(in: .whitespaces).isEmpty)
			}

			Button {
				_isPickingFromLibrary = true
			} label: {
				Label(.localized("Choose From Library"), systemImage: "apps.iphone")
			}
		} footer: {
			Text(tweak.injectByDefault
				 ? .localized("Skip auto-inject when signing apps with these bundle identifiers.")
				 : .localized("Auto-inject this tweak when signing apps with these bundle identifiers."))
		}
	}

	@ViewBuilder
	private func _injectionSettingsSection(_ tweak: ManagedTweak) -> some View {
		NBSection(.localized("Default Injection Settings")) {
			TweakConfigFields(
				config: Binding(
					get: { tweak.config },
					set: { v in manager.mutate(tweakId) { $0.config = v } }
				),
				availableExtensions: nil
			)
		} footer: {
			Text(.localized("Used by every file above that doesn't have its own custom settings. Pick the injection path, folder, and which app extensions to inject into."))
		}
	}

	private func _addBundleId() {
		let trimmed = _newBundleId.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return }
		manager.mutate(tweakId) {
			if !$0.autoInjectBundleIds.contains(trimmed) {
				$0.autoInjectBundleIds.append(trimmed)
			}
		}
		_newBundleId = ""
	}

	private func _size(_ bytes: Int64) -> String {
		bytes.formattedFileSize
	}
}
