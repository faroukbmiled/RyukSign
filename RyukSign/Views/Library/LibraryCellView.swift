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
	@ObservedObject private var skippedUpdates = SkippedUpdatesManager.shared

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
			
			NBTitleWithSubtitleView(
				title: app.name ?? .localized("Unknown"),
				subtitle: _desc,
				linelimit: 0
			)
			
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
				_contextActions(for: app)
				Divider()
				_contextActionsExtra(for: app)
				Divider()
				if let onSelectMore {
					Button(.localized("Select"), systemImage: "checkmark.circle") {
						onSelectMore()
					}
				}
				_actions(for: app)
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
	private func _contextActions(for app: AppInfoPresentable) -> some View {
		Button(.localized("Get Info"), systemImage: "info.circle") {
			selectedInfoAppPresenting = AnyApp(base: app)
		}

		if let bundleId = app.originalIdentifier ?? app.identifier {
			Button(.localized("View on App Store"), systemImage: "bag") {
				AppStoreHelper.openAppStore(for: bundleId) { result in
					switch result {
					case .success:
						break
					case .failure(let error):
						let alert = UIAlertController(
							title: "App Store Error",
							message: error.localizedDescription,
							preferredStyle: .alert
						)
						alert.addAction(UIAlertAction(title: "OK", style: .default))

						if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
						   let viewController = windowScene.windows.first?.rootViewController {
							viewController.present(alert, animated: true)
						}
					}
				}
			}
		}

		if let bundleId = app.originalIdentifier ?? app.identifier, !bundleId.isEmpty {
			let isIgnored = skippedUpdates.isIgnored(bundleId)
			Button(
				.localized(isIgnored ? "Resume Updates" : "Ignore Updates"),
				systemImage: isIgnored ? "bell" : "bell.slash"
			) {
				SkippedUpdatesManager.shared.toggle(bundleId)
			}
		}
	}
	
	@ViewBuilder
	private func _contextActionsExtra(for app: AppInfoPresentable) -> some View {
		if app.isSigned {
			if let id = app.identifier {
				Button(.localized("Open"), systemImage: "app.badge.checkmark") {
					UIApplication.openApp(with: id)
				}
			}
			Button(.localized("Install"), systemImage: "square.and.arrow.down") {
				InstallQueue.shared.enqueue(app)
			}
			Button(.localized("Re-sign"), systemImage: "signature") {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
			Button(.localized("Export"), systemImage: "square.and.arrow.up") {
				InstallQueue.shared.enqueue(app, exporting: true)
			}
		} else {
			Button(.localized("Install"), systemImage: "square.and.arrow.down") {
				InstallQueue.shared.enqueue(app)
			}
			Button(.localized("Sign"), systemImage: "signature") {
				selectedSigningAppPresenting = AnyApp(base: app)
			}
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
