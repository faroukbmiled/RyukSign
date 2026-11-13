//
//  SourceUpdatesView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import AltSourceKit
import NimbleViews
import NimbleExtensions

struct UpdateRoute: Identifiable, Hashable {
	let id = UUID()
	let key: String
	let sourceIDs: Set<String>?

	static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
	func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SourceUpdatesView: View {
	@ObservedObject private var _checker = AppUpdateChecker.shared
	@AppStorage(AppUpdateChecker.groupKey) private var _groupsByApp = true

	let updates: [AppUpdate]
	let sort: SourceAppsView.SortOption
	let ascending: Bool
	var onSelect: (AppUpdate) -> Void
	var onOpen: (AppUpdate.Candidate) -> Void

	var body: some View {
		List {
			if _groupsByApp {
				_sections(updates, name: \.name, date: \.best.date) { update in
					if _checker.isAutomatic(update) {
						_candidateRow(update.best, of: update)
					} else {
						AppUpdateRow(update: update, app: _checker.libraryApp(for: update)) {
							onSelect(update)
						}
					}
				}
			} else {
				let rows = updates.flatMap { update in update.candidates.map { (update: update, candidate: $0) } }
				_sections(rows, name: \.candidate.app.currentName, date: \.candidate.date) { row in
					_candidateRow(row.candidate, of: row.update)
				}
			}
		}
		.listStyle(.plain)
	}

	private func _sections<Item, Row: View>(
		_ items: [Item],
		name: (Item) -> String,
		date: (Item) -> Date?,
		@ViewBuilder row: @escaping (Item) -> Row
	) -> some View {
		ForEach(sort.sections(items, ascending: ascending, name: name, date: date)) { section in
			Section {
				ForEach(section.items.indices, id: \.self) { index in
					row(section.items[index])
						.listRowSeparator(.hidden, edges: index == 0 ? .top : [])
				}
			} header: {
				if let title = section.title {
					Text(title)
						.font(.headline)
						.textCase(nil)
				}
			}
		}
	}

	private func _candidateRow(_ candidate: AppUpdate.Candidate, of update: AppUpdate) -> some View {
		SourceAppsCellView(source: candidate.repository, app: candidate.app, subtitle: candidate.subtitle)
			.contentShape(Rectangle())
			.onTapGesture { onOpen(candidate) }
			.contextMenu {
				PinSourceButton(candidate: candidate, key: update.id)
				if update.candidates.count > 1 {
					Button(.localized("Other Sources"), systemImage: "square.stack") {
						onSelect(update)
					}
				}
			}
	}
}

struct AppUpdateRow: View {
	@ObservedObject private var _downloads = DownloadManager.shared

	let update: AppUpdate
	let app: AppInfoPresentable?
	var onSelect: () -> Void

	private var _subtitle: String {
		let sources = String.localized("%lld Sources", arguments: Set(update.candidates.map(\.sourceID)).count)
		return "\(update.installedVersion) → \(update.best.version) • \(sources)"
	}

	var body: some View {
		HStack(spacing: 2) {
			if let app {
				HStack(spacing: 18) {
					FRAppIconView(app: app, size: 56)
					NBTitleWithSubtitleView(title: update.name, subtitle: _subtitle, linelimit: 0)
				}
			} else {
				FRIconCellView(title: update.name, subtitle: _subtitle, iconUrl: update.best.app.iconURL)
			}

			Spacer(minLength: 8)

			if let download = update.candidates.lazy.compactMap({ _downloads.getDownload(by: $0.app.currentUniqueId) }).first {
				DownloadProgressButton(download: download)
			} else {
				UpdateCapsuleButton(action: onSelect)
			}
		}
		.contentShape(Rectangle())
		.onTapGesture(perform: onSelect)
	}
}

struct UpdateCapsuleButton: View {
	var action: () -> Void

	var body: some View {
		Button {
			NBHaptic.tap()
			action()
		} label: {
			Text(.localized("Update"))
				.lineLimit(1)
				.font(.headline.bold())
				.foregroundStyle(.white)
				.padding(.horizontal, 20)
				.padding(.vertical, 6)
				.background(Color.accentColor)
				.clipShape(Capsule())
		}
		.buttonStyle(.borderless)
	}
}

struct PinSourceButton: View {
	@ObservedObject private var _checker = AppUpdateChecker.shared

	let candidate: AppUpdate.Candidate
	let key: String

	var body: some View {
		let isPinned = _checker.isPinned(candidate, for: key)

		Button(
			.localized(isPinned ? "Unpin Source" : "Pin Source"),
			systemImage: isPinned ? "pin.slash" : "pin"
		) {
			NBHaptic.selection()
			_checker.pin(isPinned ? nil : candidate, for: key)
		}
	}
}

struct UpdatePickerView: View {
	@Environment(\.dismiss) private var _dismiss
	@ObservedObject private var _checker = AppUpdateChecker.shared
	@State private var _route: SourceAppsView.SourceAppRoute?
	@State private var _searchText = ""
	@State private var _sort = SourceAppsView.SortOption.saved
	@AppStorage(SourceAppsView.sortAscendingKey) private var _ascending = true

	let route: UpdateRoute

	private var _update: AppUpdate? {
		let update = _checker.updates.first { $0.id == route.key }
		return route.sourceIDs.map { ids in update?.scoped(to: ids) } ?? update
	}

