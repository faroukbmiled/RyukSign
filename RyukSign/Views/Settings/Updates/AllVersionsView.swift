//
//  AllVersionsView.swift
//  RyukSign
//
//  Created by Ryuk on 05.07.2026.
//

import SwiftUI
import NimbleViews

struct AllVersionsView: View {
	private enum Filter: Int { case all, stable, beta }

	@ObservedObject private var _manager = SelfUpdateManager.shared

	@State private var _releases: [SelfUpdateRelease] = []
	@State private var _page = 1
	@State private var _canLoadMore = true
	@State private var _isLoadingPage = false
	@State private var _loadError: String?
	@State private var _search = ""
	@State private var _selected: SelfUpdateRelease?
	@State private var _newestFirst = true
	@State private var _filter: Filter = .all

	private var _filtered: [SelfUpdateRelease] {
		var list = _releases
		switch _filter {
		case .stable: list = list.filter { !$0.isPrerelease }
		case .beta: list = list.filter { $0.isPrerelease }
		case .all: break
		}
		if !_search.isEmpty {
			list = list.filter {
				$0.version.localizedCaseInsensitiveContains(_search) ||
				$0.title.localizedCaseInsensitiveContains(_search)
			}
		}
		if !_newestFirst {
			list = list.sorted { ($0.publishedAt ?? .distantPast) < ($1.publishedAt ?? .distantPast) }
		}
		return list
	}

	var body: some View {
		NBList(.localized("All Versions"), type: .list) {
			ForEach(_filtered) { release in
				Button { _selected = release } label: { _row(release) }
					.tint(.primary)
					.listRowBackground(release.isInstalled ? Color.accentColor.opacity(0.12) : nil)
					.onAppear {
						if release.id == _filtered.last?.id { Task { await _loadNextPage() } }
					}
			}
			if _isLoadingPage {
				HStack { Spacer(); ProgressView(); Spacer() }
			}
		}
		.overlay { _overlay }
		.searchable(text: $_search, placement: .navigationBarDrawer(displayMode: .always))
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Picker(.localized("Sort"), selection: $_newestFirst) {
						Text(.localized("Newest First")).tag(true)
						Text(.localized("Oldest First")).tag(false)
					}
					Picker(.localized("Show"), selection: $_filter) {
						Text(.localized("All")).tag(Filter.all)
						Text(.localized("Stable")).tag(Filter.stable)
						Text(.localized("Beta")).tag(Filter.beta)
					}
				} label: {
					Image(systemName: "line.3.horizontal.decrease")
				}
			}
		}
		.sheet(item: $_selected) { release in
			SelfUpdateSheet(release: release, offersReminders: false)
		}
		.task {
			if _releases.isEmpty { await _loadNextPage() }
		}
	}

	@ViewBuilder
	private var _overlay: some View {
		if _releases.isEmpty {
			if _isLoadingPage {
				ProgressView()
			} else if let error = _loadError {
				NBContentUnavailable(.localized("Couldn't Load Versions"), systemImage: "wifi.slash", description: error)
			}
		} else if _filtered.isEmpty {
			NBContentUnavailable(.localized("No Results"), systemImage: "magnifyingglass", description: .localized("No versions match your filters."))
		}
	}

	private func _row(_ release: SelfUpdateRelease) -> some View {
		HStack(spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					Text(release.version).font(.body.weight(.medium))
					if release.id == _manager.latest?.id {
						_pill(.localized("Latest"), color: .accentColor)
					}
					if release.isPrerelease {
						_pill(.localized("Beta"), color: .orange)
					}
				}
				if let date = release.publishedAt {
					Text(date.formatted(date: .abbreviated, time: .omitted))
						.font(.caption).foregroundStyle(.secondary)
				}
			}
			Spacer()
			_badge(release)
		}
	}

	private func _pill(_ text: String, color: Color) -> some View {
		Text(text)
			.font(.caption2.bold())
			.foregroundStyle(color)
			.padding(.horizontal, 5).padding(.vertical, 1)
			.background(color.opacity(0.15)).clipShape(Capsule())
	}

	@ViewBuilder
	private func _badge(_ release: SelfUpdateRelease) -> some View {
		let cmp = SelfUpdateManager.compare(release.version, Bundle.main.version)
		if cmp == .orderedSame {
			Label(.localized("Installed"), systemImage: "checkmark.circle.fill")
				.labelStyle(.titleAndIcon)
				.font(.caption.bold())
				.foregroundStyle(Color.accentColor)
		} else if cmp == .orderedDescending {
			Image(systemName: "arrow.up.circle.fill").foregroundStyle(Color.accentColor)
		} else {
			Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
		}
	}

	private func _loadNextPage() async {
		guard _canLoadMore, !_isLoadingPage else { return }
		_isLoadingPage = true
		defer { _isLoadingPage = false }
		do {
			let batch = try await _manager.fetchReleases(page: _page)
			let existing = Set(_releases.map(\.id))
			_releases.append(contentsOf: batch.filter { !existing.contains($0.id) })
			_canLoadMore = !batch.isEmpty
			_page += 1
			_loadError = nil
		} catch {
			_loadError = error.localizedDescription
			_canLoadMore = false
		}
	}
}
