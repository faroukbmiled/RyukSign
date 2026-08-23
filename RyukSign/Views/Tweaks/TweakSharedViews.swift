//
//  TweakSharedViews.swift
//  RyukSign
//
//  Reusable controls shared by the Tweak Manager and the per-sign tweak config.
//

import SwiftUI
import NimbleViews
import CoreData

// MARK: - Targeting picker

// Picks extension targeting. With `availableExtensions` (sign time), "Selected" lists the
// real appex names; nil (library level) defers the choice to sign time.
struct TweakTargetingPicker: View {
	@Binding var targeting: ExtensionTargeting
	let availableExtensions: [String]?

	private enum Mode: Int, CaseIterable { case mainOnly, all, selected }

	private var mode: Mode {
		switch targeting {
		case .mainOnly: return .mainOnly
		case .all: return .all
		case .selected: return .selected
		}
	}

	private var selectedNames: [String] {
		if case .selected(let names) = targeting { return names }
		return []
	}

	var body: some View {
		Picker(selection: Binding(
			get: { mode },
			set: { _setMode($0) }
		)) {
			Text(.localized("Main Only")).tag(Mode.mainOnly)
			Text(.localized("All Extensions")).tag(Mode.all)
			Text(.localized("Selected")).tag(Mode.selected)
		} label: {
			Label(.localized("Inject Into"), systemImage: "syringe")
		}
		.pickerStyle(.menu)

		if mode == .selected {
			if let available = availableExtensions {
				if available.isEmpty {
					Text(verbatim: .localized("This app has no extensions."))
						.font(.footnote)
						.foregroundColor(.disabled())
				} else {
					ForEach(available, id: \.self) { name in
						_extensionToggle(name)
					}
				}
			} else {
				Text(verbatim: .localized("You'll choose the extensions when signing an app."))
					.font(.footnote)
					.foregroundColor(.disabled())
			}
		}
	}

	@ViewBuilder
	private func _extensionToggle(_ name: String) -> some View {
		let isOn = selectedNames.contains(name)
		Button {
			var set = selectedNames
			if isOn { set.removeAll { $0 == name } } else { set.append(name) }
			targeting = .selected(set)
		} label: {
			HStack {
				Image(systemName: isOn ? "checkmark.square.fill" : "square")
					.foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
				Text(name).foregroundStyle(.primary)
				Spacer()
			}
		}
	}

	private func _setMode(_ newMode: Mode) {
		switch newMode {
		case .mainOnly: targeting = .mainOnly
		case .all: targeting = .all
		case .selected: targeting = .selected(selectedNames)
		}
	}
}

// MARK: - Injection config fields (shared by library + sign-time editors)

struct TweakConfigFields: View {
	@Binding var config: TweakInjectConfig
	let availableExtensions: [String]?
	// Hide targeting for artifacts that don't inject (e.g. bundles).
	var showTargeting: Bool = true

	var body: some View {
		Toggle(isOn: $config.useCustom) {
			Label(.localized("Use Custom Settings"), systemImage: "slider.horizontal.3")
		}

		if config.useCustom {
			SigningOptionsView.picker(
				.localized("Injection Path"),
				systemImage: "doc.badge.gearshape",
				selection: Binding(
					get: { config.customPath },
					set: { config.injectPath = $0 }
				),
				values: Options.InjectPath.allCases
			)
			SigningOptionsView.picker(
				.localized("Injection Folder"),
				systemImage: "folder.badge.gearshape",
				selection: Binding(
					get: { config.customFolder },
					set: { config.injectFolder = $0 }
				),
				values: Options.InjectFolder.allCases
			)
		}

		if showTargeting {
			TweakTargetingPicker(targeting: $config.targeting, availableExtensions: availableExtensions)
		}
	}
}

// MARK: - Library tweak row (shared by the tab + folder views)

// Tweak row → detail view, with swipe/context actions injected so the owner drives its sheets.
struct TweakLibraryRow: View {
	let tweak: ManagedTweak
	var onShare: () -> Void
	var onExport: () -> Void
	var onMove: () -> Void
	var onDelete: () -> Void

	var body: some View {
		NavigationLink {
			TweakDetailView(tweakId: tweak.id)
		} label: {
			TweakRowLabel(tweak: tweak)
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			Button(role: .destructive, action: onDelete) {
				Label(.localized("Delete"), systemImage: "trash")
			}
			Button(action: onShare) {
				Label(.localized("Share"), systemImage: "square.and.arrow.up")
			}
			.tint(.blue)
		}
		.contextMenu {
			Button(action: onShare) {
				Label(.localized("Share"), systemImage: "square.and.arrow.up")
			}
			Button(action: onExport) {
				Label(.localized("Save to Files"), systemImage: "folder")
			}
			Button(action: onMove) {
				Label(.localized("Move to Folder"), systemImage: "folder")
			}
			Divider()
			Button(role: .destructive, action: onDelete) {
				Label(.localized("Delete"), systemImage: "trash")
			}
		}
	}
}

// MARK: - Folder picker (move target)

// Picks a destination folder; `onPick` gets the folder id (nil = uncategorized).
struct TweakFolderPickerView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = TweakManager.shared

	let currentFolderId: UUID?
	let onPick: (UUID?) -> Void

	@State private var _showNewFolder = false
	@State private var _newFolderName = ""

	var body: some View {
		NBNavigationView(.localized("Move to Folder")) {
			NBList(.localized("Move to Folder")) {
				Section {
					_pickRow(title: .localized("Uncategorized"), systemImage: "tray", folderId: nil)
					ForEach(manager.folders) { folder in
						_pickRow(title: folder.name, systemImage: "folder", folderId: folder.id)
					}
				}
				Section {
					Button {
						_newFolderName = ""
						_showNewFolder = true
					} label: {
						Label(.localized("New Folder"), systemImage: "folder.badge.plus")
					}
				}
			}
			.toolbar { NBToolbarButton(role: .close) }
			.alert(.localized("New Folder"), isPresented: $_showNewFolder) {
				TextField(.localized("Folder Name"), text: $_newFolderName)
				Button(.localized("Cancel"), role: .cancel) {}
				Button(.localized("Create")) {
					let folder = manager.addFolder(name: _newFolderName)
					onPick(folder.id)
					dismiss()
				}
			}
		}
	}

	@ViewBuilder
	private func _pickRow(title: String, systemImage: String, folderId: UUID?) -> some View {
		Button {
			onPick(folderId)
			dismiss()
		} label: {
			HStack(spacing: 12) {
				Image(systemName: systemImage)
					.foregroundStyle(.tint)
					.frame(width: 26)
				Text(title)
					.foregroundStyle(.primary)
				Spacer()
				if folderId == currentFolderId {
					Image(systemName: "checkmark")
						.foregroundStyle(.tint)
				}
			}
		}
	}
}

