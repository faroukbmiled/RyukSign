//
//  UpdatesSettingsView.swift
//  RyukSign
//
//  Created by Ryuk on 05.07.2026.
//

import SwiftUI
import NimbleViews
import UIKit

struct UpdatesSettingsView: View {
	@ObservedObject private var _manager = SelfUpdateManager.shared
	@AppStorage("Feather.selfUpdateAutoCheck") private var _autoCheck: Bool = true
	@AppStorage("Feather.selfUpdateCertIndex") private var _certIndex: Int = -1
	@AppStorage("Feather.selfUpdateMethod") private var _method: Int = 0

	@State private var _selected: SelfUpdateRelease?

	private let _certificates = Storage.shared.getAllCertificates()

	var body: some View {
		NBList(.localized("Updates")) {
			_statusSection
			_optionsSection
			if !_manager.ignoredVersions.isEmpty { _ignoredSection }
			Section {
				NavigationLink(destination: AllVersionsView()) {
					Label(.localized("All Versions"), systemImage: "square.stack.3d.up")
				}
			}
		}
		.sheet(item: $_selected) { release in
			SelfUpdateSheet(release: release, offersReminders: false)
		}
		.task {
			await _manager.check()
		}
	}

	// MARK: Status

	private var _statusSection: some View {
		NBSection(.localized("Current Version")) {
			HStack {
				Text(.localized("Installed"))
				Spacer()
				Text(Bundle.main.version).foregroundStyle(.secondary)
			}
			if let available = _manager.available {
				HStack {
					Label(String.localized("Update available: %@", arguments: available.version), systemImage: "arrow.up.circle.fill")
						.foregroundStyle(Color.accentColor)
					Spacer()
					Button(.localized("View")) { _selected = available }
						.font(.subheadline.bold())
				}
			} else if let latest = _manager.latest {
				HStack {
					VStack(alignment: .leading, spacing: 2) {
						Text(.localized("Latest Release"))
						Text(latest.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
					}
					Spacer()
					Button(latest.isInstalled ? .localized("Reinstall") : .localized("Install")) { _selected = latest }
						.font(.subheadline.bold())
				}
			}
			Button {
				Task { await _manager.check() }
			} label: {
				HStack {
					Text(.localized("Check for Updates"))
					Spacer()
					if _manager.isChecking { ProgressView() }
				}
			}
			.disabled(_manager.isChecking)
		}
	}

	// MARK: Options

	private var _optionsSection: some View {
		Group {
			NBSection(.localized("Options")) {
				Toggle(.localized("Automatic Update Checks"), isOn: $_autoCheck)
				Picker(.localized("Install Method"), selection: $_method) {
					Text(.localized("Server")).tag(0)
					Text(.localized("IDevice")).tag(1)
				}
				Picker(.localized("Signing Certificate"), selection: $_certIndex) {
					Text(.localized("Selected Certificate")).tag(-1)
					ForEach(Array(_certificates.enumerated()), id: \.offset) { index, cert in
						Text(_certName(cert)).tag(index)
					}
				}
			} footer: {
				VStack(alignment: .leading, spacing: 6) {
					Text(_method == 0
						 ? .localized("Server: your certificate is sent over HTTPS, the update is signed remotely, and iOS installs it. No pairing file needed.")
						 : .localized("IDevice: the update is signed on-device and installed over a pairing file."))
					Text(.localized("Sign with the certificate you first installed RyukSign with, or iOS won't update it in place."))
				}
			}

			if _method == 1 {
				Section {
					Button {
						UIApplication.open("localdevvpn://enable?scheme=feather")
					} label: {
						Label(.localized("Connect to LocalDevVPN"), systemImage: "link")
					}
					Button {
						UIApplication.open("https://apps.apple.com/us/app/localdevvpn/id6755608044")
					} label: {
						Label(.localized("Download LocalDevVPN"), systemImage: "arrow.down.app")
					}
					if !_manager.hasPairing {
						Label(.localized("IDevice updates need a pairing file. Set it up in Installation settings, or switch to Server."), systemImage: "exclamationmark.triangle.fill")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				} footer: {
					Text(.localized("IDevice updates need the loopback VPN connected. Enable LocalDevVPN, then update."))
				}
			} else if !_manager.isServerConfigured {
				Section {
					Label(.localized("The updater server isn't available in this build."), systemImage: "exclamationmark.triangle.fill")
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	// MARK: Ignored

	private var _ignoredSection: some View {
		NBSection(.localized("Ignored Versions")) {
			ForEach(Array(_manager.ignoredVersions).sorted { SelfUpdateManager.compare($0, $1) == .orderedDescending }, id: \.self) { version in
				HStack {
					Text(version)
					Spacer()
					Button(.localized("Resume")) { _manager.unignore(version) }
						.font(.subheadline)
				}
			}
		}
	}

	private func _certName(_ cert: CertificatePair) -> String {
		cert.nickname ?? Storage.shared.getProvisionFileDecoded(for: cert)?.Name ?? .localized("Unknown")
	}
}
