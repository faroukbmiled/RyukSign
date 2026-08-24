//
//  BatchSignView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct BatchSignView: View {
	@State private var _options: Options = .batchBase
	@State private var _overrides: [String: Options] = [:]
	@State private var _icons: [String: UIImage] = [:]
	/// Resolving walks each app bundle, so it happens once instead of on every render.
	@State private var _autoInject: [String: [TweakInjectionSpec]] = [:]
	@State private var _selectedCertificate: Int
	@State private var _runner: BatchJobRunner?

	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	let apps: [AppInfoPresentable]
	let mode: BatchJobRunner.Mode

	init(apps: [AppInfoPresentable], mode: BatchJobRunner.Mode) {
		self.apps = apps
		self.mode = mode
		__selectedCertificate = State(initialValue: UserDefaults.standard.integer(forKey: "feather.selectedCert"))

		if mode == .install {
			__runner = State(initialValue: BatchJobRunner(
				apps: apps,
				mode: mode,
				options: .batchBase,
				certificate: nil
			))
		}
	}

	private func _selectedCert() -> CertificatePair? {
		guard _certificates.indices.contains(_selectedCertificate) else { return nil }
		return _certificates[_selectedCertificate]
	}

	// MARK: Body
	var body: some View {
		if let runner = _runner {
			BatchProgressView(runner: runner)
		} else {
			_configuration
		}
	}

	@ViewBuilder
	private var _configuration: some View {
		NBNavigationView("", displayMode: .inline) {
			Form {
				Section {
					_summary
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
				}

				NBSection(.localized("Signing")) {
					if let cert = _selectedCert() {
						NavigationLink {
							CertificatesView(selectedCert: $_selectedCertificate)
						} label: {
							CertificatesCellView(cert: cert)
						}
					} else {
						Text(.localized("No Certificate"))
							.font(.footnote)
							.foregroundColor(.disabled())
					}
				}

				NBSection(.localized("Advanced")) {
					NavigationLink {
						Form { SigningOptionsView(
							options: $_options,
							temporaryOptions: .batchBase
						)}
						.navigationTitle(.localized("Properties"))
					} label: {
						Label(.localized("Properties"), systemImage: "slider.horizontal.3")
					}
				} footer: {
					Text(.localized("These apply to every app in the batch."))
				}

				NBSection(.localized("Apps"), secondary: apps.count.description) {
					ForEach(apps, id: \.uuid) { app in
						_appRow(for: app)
					}
				} footer: {
					Text(.localized("Tap an app to change how it alone is signed."))
				}

				Rectangle()
					.foregroundStyle(.clear)
					.frame(height: 30)
					.listRowBackground(EmptyView())
			}
			.overlay {
				VStack(spacing: 0) {
					Spacer()
					NBVariableBlurView()
						.frame(height: UIDevice.current.userInterfaceIdiom == .pad ? 60 : 80)
						.rotationEffect(.degrees(180))
						.overlay {
							Button(action: _start) {
								NBSheetButton(title: _actionTitle, style: .prominent)
									.padding()
							}
							.buttonStyle(.plain)
							.offset(y: UIDevice.current.userInterfaceIdiom == .pad ? -20 : -40)
						}
				}
				.ignoresSafeArea(edges: .bottom)
			}
			.toolbar {
				NBToolbarButton(role: .cancel)
			}
			.task {
				guard _autoInject.isEmpty else { return }

				for app in apps {
					guard let uuid = app.uuid else { continue }
					_autoInject[uuid] = Options.autoInjectSpecs(for: app)
				}
			}
		}
	}

	// MARK: App rows

	@ViewBuilder
	private func _appRow(for app: AppInfoPresentable) -> some View {
		let resolved = _resolved(for: app)
		let identifier = resolved.appIdentifier ?? app.identifier
		let isRenamed = identifier != app.identifier
		let isCustomized = app.uuid.map { _overrides[$0] != nil } ?? false
		let icon = app.uuid.flatMap { _icons[$0] }

		NavigationLink {
			BatchAppOptionsView(
				app: app,
				identifierSuggestion: _provisioningIdentifier(),
				options: _binding(for: app),
				appIcon: _icon(for: app),
				onReset: { _reset(app) }
			)
		} label: {
			HStack(spacing: NBSpacing.row) {
				if let icon {
					Image(uiImage: icon)
						.appIconStyle(size: 44)
				} else {
					FRAppIconView(app: app, size: 44)
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(resolved.appName ?? app.name ?? .localized("Unknown"))
						.font(.headline)

					if isRenamed, let original = app.identifier {
						Text(original)
							.font(.caption)
							.foregroundStyle(.tertiary)
							.strikethrough()
							.lineLimit(1)
					}

					Text(identifier ?? .localized("Unknown"))
						.font(.caption)
						.foregroundStyle(isRenamed ? Color.accentColor : .secondary)
						.lineLimit(1)
				}
				.frame(maxWidth: .infinity, alignment: .leading)

				if _injectionCount(resolved) > 0 {
					Label(_injectionCount(resolved).description, systemImage: "syringe")
						.font(.caption)
						.foregroundStyle(.secondary)
						.labelStyle(.titleAndIcon)
				}

				if isCustomized {
					Image(systemName: "pencil")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.padding(.vertical, 2)
		}
	}

	private func _resolved(for app: AppInfoPresentable) -> Options {
		guard let uuid = app.uuid else { return _options.resolved(for: app) }

		if let override = _overrides[uuid] {
			return override
		}

		var options = _options
		options.tweakInjections = _autoInject[uuid]
		return options.resolved(for: app)
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

	private func _injectionCount(_ options: Options) -> Int {
		options.injectionFiles.count
		+ (options.tweakInjections?.filter { $0.enabled }.count ?? 0)
	}

	/// Writes only on a real edit, so merely opening an app does not detach it from the shared options.
	private func _binding(for app: AppInfoPresentable) -> Binding<Options> {
		Binding(
			get: { _resolved(for: app) },
			set: { newValue in
				guard let uuid = app.uuid else { return }
				_overrides[uuid] = newValue
			}
		)
	}

	private func _icon(for app: AppInfoPresentable) -> Binding<UIImage?> {
		Binding(
			get: { app.uuid.flatMap { _icons[$0] } },
			set: { newValue in
				guard let uuid = app.uuid else { return }
				_icons[uuid] = newValue
			}
		)
	}

	/// Same as the signing screen's Reset: drops PPQ protection and every edit for this app.
	private func _reset(_ app: AppInfoPresentable) {
		guard let uuid = app.uuid else { return }

		var options = _options
		options.appName = nil
		options.appIdentifier = nil
		options.appVersion = nil
		options.tweakInjections = Options.autoInjectSpecs(for: app)

		_overrides[uuid] = options
		_icons.removeValue(forKey: uuid)
	}

	private var _actionTitle: String {
		mode == .signAndInstall ? .localized("Sign & Install") : .localized("Start Signing")
	}

	// MARK: Summary

	@ViewBuilder
	private var _summary: some View {
		VStack(spacing: 10) {
			HStack(spacing: -14) {
				ForEach(apps.prefix(5), id: \.uuid) { app in
					FRAppIconView(app: app, size: 52)
						.overlay(
							RoundedRectangle(cornerRadius: 12, style: .continuous)
								.stroke(Color(.systemBackground), lineWidth: 2)
						)
				}
			}
			.padding(.top, 8)

			Text(String.localized("Sign %lld Apps", arguments: apps.count))
				.font(.title3.weight(.semibold))
		}
		.frame(maxWidth: .infinity)
	}

	private func _start() {
		guard
			_selectedCert() != nil || _options.signingOption != .default
		else {
			UIAlertController.showAlertWithOk(
				title: .localized("No Certificate"),
				message: .localized("Please go to settings and import a valid certificate"),
				isCancel: true
			)
			return
		}

		NBHaptic.tap()
		_runner = BatchJobRunner(
			apps: apps,
			mode: mode,
			options: _options,
			overrides: _overrides,
			icons: _icons,
			certificate: _selectedCert()
		)
	}
}
