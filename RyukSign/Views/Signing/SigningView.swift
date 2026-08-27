//
//  SigningView.swift
//  RyukSign
//
//  Created by samara on 14.04.2025.
//

import SwiftUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct SigningView: View {
	@Environment(\.dismiss) var dismiss
	@State private var _temporaryOptions: Options = OptionsManager.shared.options
	@State private var _temporaryCertificate: Int
	@State private var _isSigning = false
	@State private var _isLogPresenting = false
	@State private var _postSignAction: (() -> Void)? = nil
	@State var appIcon: UIImage?
	@AppStorage("RyukSign.autoShowSigningLogs") private var _autoShowLogs: Bool = false

	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var certificates: FetchedResults<CertificatePair>
	
	private func _selectedCert() -> CertificatePair? {
		guard certificates.indices.contains(_temporaryCertificate) else { return nil }
		return certificates[_temporaryCertificate]
	}

	private func _provisioningIdentifier() -> String? {
		guard
			let cert = _selectedCert(),
			let decoded = Storage.shared.getProvisionFileDecoded(for: cert),
			let appId = decoded.Entitlements?["application-identifier"]?.value as? String
		else {
			return nil
		}

		let bundleId = appId.drop { $0 != "." }.dropFirst()
		guard !bundleId.isEmpty, !bundleId.contains("*") else { return nil }
		return String(bundleId)
	}
	
	var app: AppInfoPresentable
	
	init(app: AppInfoPresentable) {
		self.app = app
		let storedCert = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		__temporaryCertificate = State(initialValue: storedCert)
	}
		
	// MARK: Body
    var body: some View {
		NBNavigationView("", displayMode: .inline) {
			Form {
				SigningCustomizationView(
					app: app,
					options: $_temporaryOptions,
					appIcon: $appIcon,
					identifierSuggestion: _provisioningIdentifier()
				)
				_cert()
				SigningAdvancedView(app: app, options: $_temporaryOptions, certificate: _selectedCert())
				
				// horrible
				Rectangle()
					.foregroundStyle(.clear)
					.frame(height: 30)
					.listRowBackground(EmptyView())
			}
			.disabled(_isSigning)
			.animation(.smooth, value: _isSigning)
			.overlay {
				VStack(spacing: 0) {
					Spacer()
					NBVariableBlurView()
						.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 60 : 80)
						.rotationEffect(.degrees(180))
						.overlay {
							Button {
								if _isSigning {
									_isLogPresenting = true
								} else {
									_start()
								}
							} label: {
								NBSheetButton(title: .localized(_isSigning ? "Show Logs" : "Start Signing"), style: .prominent)
									.overlay(alignment: .trailing) {
										if _isSigning {
											ProgressView()
												.progressViewStyle(.circular)
												.tint(.white)
												.padding(.trailing, 28)
												.allowsHitTesting(false)
										}
									}
									.padding()
							}
							.buttonStyle(.plain)
							.offset(y: UIDevice.current.userInterfaceIdiom == .pad ? -20 : -40)
						}
				}
				.ignoresSafeArea(edges: .bottom)
			}

			.toolbar {
				NBToolbarButton(role: .dismiss)
				ToolbarItem(placement: .principal) {
					Image("Glyph")
						.resizable()
						.scaledToFit()
						.frame(height: 38)
						.foregroundStyle(.primary)
				}
				NBToolbarButton(
					.localized("Reset"),
					style: .text,
					placement: .topBarTrailing
				) {
					// Reset drops PPQ protection and every override, back to the app's own identity.
					_temporaryOptions = OptionsManager.shared.options
					_temporaryOptions.resetPerApp(for: app)
					appIcon = nil
				}
			}
			.sheet(isPresented: $_isLogPresenting, onDismiss: {
				_postSignAction?()
				_postSignAction = nil
			}) {
				SigningLogView()
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.visible)
			}
		}
		.onAppear { _temporaryOptions = _temporaryOptions.resolved(for: app) }
		.onDisappear { UIApplication.shared.endEditing() }
    }
}

// MARK: - Extension: View
extension SigningView {
	@ViewBuilder
	private func _cert() -> some View {
		NBSection(.localized("Signing")) {
			if let cert = _selectedCert() {
				NavigationLink {
					CertificatesView(selectedCert: $_temporaryCertificate)
				} label: {
					CertificatesCellView(
						cert: cert
					)
				}
			} else {
				Text(.localized("No Certificate"))
					.font(.footnote)
					.foregroundColor(.disabled())
			}
		}
	}
	
}

// MARK: - Extension: View (import)
extension SigningView {
	private func _start() {
		guard
			_selectedCert() != nil || _temporaryOptions.signingOption != .default
		else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate"),
				isCancel: true
			)
			return
		}

		NBHaptic.tap()
		_isSigning = true
		if _autoShowLogs { _isLogPresenting = true }

		FR.signPackageFile(
			app,
			using: _temporaryOptions,
			icon: appIcon,
			certificate: _selectedCert()
		) { result in
			switch result {
			case .failure(let error):
				// Keep the sheet open so the user can fix and retry.
				_isSigning = false
				Toast.error(error.localizedDescription, duration: .sticky)
			case .success(let signed):
				_isSigning = false
				Toast.success(.localized("Signed successfully"), systemImage: "checkmark.seal.fill")

				let finish = {
					if
						_temporaryOptions.post_deleteAppAfterSigned,
						!app.isSigned
					{
						Storage.shared.deleteApp(for: app)
					}

					if _temporaryOptions.post_installAppAfterSigned {
						InstallQueue.shared.enqueue(signed)
					}

					dismiss()
				}

				// If the user is watching logs, hold the finish until they close the console.
				if _isLogPresenting {
					_postSignAction = finish
				} else {
					finish()
				}
			}
		}
	}
}
