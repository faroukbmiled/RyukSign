//
//  SourcesCellView.swift
//  RyukSign
//
//  Created by samara on 1.05.2025.
//

import SwiftUI
import NimbleViews
import NukeUI

// MARK: - View
struct SourcesCellView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@AppStorage("RyukSign.sourcesShowAppCount") private var _showsAppCount = true
	@ObservedObject private var _viewModel = SourcesViewModel.shared
	@ObservedObject private var _favorites = SourceFavorites.shared

	var source: AltSource
	var isEditMode: Bool = false

	@State private var _isExcluded: Bool = false

	private var _sourceIdentifier: String {
		source.identifier ?? source.sourceURL?.absoluteString ?? ""
	}

	private var _isPremiumSource: Bool {
		guard let url = source.sourceURL else { return false }
		return RyukSignAPI.isPremiumSource(url)
	}

	// MARK: Body
	var body: some View {
		let isRegular = horizontalSizeClass != .compact

		let cellContent = HStack {
			FRIconCellView(
				title: source.name ?? .localized("Unknown"),
				subtitle: _subtitle,
				iconUrl: source.iconURL
			)
			if _isPremiumSource {
				Image(systemName: "crown.fill")
					.foregroundColor(.yellow)
					.font(.caption)
			}
			if _isExcluded {
				Image(systemName: "eye.slash")
					.foregroundColor(.secondary)
					.font(.caption2)
			}
		}
		.padding(isRegular ? 12 : 0)
		.background(
			isRegular
			? RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(Color(.quaternarySystemFill))
			: nil
		)
		.onAppear { _isExcluded = RyukSignAPI.isSourceExcluded(_sourceIdentifier) }

		if isEditMode {
			cellContent
		} else {
			cellContent
				.swipeActions(edge: .leading) {
					_favoriteAction()
				}
				.swipeActions {
					if !_isPremiumSource {
						_actions(for: source)
					}
					_excludeAction()
					_contextActions(for: source)
				}
				.contextMenu {
					_favoriteAction()
					_contextActions(for: source)
					_excludeAction()
					if !_isPremiumSource {
						Divider()
						_actions(for: source)
					}
				}
		}
	}
}

// MARK: - Extension: View
extension SourcesCellView {
	private var _subtitle: String {
		let url = source.sourceURL?.absoluteString ?? ""
		guard _showsAppCount, let count = _viewModel.sources[source]?.apps.count else { return url }
		return .localized("%lld Apps", arguments: count) + " • " + url
	}

	private func _favoriteAction() -> some View {
		let isFavorite = _favorites.contains(source)
		return Button {
			_favorites.toggle(source)
		} label: {
			Label(
				isFavorite ? .localized("Unfavorite") : .localized("Favorite"),
				systemImage: isFavorite ? "star.slash" : "star"
			)
		}
		.tint(.yellow)
	}

	@ViewBuilder
	private func _actions(for source: AltSource) -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			Storage.shared.deleteSource(for: source)
		}
	}

	@ViewBuilder
	private func _contextActions(for source: AltSource) -> some View {
		Button(.localized("Copy"), systemImage: "doc.on.clipboard") {
			UIPasteboard.general.string = source.sourceURL?.absoluteString
		}
	}

	@ViewBuilder
	private func _excludeAction() -> some View {
		Button {
			let newValue = !_isExcluded
			RyukSignAPI.setSourceExcluded(_sourceIdentifier, excluded: newValue)
			_isExcluded = newValue
		} label: {
			Label(
				_isExcluded ? .localized("Show in All") : .localized("Hide from All"),
				systemImage: _isExcluded ? "eye" : "eye.slash"
			)
		}
		.tint(.orange)
	}
}
