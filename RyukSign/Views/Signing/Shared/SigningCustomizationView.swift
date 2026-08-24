//
//  SigningCustomizationView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import PhotosUI
import NimbleViews

struct SigningCustomizationView: View {
	@State private var _isAltPickerPresenting = false
	@State private var _isFilePickerPresenting = false
	@State private var _isImagePickerPresenting = false
	@State private var _selectedPhoto: PhotosPickerItem?
	@State private var _displayedDescription: String?

	let app: AppInfoPresentable
	@Binding var options: Options
	@Binding var appIcon: UIImage?
	var identifierSuggestion: String?

	init(
		app: AppInfoPresentable,
		options: Binding<Options>,
		appIcon: Binding<UIImage?>,
		identifierSuggestion: String? = nil
	) {
		self.app = app
		self._options = options
		self._appIcon = appIcon
		self.identifierSuggestion = identifierSuggestion
		__displayedDescription = State(initialValue: app.appDescription)
	}

	// MARK: Body
	var body: some View {
		NBSection(.localized("Customization")) {
			Menu {
				Button(.localized("Select Alternative Icon"), systemImage: "app.dashed") { _isAltPickerPresenting = true }
				Button(.localized("Choose from Files"), systemImage: "folder") { _isFilePickerPresenting = true }
				Button(.localized("Choose from Photos"), systemImage: "photo") { _isImagePickerPresenting = true }
			} label: {
				if let appIcon {
					Image(uiImage: appIcon)
						.appIconStyle()
				} else {
					FRAppIconView(app: app, size: 56)
				}
			}

			_infoCell(.localized("Name"), desc: options.appName ?? app.name) {
				SigningPropertiesView(
					title: .localized("Name"),
					initialValue: options.appName ?? (app.name ?? ""),
					bindingValue: $options.appName
				)
			}
			_infoCell(.localized("Identifier"), desc: options.appIdentifier ?? app.identifier) {
				SigningPropertiesView(
					title: .localized("Identifier"),
					initialValue: options.appIdentifier ?? (app.identifier ?? ""),
					bindingValue: $options.appIdentifier,
					suggestion: identifierSuggestion
				)
			}
			_infoCell(.localized("Version"), desc: options.appVersion ?? app.version) {
				SigningPropertiesView(
					title: .localized("Version"),
					initialValue: options.appVersion ?? (app.version ?? ""),
					bindingValue: $options.appVersion
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
		.sheet(isPresented: $_isAltPickerPresenting) {
			SigningAlternativeIconView(app: app, appIcon: $appIcon, isModifing: .constant(true))
		}
		.sheet(isPresented: $_isFilePickerPresenting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.image],
				folder: .icons,
				onDocumentsPicked: { urls in
					guard let url = urls.first else { return }
					appIcon = UIImage.fromFile(url)?.resizeToSquare()
				}
			)
			.ignoresSafeArea()
		}
		.photosPicker(isPresented: $_isImagePickerPresenting, selection: $_selectedPhoto)
		.onChange(of: _selectedPhoto) { newValue in
			guard let newValue else { return }

			Task {
				if
					let data = try? await newValue.loadTransferable(type: Data.self),
					let image = UIImage(data: data)?.resizeToSquare()
				{
					appIcon = image
				}
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
