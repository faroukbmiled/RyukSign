//
//  SigningView.swift
//  RyukSign
//
//  Created by samara on 14.04.2025.
//

import SwiftUI
import PhotosUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct SigningView: View {
	@Environment(\.dismiss) var dismiss
	@StateObject private var _optionsManager = OptionsManager.shared
	
	@State private var _temporaryOptions: Options = OptionsManager.shared.options
	@State private var _temporaryCertificate: Int
	@State private var _isAltPickerPresenting = false
	@State private var _isFilePickerPresenting = false
	@State private var _isImagePickerPresenting = false
	@State private var _isSigning = false
	@State private var _isLogPresenting = false
	@State private var _postSignAction: (() -> Void)? = nil
	@State private var _selectedPhoto: PhotosPickerItem? = nil
	@State var appIcon: UIImage?
	@State private var _displayedDescription: String?
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
				_customizationOptions(for: app)
				_cert()
				_customizationProperties(for: app)
				
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
					_temporaryOptions = OptionsManager.shared.options
					_temporaryOptions.tweakInjections = nil
					_resolveAutoInjectIfNeeded()
					appIcon = nil
				}
			}
			.onAppear { _resolveAutoInjectIfNeeded() }
			.sheet(isPresented: $_isAltPickerPresenting) { SigningAlternativeIconView(app: app, appIcon: $appIcon, isModifing: .constant(true)) }
			.sheet(isPresented: $_isFilePickerPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes:  [.image],
					onDocumentsPicked: { urls in
						guard let selectedFileURL = urls.first else { return }
						self.appIcon = UIImage.fromFile(selectedFileURL)?.resizeToSquare()
					}
				)
				.ignoresSafeArea()
			}
			.photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
			.onChange(of: _selectedPhoto) { newValue in
				guard let newValue else { return }

				Task {
					if let data = try? await newValue.loadTransferable(type: Data.self),
					   let image = UIImage(data: data)?.resizeToSquare() {
						appIcon = image
					}
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
		.onAppear {
			_displayedDescription = app.appDescription

			// ppq protection
			if
				_optionsManager.options.ppqProtection,
				let identifier = app.identifier,
				let cert = _selectedCert(),
				cert.ppQCheck
			{
				var modifiedId = identifier
					.replacingOccurrences(of: "google", with: "ryu", options: .caseInsensitive)
					.replacingOccurrences(of: "facebook", with: "ryu", options: .caseInsensitive)
					.replacingOccurrences(of: "ios", with: "anox", options: .caseInsensitive)

				let dotCount = modifiedId.filter { $0 == "." }.count

				let transformedIdentifier: String
				switch dotCount {
				case 2...:
					if let firstDot = modifiedId.firstIndex(of: ".") {
						let suffix = modifiedId[firstDot...]
						transformedIdentifier = "ryuk" + suffix
					} else {
						transformedIdentifier = "ryuk." + modifiedId
					}
				case 1:
					transformedIdentifier = "ryuk." + modifiedId
				default:
					transformedIdentifier = "ryuk.app." + modifiedId
				}

				_temporaryOptions.appIdentifier = "\(transformedIdentifier).\(_optionsManager.options.ppqString)"
			}
			
			if
				let currentBundleId = app.identifier,
				let newBundleId = _temporaryOptions.identifiers[currentBundleId]
			{
				_temporaryOptions.appIdentifier = newBundleId
			}
			
			if
				let currentName = app.name,
				let newName = _temporaryOptions.displayNames[currentName]
			{
				_temporaryOptions.appName = newName
			}
		}
    }
}

