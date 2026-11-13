//
//  LibraryAppMenu.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI

struct LibraryAppMenu: View {
	@ObservedObject private var skippedUpdates = SkippedUpdatesManager.shared
	@ObservedObject private var _updateChecker = AppUpdateChecker.shared

	var app: AppInfoPresentable
	@Binding var selectedInfoAppPresenting: AnyApp?
	@Binding var selectedSigningAppPresenting: AnyApp?
	var onUpdate: ((AppUpdate) -> Void)?
	var onSelectMore: (() -> Void)?

	var body: some View {
		_infoActions
		Divider()
		_appActions
		Divider()
		if let onSelectMore {
			Button(.localized("Select"), systemImage: "checkmark.circle") {
				onSelectMore()
			}
		}
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			Storage.shared.deleteApp(for: app)
		}
	}

	@ViewBuilder
	private var _infoActions: some View {
		Button(.localized("Get Info"), systemImage: "info.circle") {
			Presentation.afterDismiss { selectedInfoAppPresenting = AnyApp(base: app) }
		}

		if let bundleId = app.originalIdentifier ?? app.identifier {
			Button(.localized("View on App Store"), systemImage: "bag") {
				AppStoreHelper.openAppStore(for: bundleId) { result in
					switch result {
					case .success:
						break
					case .failure(let error):
						let alert = UIAlertController(
							title: .localized("App Store"),
							message: error.localizedDescription,
							preferredStyle: .alert
						)
						alert.addAction(UIAlertAction(title: .localized("OK"), style: .default))

						if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
						   let viewController = windowScene.windows.first?.rootViewController {
							viewController.present(alert, animated: true)
						}
					}
				}
			}
		}

		if let update = _updateChecker.update(for: app), let onUpdate {
			Button(String.localized("Update to %@", arguments: update.best.version), systemImage: "arrow.up.circle") {
				Presentation.afterDismiss { onUpdate(update) }
			}
		}

		if let bundleId = app.originalIdentifier ?? app.identifier, _updateChecker.pins[bundleId] != nil {
			Button(.localized("Reset Update Source"), systemImage: "pin.slash") {
				_updateChecker.pin(nil, for: bundleId)
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
	private var _appActions: some View {
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
				Presentation.afterDismiss { selectedSigningAppPresenting = AnyApp(base: app) }
			}
			Button(.localized("Export"), systemImage: "square.and.arrow.up") {
				InstallQueue.shared.enqueue(app, exporting: true)
			}
		} else {
			Button(.localized("Install"), systemImage: "square.and.arrow.down") {
				InstallQueue.shared.enqueue(app)
			}
			Button(.localized("Sign"), systemImage: "signature") {
				Presentation.afterDismiss { selectedSigningAppPresenting = AnyApp(base: app) }
			}
		}
	}
}
