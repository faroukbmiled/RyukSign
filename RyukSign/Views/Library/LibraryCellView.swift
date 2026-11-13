//
//  LibraryCellView.swift
//  RyukSign
//
//  Created by samara on 11.04.2025.
//

import SwiftUI
import NimbleExtensions
import NimbleViews

// MARK: - View
struct LibraryCellView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Environment(\.editMode) private var editMode

	var certInfo: Date.ExpirationInfo? {
		Storage.shared.getCertificate(from: app)?.expiration?.expirationInfo()
	}
	
	var certRevoked: Bool {
		Storage.shared.getCertificate(from: app)?.revoked == true
	}
	
	var app: AppInfoPresentable
	@Binding var selectedInfoAppPresenting: AnyApp?
	@Binding var selectedSigningAppPresenting: AnyApp?
	@Binding var selectedAppUUIDs: Set<String>
	var isHighlighted: Bool = false
	var update: AppUpdate?
	var onUpdate: ((AppUpdate) -> Void)?
	var onSelectMore: (() -> Void)?
	
	// MARK: Selections
	private var _isSelected: Bool {
		guard let uuid = app.uuid else { return false }
		return selectedAppUUIDs.contains(uuid)
	}
	
	private func _toggleSelection() {
		guard let uuid = app.uuid else { return }
		NBHaptic.selection()
		if selectedAppUUIDs.contains(uuid) {
			selectedAppUUIDs.remove(uuid)
		} else {
			selectedAppUUIDs.insert(uuid)
		}
	}
	
	// MARK: Body
	var body: some View {
		let isRegular = horizontalSizeClass != .compact
		let isEditing = editMode?.wrappedValue == .active
		
		HStack(spacing: NBSpacing.row) {
			if isEditing {
				Button {
					_toggleSelection()
				} label: {
					Image(systemName: _isSelected ? "checkmark.circle.fill" : "circle")
						.foregroundColor(_isSelected ? .accentColor : .secondary)
						.font(.title2)
				}
				.buttonStyle(.borderless)
			}
			
			FRAppIconView(app: app, size: 57)
			
			VStack(alignment: .leading, spacing: 4) {
				NBTitleWithSubtitleView(
					title: app.name ?? .localized("Unknown"),
					subtitle: _desc,
					linelimit: 0
				)

				if let update, let onUpdate, !isEditing {
					Button {
						NBHaptic.tap()
						onUpdate(update)
					} label: {
						HStack(spacing: 4) {
							Image(systemName: "arrow.up.circle.fill")
							Text(String.localized("Update to %@", arguments: update.best.version))
						}
						.font(.caption.weight(.semibold))
						.foregroundStyle(Color.accentColor)
						.lineLimit(1)
					}
					.buttonStyle(.borderless)
				}
			}
			
			if !isEditing {
				_buttonActions(for: app)
			}
		}
		.padding(isRegular ? NBSpacing.cellPadding : 0)
		.background(_cellBackground(isRegular: isRegular, isEditing: isEditing))
		.contentShape(Rectangle())
		.onTapGesture {
			if isEditing {
				_toggleSelection()
			}
		}
		.swipeActions {
			if !isEditing {
				_actions(for: app)
			}
		}
		.contextMenu {
			if !isEditing {
				LibraryAppMenu(
					app: app,
					selectedInfoAppPresenting: $selectedInfoAppPresenting,
					selectedSigningAppPresenting: $selectedSigningAppPresenting,
					onUpdate: onUpdate,
					onSelectMore: onSelectMore
				)
			}
		}
	}

	// Single row background so highlight and card share one shape/radius.
	@ViewBuilder
	private func _cellBackground(isRegular: Bool, isEditing: Bool) -> some View {
		let radius = isRegular ? NBRadius.card : NBRadius.medium
		let fill: Color = {
			if isHighlighted { return Color.accentColor.opacity(0.3) }
			if _isSelected && isEditing { return Color.accentColor.opacity(0.1) }
			return isRegular ? Color(.quaternarySystemFill) : .clear
		}()

		RoundedRectangle(cornerRadius: radius, style: .continuous)
			.fill(fill)
			.animation(.easeInOut(duration: 0.3), value: isHighlighted)
	}
	
	private var _desc: String {
		if let version = app.version, let id = app.identifier {
			return "\(version) • \(id)"
		} else {
			return .localized("Unknown")
		}
	}
}

// MARK: - Extension: View
extension LibraryCellView {
	@ViewBuilder
	private func _actions(for app: AppInfoPresentable) -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			Storage.shared.deleteApp(for: app)
		}
	}
	
	@ViewBuilder
	private func _buttonActions(for app: AppInfoPresentable) -> some View {
		Group {
			if app.isSigned {
				Button {
					NBHaptic.tap()
					InstallQueue.shared.enqueue(app)
				} label: {
					FRExpirationPillView(
						title: .localized("Install"),
						revoked: certRevoked,
						expiration: certInfo
					)
				}
			} else {
				Button {
					NBHaptic.tap()
					selectedSigningAppPresenting = AnyApp(base: app)
				} label: {
					FRExpirationPillView(
						title: .localized("Sign"),
						revoked: false,
						expiration: nil
					)
				}
			}
		}
		.buttonStyle(.borderless)
	}
}
