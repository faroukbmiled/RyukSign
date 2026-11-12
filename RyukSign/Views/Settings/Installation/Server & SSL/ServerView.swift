//
//  ServerView.swift
//  RyukSign
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import NimbleJSON
import NimbleViews

// MARK: - Extension: Model
extension ServerView {
	struct ServerPackModel: Decodable {
		var cert: String
		var ca: String
		var key: String
		var info: ServerPackInfo
		
		private enum CodingKeys: String, CodingKey {
			case cert, ca, key1, key2, info
		}
		
		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			cert = try container.decode(String.self, forKey: .cert)
			ca = try container.decode(String.self, forKey: .ca)
			let key1 = try container.decode(String.self, forKey: .key1)
			let key2 = try container.decode(String.self, forKey: .key2)
			key = key1 + key2
			info = try container.decode(ServerPackInfo.self, forKey: .info)
		}
		
		struct ServerPackInfo: Decodable {
			var issuer: Domains
			var domains: Domains
		}
		
		struct Domains: Decodable {
			var commonName: String
			
			private enum CodingKeys: String, CodingKey {
				case commonName = "commonName"
			}
		}
	}
}

// MARK: - View
struct ServerView: View {
	@Environment(\.scenePhase) private var _scenePhase
	@AppStorage("Feather.ipFix") private var _ipFix: Bool = false
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@AppStorage(LocalCertificate.enabledKey) private var _useLocalCertificate: Bool = false
	@AppStorage(AppInstaller.detectsRejectionKey) private var _detectsRejection: Bool = true
	@State private var _isTrusted = false
	private let _serverMethods: [String] = [.localized("Fully Local"), .localized("Semi Local")]
	
	// MARK: Body
	var body: some View {
		Group {
			Section {
				Picker(.localized("Server Type"), systemImage: "server.rack", selection: $_serverMethod) {
					ForEach(_serverMethods.indices, id: \.description) { index in
						Text(_serverMethods[index]).tag(index)
					}
				}
				Toggle(.localized("Only use localhost address"), systemImage: "lifepreserver", isOn: $_ipFix)
					.disabled(_serverMethod != 1)
			}
			
			if _serverMethod == 0 {
				_certificateSection
			}

			Section {
				Toggle(.localized("Detect Failed Installs"), systemImage: "exclamationmark.shield", isOn: $_detectsRejection)
			} footer: {
				Text(.localized("Shows an error when iOS rejects an app, like an update signed with a different certificate. Turn it off if installs that worked show as failed."))
			}
		}
		.task(id: _useLocalCertificate) { _refreshTrust() }
		.onChange(of: _scenePhase) { phase in
			if phase == .active { _refreshTrust() }
		}
	}
}

// MARK: - View extension
private extension ServerView {
	var _certificateSection: some View {
		Section {
			Picker(.localized("Certificate"), systemImage: "lock.shield", selection: $_useLocalCertificate) {
				Text(verbatim: "RyukSign").tag(false)
				Text(.localized("On Device")).tag(true)
			}

			if _useLocalCertificate {
				LabeledContent(.localized("Status")) {
					Text(_isTrusted ? .localized("Trusted") : .localized("Not Trusted"))
						.foregroundStyle(_isTrusted ? .green : .orange)
				}
				Button(.localized("Install Profile"), systemImage: "arrow.down.doc") {
					do {
						try LocalCertificateProfileServer.open()
					} catch {
						UIAlertController.showAlertWithOk(title: .localized("Certificate"), message: error.localizedDescription)
					}
				}
			} else {
				Button(.localized("Update SSL Certificates"), systemImage: "arrow.down.doc") {
					FR.downloadSSLCertificates { success in
						DispatchQueue.main.async {
							UIAlertController.showAlertWithOk(
								title: .localized("SSL Certificates"),
								message: success
									? .localized("Certificates updated successfully.")
									: .localized("Failed to download, check your internet connection and try again.")
							)
						}
					}
				}
			}
		} footer: {
			if _useLocalCertificate {
				Text(.localized("After installing the profile, turn on full trust for it in Settings › General › About › Certificate Trust Settings."))
			}
		}
	}

	func _refreshTrust() {
		guard _useLocalCertificate else { return }
		try? LocalCertificate.prepare()
		_isTrusted = LocalCertificate.isTrusted
	}
}
