//
//  WebManagerView.swift
//  RyukSign
//
//  Controls the Web Manager server: HTTP upload page + WebDAV mount.
//

import SwiftUI
import NimbleViews
import NimbleExtensions
import CoreImage.CIFilterBuiltins

// MARK: - View
struct WebManagerView: View {
	@ObservedObject private var manager = WebManager.shared

	// MARK: Body
	var body: some View {
		NBList(.localized("Web Manager")) {
			_serverSection
			if manager.isRunning {
				_connectSection
			}
			_settingsSection
			_recentSection
		}
		.dismissableKeyboard()
		.animation(.smooth, value: manager.isRunning)
		.animation(.smooth, value: manager.recentUploads)
	}
}

// MARK: - Sections
extension WebManagerView {
	@ViewBuilder
	private var _serverSection: some View {
		NBSection(.localized("Server")) {
			Toggle(isOn: Binding(
				get: { manager.isRunning },
				set: { _ in manager.toggle() }
			)) {
				Label(.localized("Enable Server"), systemImage: "externaldrive.badge.wifi")
			}

			if let error = manager.lastError {
				Label(error, systemImage: "exclamationmark.triangle")
					.foregroundStyle(.red)
					.font(.footnote)
			}

			if manager.isRunning && !manager.authActive {
				Label(.localized("No password set — anyone on this network can browse, upload and delete your apps and certificates."), systemImage: "lock.open")
					.foregroundStyle(.orange)
					.font(.footnote)
			}
		} footer: {
			Text(.localized("Open it in a browser on your computer to upload files and manage your apps, certificates and tweaks over your local network."))
		}
	}

	@ViewBuilder
	private var _connectSection: some View {
		NBSection(.localized("Connect")) {
			_urlRow(.localized("Browser"), value: manager.httpURL, systemImage: "safari")
			_urlRow(.localized("WebDAV (Finder)"), value: manager.webdavURL, systemImage: "externaldrive.connected.to.line.below")

			HStack {
				Spacer()
				if let qr = QRCode.generate(from: manager.httpURL) {
					Image(uiImage: qr)
						.interpolation(.none)
						.resizable()
						.frame(width: 160, height: 160)
						.padding(8)
						.background(Color.white)
						.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
				Spacer()
			}
			.listRowBackground(EmptyView())
		} footer: {
			Text(.localized("Scan the code to open the Web Manager, or mount the WebDAV address in Finder (Go → Connect to Server) or the Files app."))
		}
	}

	@ViewBuilder
	private func _urlRow(_ title: String, value: String, systemImage: String) -> some View {
		Button {
			UIPasteboard.general.string = value
			Toast.info(.localized("Copied"), systemImage: "doc.on.doc.fill")
		} label: {
			HStack {
				Label(title, systemImage: systemImage)
				Spacer()
				Text(value)
					.font(.footnote)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
				Image(systemName: "doc.on.doc")
					.font(.footnote)
					.foregroundStyle(.tint)
			}
		}
	}

	@ViewBuilder
	private var _settingsSection: some View {
		NBSection(.localized("Settings")) {
			HStack {
				Label(.localized("Port"), systemImage: "number")
				Spacer()
				TextField("8080", text: Binding(
					get: { String(manager.port) },
					set: { manager.port = Int($0.filter(\.isNumber)) ?? manager.port }
				))
				.keyboardType(.numberPad)
				.multilineTextAlignment(.trailing)
				.frame(width: 80)
				.onSubmit { manager.restartIfRunning() }
			}

			Toggle(isOn: Binding(
				get: { manager.requireAuth },
				set: { manager.requireAuth = $0; manager.restartIfRunning() }
			)) {
				Label(.localized("Require Password"), systemImage: "lock")
			}

			if manager.requireAuth {
				HStack {
					Label(.localized("Username"), systemImage: "person")
					Spacer()
					TextField(.localized("Username"), text: Binding(
						get: { manager.username },
						set: { manager.username = $0 }
					))
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.multilineTextAlignment(.trailing)
					.onSubmit { manager.restartIfRunning() }
				}
				HStack {
					Label(.localized("Password"), systemImage: "key")
					Spacer()
					SecureField(.localized("Password"), text: Binding(
						get: { manager.password },
						set: { manager.password = $0 }
					))
					.multilineTextAlignment(.trailing)
					.onSubmit { manager.restartIfRunning() }
				}

				if manager.password.isEmpty {
					Label(.localized("Set a password — until you do, the server stays open to anyone on the network."), systemImage: "exclamationmark.triangle.fill")
						.foregroundStyle(.orange)
						.font(.footnote)
				}
			}
		} footer: {
			Text(.localized("Changing the port or password restarts the server. Traffic is sent over your local network unencrypted, so only run this on a network you trust."))
		}

		NBSection(.localized("Background")) {
			Toggle(isOn: Binding(
				get: { manager.keepAlive },
				set: { manager.keepAlive = $0 }
			)) {
				Label(.localized("Keep Alive"), systemImage: "bolt.badge.clock")
			}
		} footer: {
			Text(.localized("Keeps the server reachable while RyukSign is in the background by playing silent audio. This noticeably increases battery drain — turn it off when you're done transferring."))
		}
	}

	@ViewBuilder
	private var _recentSection: some View {
		if !manager.recentUploads.isEmpty {
			NBSection(.localized("Recent Uploads"), secondary: "\(manager.recentUploads.count)") {
				ForEach(manager.recentUploads, id: \.self) { name in
					Label(name, systemImage: _icon(for: name))
						.lineLimit(1)
				}

				Button(role: .destructive) {
					manager.clearRecent()
				} label: {
					Label(.localized("Clear"), systemImage: "trash")
				}
			}
		}
	}

	private func _icon(for name: String) -> String {
		let n = name.lowercased()
		if n.hasSuffix(".ipa") || n.hasSuffix(".tipa") { return "app.badge" }
		if n.hasSuffix(".dylib") { return "doc.badge.gearshape" }
		if n.hasSuffix(".deb") { return "shippingbox" }
		return "doc"
	}
}

// MARK: - QR
enum QRCode {
	static func generate(from string: String) -> UIImage? {
		let context = CIContext()
		let filter = CIFilter.qrCodeGenerator()
		filter.message = Data(string.utf8)
		filter.correctionLevel = "M"

		guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else {
			return nil
		}
		guard let cg = context.createCGImage(output, from: output.extent) else { return nil }
		return UIImage(cgImage: cg)
	}
}
