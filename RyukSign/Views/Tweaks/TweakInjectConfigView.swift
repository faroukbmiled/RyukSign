//
//  TweakInjectConfigView.swift
//  RyukSign
//
//  Per-sign editor for one tweak injection. A tweak can hold several files (e.g. a
//  .deb plus two .dylibs); each file gets its own row with where it lands and which
//  extensions of THIS app it targets (enumerated live).
//

import SwiftUI
import NimbleViews

// MARK: - View
struct TweakInjectConfigView: View {
	var app: AppInfoPresentable
	@Binding var spec: TweakInjectionSpec

	private var _appex: [String] {
		AppExtensionEnumerator.appexNames(for: app)
	}

	private var _appURL: URL? {
		Storage.shared.getAppDirectory(for: app)
	}

	// MARK: Body
	var body: some View {
		NBList(spec.displayName) {
			NBSection(.localized("Injection")) {
				Toggle(isOn: $spec.enabled) {
					Label(.localized("Inject This Tweak"), systemImage: "syringe")
				}
			} footer: {
				Text(.localized("Turn the whole tweak on or off for this sign. Configure each file below."))
			}

			ForEach($spec.files) { $file in
				_fileSection($file)
			}
		}
	}

	// MARK: File section

	@ViewBuilder
	private func _fileSection(_ file: Binding<TweakInjectionFile>) -> some View {
		let type = file.wrappedValue.fileType
		NBSection(file.wrappedValue.fileName) {
			Toggle(isOn: file.enabled) {
				Label(.localized("Include This File"), systemImage: type.systemImage)
			}

			if file.wrappedValue.enabled {
				switch type {
				case .appex:
					Label(.localized("Placed in PlugIns/ and signed with the app."), systemImage: "puzzlepiece.extension")
						.font(.footnote)
						.foregroundStyle(.secondary)
				case .bundle:
					Label(.localized("Copied to the app root — no injection needed."), systemImage: "cube")
						.font(.footnote)
						.foregroundStyle(.secondary)
				default:
					TweakConfigFields(config: file.config, availableExtensions: _appex)
				}

				NavigationLink {
					TweakInfoView(
						title: file.wrappedValue.fileName,
						fileURL: file.wrappedValue.fileURL,
						type: type,
						appURL: _appURL,
						onApplyRecommendation: type.isInjectable ? { path, folder in
							file.config.wrappedValue.useCustom = true
							file.config.wrappedValue.injectPath = path
							file.config.wrappedValue.injectFolder = folder
						} : nil,
						currentConfig: file.config.wrappedValue
					)
				} label: {
					Label(.localized("File Info & Dependencies"), systemImage: "info.circle")
				}
			}
		} footer: {
			Text(verbatim: "\(type.displayName)")
		}
	}
}
