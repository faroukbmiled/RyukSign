//
//  UpdateAllView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews
import NimbleExtensions

struct UpdateAllView: View {
	@Environment(\.dismiss) private var _dismiss
	@ObservedObject private var _downloads = DownloadManager.shared
	@State private var _choices: [String: AppUpdate.Candidate]
	@State private var _action: AutoSignManager.Action
	@State private var _searchText = ""
	@State private var _route: UpdateRoute?

	let updates: [AppUpdate]
	let sort: SourceAppsView.SortOption
	let ascending: Bool

	private let _actions = AutoSignManager.canSign ? AutoSignManager.Action.allCases : [.keep]

	init(updates: [AppUpdate], sort: SourceAppsView.SortOption, ascending: Bool) {
		self.updates = updates
		self.sort = sort
		self.ascending = ascending

		let checker = AppUpdateChecker.shared
		__choices = State(initialValue: Dictionary(
			updates.filter(checker.isAutomatic).map { ($0.id, $0.best) },
			uniquingKeysWith: { first, _ in first }
		))
		__action = State(initialValue: AutoSignManager.canSign ? .current : .keep)
	}

	private var _sourceIDs: Set<String> {
		Set(updates.flatMap { $0.candidates.map(\.sourceID) })
	}

	private var _pending: [AppUpdate] {
		updates.filter { _downloads.download(for: $0) == nil }
	}

	private var _selected: [AppUpdate.Candidate] {
		_pending.compactMap { _choices[$0.id] }
	}

	private var _visible: [AppUpdate] {
		let matches = _searchText.isEmpty ? updates : updates.filter { $0.name.localizedCaseInsensitiveContains(_searchText) }
		return sort.sections(matches, ascending: ascending, name: \.name, date: { (_choices[$0.id] ?? $0.best).date })
			.flatMap(\.items)
	}

	private var _needsChoice: Bool {
		_pending.contains { _choices[$0.id] == nil && !AppUpdateChecker.shared.isAutomatic($0) }
	}

	var body: some View {
		NBNavigationView(.localized("Update All"), displayMode: .inline) {
			Form {
				NBSection(.localized("Apps"), secondary: "\(_selected.count)/\(_pending.count)") {
					ForEach(_visible) { _row($0) }
				} footer: {
					if _needsChoice {
						Text(.localized("Apps found in more than one source wait until you choose where to update from."))
					}
				}

				NBSection(.localized("When Downloaded")) {
					Picker(.localized("When Downloaded"), selection: $_action) {
						ForEach(_actions, id: \.self) { action in
							Label(action.title, systemImage: action.systemImage).tag(action)
						}
					}
					.pickerStyle(.inline)
					.labelsHidden()
				} footer: {
					if _actions.count == 1 {
						Text(.localized("Signing needs a certificate. Import one in Settings to sign or install right away."))
					} else if _action == .install {
						Text(.localized("Signed apps install one after another in the install window."))
					}
				}

				Rectangle()
					.foregroundStyle(.clear)
					.frame(height: 30)
					.listRowBackground(EmptyView())
			}
			.searchable(text: $_searchText, placement: .navigationBarDrawer(displayMode: .automatic))
			.overlay(alignment: .bottom) { _startButton }
			.toolbar {
				NBToolbarButton(role: .cancel)
				ToolbarItem(placement: .topBarTrailing) {
					let targets = _visible.filter { _downloads.download(for: $0) == nil }
					let isAllSelected = targets.allSatisfy { _choices[$0.id] != nil }
					Button(.localized(isAllSelected ? "Deselect All" : "Select All")) {
						for update in targets {
							_choices[update.id] = isAllSelected ? nil : _choices[update.id] ?? update.best
						}
					}
					.disabled(targets.isEmpty)
				}
			}
			.navigationDestinationIfAvailable(item: $_route) { route in
				UpdatePickerView(route: route, chosenID: _choices[route.key]?.id) { candidate in
					_choices[route.key] = candidate
				}
			}
		}
	}

	private var _startButton: some View {
		VStack(spacing: 0) {
			NBVariableBlurView()
				.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 60 : 80)
				.rotationEffect(.degrees(180))
				.overlay {
					Button(action: _start) {
						NBSheetButton(title: _startTitle, style: _selected.isEmpty ? .standard : .prominent)
							.padding()
					}
					.buttonStyle(.plain)
					.allowsHitTesting(!_selected.isEmpty)
					.offset(y: UIDevice.current.userInterfaceIdiom == .pad ? -20 : -40)
				}
		}
		.ignoresSafeArea(edges: .bottom)
	}

	private var _startTitle: String {
		switch _selected.count {
		case 0: .localized("Select Apps to Update")
		case _pending.count: .localized("Update All")
		default: .localized("Update %lld", arguments: _selected.count)
		}
	}

	private func _row(_ update: AppUpdate) -> some View {
		let download = _downloads.download(for: update)
		let choice = _choices[update.id]
		let isSelected = download == nil && choice != nil

		return HStack(spacing: 12) {
			Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
				.font(.title2)
				.foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.5))

			UpdateIcon(update: update, size: 48)

			VStack(alignment: .leading, spacing: 2) {
				Text(update.name)
					.font(.headline)
					.lineLimit(1)
				Text(verbatim: "\(update.installedVersion) → \((choice ?? update.best).version)")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.lineLimit(1)
				if download == nil {
					_sourceButton(update, choice: choice)
				}
			}

			Spacer(minLength: 8)

			if let download {
				DownloadProgressButton(download: download)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture {
			guard download == nil else { return }
			NBHaptic.selection()
			_choices[update.id] = choice == nil ? update.best : nil
		}
	}

	private func _sourceButton(_ update: AppUpdate, choice: AppUpdate.Candidate?) -> some View {
		Button {
			_route = UpdateRoute(key: update.id, sourceIDs: _sourceIDs)
		} label: {
			HStack(spacing: 3) {
				Text(choice?.sourceName ?? .localized("Choose Source"))
					.lineLimit(1)
				Image(systemName: "chevron.right")
					.font(.caption2.weight(.semibold))
			}
			.font(.footnote.weight(choice == nil ? .semibold : .regular))
			.foregroundStyle(choice == nil ? Color.accentColor : Color.secondary)
		}
		.buttonStyle(.borderless)
	}

	private func _start() {
		guard !_selected.isEmpty else { return }
		NBHaptic.notify(.success)
		for candidate in _selected {
			DownloadManager.shared.startDownload(for: candidate.app, then: _action)
		}
		_dismiss()
	}
}
