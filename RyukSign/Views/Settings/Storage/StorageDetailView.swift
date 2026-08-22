//
//  StorageDetailView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct StorageDetailView: View {
	@ObservedObject private var _manager = StorageManager.shared

	let location: StorageLocation
	let category: StorageCategory

	@AppStorage("Feather.storageSort") private var _sortRaw = ItemSortOption.sizeLargest.rawValue
	@State private var _query = ""
	@State private var _isEditing = false
	@State private var _selection: Set<String> = []
	@State private var _isLoading = true

	init(category: StorageCategory) {
		self.location = .category(category)
		self.category = category
	}

	init(directory: URL, category: StorageCategory) {
		self.location = .directory(directory)
		self.category = category
	}

	private var _sort: ItemSortOption { ItemSortOption(rawValue: _sortRaw) ?? .sizeLargest }
	private var _all: [StorageEntry] { _manager.entries[location] ?? [] }

	private var _entries: [StorageEntry] {
		let query = _query.trimmingCharacters(in: .whitespaces)
		let matched = query.isEmpty
			? _all
			: _all.filter { $0.name.localizedCaseInsensitiveContains(query) }
		return matched.sorted(by: _sort.comparator())
	}

	private var _title: String {
		_isEditing
		? String.localized("%lld Selected", arguments: _selection.count)
		: location.title
	}

	// MARK: Body
	var body: some View {
		NBList(_title, type: .list) {
			if let explanation = _explanation, !_isEditing {
				Section {
					Text(explanation)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}

			Section {
				ForEach(_entries) { entry in
					_row(entry)
				}
			} header: {
				if !_all.isEmpty {
					Text(verbatim: .localized("%lld items · %@", arguments: _all.count, _total.formattedFileSize))
				}
			}
		}
		.searchable(text: $_query)
		.overlay { _empty }
		.toolbar { _toolbar }
		.safeAreaInset(edge: .bottom) { _deleteBar }
		.animation(.snappy, value: _isEditing)
		.task {
			await _manager.refreshEntries(at: location)
			_isLoading = false
		}
	}
}

// MARK: - View extension
@MainActor
private extension StorageDetailView {
	var _explanation: String? {
		if case .category = location { return category.explanation }
		return nil
	}

	var _total: Int64 {
		_all.reduce(0) { $0 + $1.size }
	}

	var _selectableIds: Set<String> {
		Set(_all.filter { !$0.isProtected }.map(\.id))
	}

	@ViewBuilder
	var _empty: some View {
		if _entries.isEmpty {
			NBContentUnavailable(
				_emptyTitle,
				systemImage: _isLoading ? "hourglass" : "checkmark.circle",
				description: _isLoading ? "" : .localized("Nothing to clean up here.")
			)
		}
	}

	var _emptyTitle: String {
		if _isLoading { return .localized("Loading") }
		return _query.isEmpty ? .localized("Empty") : .localized("No Results")
	}

	@ViewBuilder
	func _row(_ entry: StorageEntry) -> some View {
		if _isEditing {
			Button {
				if _selection.contains(entry.id) { _selection.remove(entry.id) }
				else { _selection.insert(entry.id) }
			} label: {
				HStack(spacing: 12) {
					Image(systemName: _selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
						.foregroundStyle(_selection.contains(entry.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
					StorageEntryLabel(entry: entry)
				}
			}
			.disabled(entry.isProtected)
		} else if entry.isDirectory, category.allowsExploring {
			NavigationLink(destination: StorageDetailView(directory: entry.url, category: category)) {
				StorageEntryLabel(entry: entry)
			}
			.swipeActions(edge: .trailing) { _deleteAction(entry) }
		} else {
			StorageEntryLabel(entry: entry)
				.swipeActions(edge: .trailing) { _deleteAction(entry) }
		}
	}

	@ViewBuilder
	func _deleteAction(_ entry: StorageEntry) -> some View {
		if !entry.isProtected {
			Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
				_delete([entry])
			}
		}
	}

	@ToolbarContentBuilder
	var _toolbar: some ToolbarContent {
		if _isEditing {
			ToolbarItem(placement: .topBarLeading) {
				Button(_selection == _selectableIds ? .localized("Deselect All") : .localized("Select All")) {
					_selection = (_selection == _selectableIds) ? [] : _selectableIds
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Done")) { _isEditing = false; _selection.removeAll() }
					.fontWeight(.semibold)
			}
		} else {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					if !_selectableIds.isEmpty {
						Button(.localized("Select")) { _isEditing = true }
					}
					Picker(.localized("Sort By"), selection: $_sortRaw) {
						ForEach(ItemSortOption.allCases) { option in
							Label(option.label, systemImage: option.systemImage).tag(option.rawValue)
						}
					}
				} label: {
					Image(systemName: "line.3.horizontal.decrease")
				}
			}
		}
	}

	@ViewBuilder
	var _deleteBar: some View {
		if _isEditing, !_selection.isEmpty {
			Button(role: .destructive) {
				let picked = _all.filter { _selection.contains($0.id) }
				DestructiveConfirm.present(
					title: .localized("Delete %lld", arguments: picked.count),
					message: (picked.reduce(0) { $0 + $1.size }).formattedFileSize
				) {
					_delete(picked)
					_isEditing = false
				}
			} label: {
				Text(verbatim: .localized("Delete %lld", arguments: _selection.count))
					.fontWeight(.semibold)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 14)
					.background(Color(.secondarySystemGroupedBackground), in: Capsule())
			}
			.padding(.horizontal)
			.padding(.bottom, 8)
			.transition(.move(edge: .bottom).combined(with: .opacity))
		}
	}

	func _delete(_ items: [StorageEntry]) {
		withAnimation {
			_manager.delete(items)
			_selection.subtract(items.map(\.id))
		}
	}
}

// MARK: - View: row
struct StorageEntryLabel: View {
	let entry: StorageEntry

	var body: some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				Text(entry.name)
					.lineLimit(1)
					.truncationMode(.middle)
				if let subtitle = _subtitle {
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Spacer(minLength: 8)

			if entry.isProtected {
				Image(systemName: "lock.fill")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Text(entry.size.formattedFileSize)
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
	}

	private var _subtitle: String? {
		var parts: [String] = []
		if let version = entry.version { parts.append(version) }
		if entry.isDirectory, entry.childCount > 0 {
			parts.append(.localized("%lld items", arguments: entry.childCount))
		}
		if entry.date != .distantPast {
			parts.append(DateFormatter.localizedString(from: entry.date, dateStyle: .medium, timeStyle: .none))
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}
}