// MARK: - Extension: View
extension SigningView {
	@ViewBuilder
	private func _customizationOptions(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Customization")) {
			Menu {
				Button(.localized("Select Alternative Icon"), systemImage: "app.dashed") { _isAltPickerPresenting = true }
				Button(.localized("Choose from Files"), systemImage: "folder") { _isFilePickerPresenting = true }
				Button(.localized("Choose from Photos"), systemImage: "photo") { _isImagePickerPresenting = true }
			} label: {
				if let icon = appIcon {
					Image(uiImage: icon)
						.appIconStyle()
				} else {
					FRAppIconView(app: app, size: 56)
				}
			}
			
			_infoCell(.localized("Name"), desc: _temporaryOptions.appName ?? app.name) {
				SigningPropertiesView(
					title: .localized("Name"),
					initialValue: _temporaryOptions.appName ?? (app.name ?? ""),
					bindingValue: $_temporaryOptions.appName
				)
			}
			_infoCell(.localized("Identifier"), desc: _temporaryOptions.appIdentifier ?? app.identifier) {
				SigningPropertiesView(
					title: .localized("Identifier"),
					initialValue: _temporaryOptions.appIdentifier ?? (app.identifier ?? ""),
					bindingValue: $_temporaryOptions.appIdentifier,
					suggestion: _provisioningIdentifier()
				)
			}
			_infoCell(.localized("Version"), desc: _temporaryOptions.appVersion ?? app.version) {
				SigningPropertiesView(
					title: .localized("Version"),
					initialValue: _temporaryOptions.appVersion ?? (app.version ?? ""),
					bindingValue: $_temporaryOptions.appVersion
				)
			}
			NavigationLink {
				SigningDescriptionView(
					title: .localized("Description"),
					initialValue: _displayedDescription ?? "",
					onSave: { newValue in
						Storage.shared.updateDescription(for: app, description: newValue)
						_displayedDescription = newValue
					}
				)
			} label: {
				LabeledContent(.localized("Description")) {
					Text(_displayedDescription ?? .localized("None"))
						.lineLimit(1)
				}
			}
			.copyableText(_displayedDescription ?? "")
		}
	}
	
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
	
	@ViewBuilder
	private func _customizationProperties(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Advanced")) {
			NavigationLink {
				SigningTweaksView(
					app: app,
					options: $_temporaryOptions
				)
			} label: {
				Label(.localized("Tweaks"), systemImage: "syringe")
			}
			.badge(_activeInjectionCount)

			DisclosureGroup {
				NavigationLink {
					SigningDylibView(
						app: app,
						options: $_temporaryOptions.optional()
					)
				} label: {
					Label(.localized("Existing Dylibs"), systemImage: "doc.text.magnifyingglass")
				}

				NavigationLink {
					SigningFrameworksView(
						app: app,
						options: $_temporaryOptions.optional()
					)
				} label: {
					Label(.localized("Frameworks & PlugIns"), systemImage: "shippingbox")
				}
				#if NIGHTLY || DEBUG
				NavigationLink {
					SigningEntitlementsView(
						bindingValue: $_temporaryOptions.appEntitlementsFile
					)
				} label: {
					Label(.localized("Entitlements") + " (BETA)", systemImage: "checkmark.seal")
				}
				#endif
			} label: {
				Label(.localized("Modify"), systemImage: "wrench.adjustable")
			}

			NavigationLink {
				Form { SigningOptionsView(
					options: $_temporaryOptions,
					temporaryOptions: _optionsManager.options
				)}
				.navigationTitle(.localized("Properties"))
			} label: {
				Label(.localized("Properties"), systemImage: "slider.horizontal.3")
			}
		}
	}
	
	@ViewBuilder
	private func _infoCell<V: View>(_ title: String, desc: String?, @ViewBuilder destination: () -> V) -> some View {
		NavigationLink {
			destination()
		} label: {
			LabeledContent(title) {
				Text(desc ?? .localized("Unknown"))
			}
		}
	}

}

// MARK: - Extension: Tweak auto-inject
extension SigningView {
	/// Active tweak count for this sign: ad-hoc files + enabled library specs.
	private var _activeInjectionCount: Int {
		_temporaryOptions.injectionFiles.count
		+ (_temporaryOptions.tweakInjections?.filter { $0.enabled }.count ?? 0)
	}

	/// Resolves auto-inject rules from the Tweak Manager into the working options once.
	private func _resolveAutoInjectIfNeeded() {
		guard _temporaryOptions.tweakInjections == nil else { return }
		_temporaryOptions.tweakInjections = _resolveAutoInjectSpecs()
	}

	private func _resolveAutoInjectSpecs() -> [TweakInjectionSpec] {
		let appex = AppExtensionEnumerator.appexNames(for: app)
		return TweakManager.shared.resolveAutoInject(forBundleId: app.identifier)
			.compactMap { TweakManager.shared.injectionSpec(for: $0, availableAppex: appex) }
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
		) { error in
			if let error {
				// Keep the sheet open so the user can fix and retry.
				_isSigning = false
				Toast.error(error.localizedDescription, duration: .sticky)
			} else {
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
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
							NotificationCenter.default.post(name: Notification.Name("Feather.installApp"), object: nil)
						}
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
