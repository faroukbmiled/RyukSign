//
//  CertificatesView.swift
//  RyukSign
//
//  Created by samara on 15.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct CertificatesView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	
	@State private var _isAddingPresenting = false
	@State private var _isRenamingPresenting = false
	@State private var _isSelectedInfoPresenting: CertificatePair?
	@State private var _certToRename: CertificatePair?
	@State private var _newNickname: String = ""

	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	private var _bindingSelectedCert: Binding<Int>?
	private var _selectedCertBinding: Binding<Int> {
		_bindingSelectedCert ?? $_storedSelectedCert
	}
	
	init(selectedCert: Binding<Int>? = nil) {
		self._bindingSelectedCert = selectedCert
	}
	
	// MARK: Body
	var body: some View {
		NBGrid {
			ForEach(Array(_certificates.enumerated()), id: \.element.uuid) { index, cert in
				_cellButton(for: cert, at: index)
			}
		}
		.navigationTitle(.localized("Certificates"))
		.overlay {
			if _certificates.isEmpty {
				NBContentUnavailable(
					.localized("No Certificates"),
					systemImage: "questionmark.folder.fill",
					description: .localized("Get started signing by importing your first certificate.")
				) {
					Button {
						_isAddingPresenting = true
					} label: {
						NBButton(.localized("Import"), style: .text)
					}
				}
			}
		}
		.toolbar {
			if _bindingSelectedCert == nil {
				NBToolbarButton(
					systemImage: "plus",
					style: .icon,
					placement: .topBarTrailing
				) {
					_isAddingPresenting = true
				}
			}
		}
		.sheet(item: $_isSelectedInfoPresenting) { cert in
			CertificatesInfoView(cert: cert)
		}
		.sheet(isPresented: $_isAddingPresenting) {
			CertificatesAddView()
				.presentationDetents([.medium])
		}
		.alert(.localized("Change Nickname"), isPresented: $_isRenamingPresenting, presenting: _certToRename) { cert in
			TextField(.localized("Nickname"), text: $_newNickname)
			Button(.localized("Cancel"), role: .cancel) { }
			Button(.localized("OK")) {
				cert.nickname = _newNickname.isEmpty ? nil : _newNickname
				Storage.shared.saveContext()
			}
		}
	}
}

// MARK: - View extension
extension CertificatesView {
	@ViewBuilder
	private func _cellButton(for cert: CertificatePair, at index: Int) -> some View {
		let cornerRadius = NBRadius.large

		Button {
			_selectedCertBinding.wrappedValue = index
		} label: {
			CertificatesCellView(
				cert: cert
			)
			.padding()
			.background(
				RoundedRectangle(cornerRadius: cornerRadius)
					.fill(Color(uiColor: .quaternarySystemFill))
			)
			.overlay(
				RoundedRectangle(cornerRadius: cornerRadius)
					.strokeBorder(
						_selectedCertBinding.wrappedValue == index ? Color.accentColor : Color.clear,
						lineWidth: 2
					)
			)
			.contextMenu {
				_contextActions(for: cert)
				Divider()
				_actions(for: cert)
			}
			.transaction {
				$0.animation = nil
			}
		}
		.buttonStyle(.plain)
	}
	
	@ViewBuilder
	private func _actions(for cert: CertificatePair) -> some View {
		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			Storage.shared.deleteCertificate(for: cert)
		}
	}
	
	@ViewBuilder
	private func _contextActions(for cert: CertificatePair) -> some View {
		Button(.localized("Get Info"), systemImage: "info.circle") {
			_isSelectedInfoPresenting = cert
		}
		Button(.localized("Change Nickname"), systemImage: "pencil") {
			_newNickname = cert.nickname ?? ""
			_certToRename = cert
			_isRenamingPresenting = true
		}
		Button(.localized("Export Certificate"), systemImage: "square.and.arrow.up") {
			if let zip = CertificateExporter.makeZip(for: cert) {
				UIActivityViewController.show(activityItems: [zip])
			} else {
				Toast.error(.localized("Couldn't export certificate"))
			}
		}
		Divider()
		Button(.localized("Check Revokage"), systemImage: "person.text.rectangle") {
			Storage.shared.revokagedCertificate(for: cert)
		}
	}
}