	var body: some View {
		Group {
			if let update = _update {
				_list(update)
					.if(update.candidates.count > 5) {
						$0.searchable(text: $_searchText, placement: .navigationBarDrawer(displayMode: .automatic))
					}
			} else {
				NBContentUnavailable(
					.localized("Up to Date"),
					systemImage: "checkmark.circle",
					description: .localized("No newer version in your sources.")
				) {}
			}
		}
		.navigationTitle(.localized("Update"))
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .primaryAction) {
				Menu {
					SortPicker(selection: $_sort)
					if _sort != .default {
						SortOrderPicker(ascending: $_ascending)
					}
				} label: {
					Image(systemName: "line.3.horizontal.decrease")
				}
			}
		}
		.navigationDestinationIfAvailable(item: $_route) { route in
			SourceAppsDetailView(source: route.source, app: route.app)
		}
	}

	private func _list(_ update: AppUpdate) -> some View {
		let candidates = _searchText.isEmpty ? update.candidates : update.candidates.filter { candidate in
			[candidate.sourceName, candidate.version, candidate.app.currentDescription ?? ""]
				.contains { $0.localizedCaseInsensitiveContains(_searchText) }
		}
		let pinned = candidates.filter { _checker.isPinned($0, for: update.id) }
		let sections = _sort.sections(
			candidates.filter { !_checker.isPinned($0, for: update.id) },
			ascending: _ascending,
			name: \.sourceName,
			date: \.date
		)

		return List {
			HStack(spacing: NBSpacing.row) {
				if let app = _checker.libraryApp(for: update) {
					FRAppIconView(app: app, size: 57)
				}
				NBTitleWithSubtitleView(
					title: update.name,
					subtitle: .localized("Installed %@", arguments: update.installedVersion)
				)
			}
			.listRowSeparator(.hidden, edges: .top)

			if !pinned.isEmpty {
				Section(.localized("Pinned")) {
					ForEach(pinned) { _row($0, key: update.id) }
				}
			}

			ForEach(sections) { section in
				Section {
					ForEach(section.items) { _row($0, key: update.id) }
				} header: {
					Text(section.title ?? .localized("Available"))
						.font(.headline)
						.textCase(nil)
				} footer: {
					if pinned.isEmpty, section.id == sections.last?.id {
						Text(.localized("Pin a source to update from it automatically."))
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.listStyle(.plain)
	}

	private func _row(_ candidate: AppUpdate.Candidate, key: String) -> some View {
		HStack(spacing: 2) {
			FRIconCellView(
				title: candidate.app.currentName,
				subtitle: candidate.subtitle,
				iconUrl: candidate.app.iconURL
			)
			Spacer(minLength: 8)
			UpdateCapsuleButton {
				DownloadManager.shared.startDownload(for: candidate.app)
				_dismiss()
			}
		}
		.contentShape(Rectangle())
		.onTapGesture {
			_route = SourceAppsView.SourceAppRoute(source: candidate.repository, app: candidate.app)
		}
		.swipeActions(edge: .leading) {
			PinSourceButton(candidate: candidate, key: key)
				.tint(.accentColor)
		}
		.contextMenu {
			PinSourceButton(candidate: candidate, key: key)
			Button(.localized("View in Sources"), systemImage: "globe.desk") {
				_dismiss()
				ViewInSources.open(candidate)
			}
		}
	}
}

enum ViewInSources {
	static func open(_ candidate: AppUpdate.Candidate) {
		Presentation.afterDismiss {
			AppNavigationManager.shared.navigateToApp(
				appId: candidate.app.currentUniqueId,
				appName: candidate.app.currentName,
				sourceIdentifier: candidate.sourceID,
				opensDetail: true
			)
		}
	}
}

extension AppUpdate.Candidate {
	var date: Date? { app.currentDate?.date }

	var subtitle: String {
		[version, sourceName, app.currentDescription]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: " • ")
	}
}

struct SortedSection<Item>: Identifiable {
	let title: String?
	var items: [Item]
	var id: String { title ?? "" }
}

extension SourceAppsView.SortOption {
	private static let _dayFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.dateFormat = "MMMM d, yyyy"
		return formatter
	}()

	func sections<Item>(
		_ items: [Item],
		ascending: Bool,
		name: (Item) -> String,
		date: (Item) -> Date?
	) -> [SortedSection<Item>] {
		switch self {
		case .default:
			return items.isEmpty ? [] : [SortedSection(title: nil, items: ascending ? items : items.reversed())]

		case .name:
			let sorted = items.sorted {
				let order = name($0).localizedCaseInsensitiveCompare(name($1))
				return order == (ascending ? .orderedAscending : .orderedDescending)
			}
			var groups: [String: [Item]] = [:]
			var keys: [String] = []
			for item in sorted {
				let first = name(item).trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "#"
				let key = first.range(of: "[A-Z]", options: .regularExpression) != nil ? first : "#"
				if groups[key] == nil { keys.append(key) }
				groups[key, default: []].append(item)
			}
			keys = keys.filter { $0 != "#" } + keys.filter { $0 == "#" }
			return keys.map { SortedSection(title: $0, items: groups[$0] ?? []) }

		case .date:
			let days = Dictionary(grouping: items) { date($0)?.stripTime() ?? .distantPast }
			return days.keys
				.sorted { ascending ? $0 > $1 : $0 < $1 }
				.map { day in
					SortedSection(
						title: Self._dayFormatter.string(from: day),
						items: (days[day] ?? []).sorted { (date($0) ?? .distantPast) > (date($1) ?? .distantPast) }
					)
				}
		}
	}
}
