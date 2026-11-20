//
//  CertificatesView.swift
//  RyukSign
//
//  Created by samara on 15.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - View
struct CertificatesView: View {
	@AppStorage("feather.selectedCert") private var _storedSelectedCert: Int = 0
	
	@State private var _isAddingPresenting = false
	@State private var _isRenamingPresenting = false
	@State private var _isSelectedInfoPresenting: CertificatePair?
	@State private var _certToRename: CertificatePair?
	@State private var _newNickname: String = ""
	@State private var _searchText = ""
	@State private var _searchNames: [String: String] = [:]
	@State private var _isReordering = false

	// MARK: Fetch
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: CertificatePair.sortDescriptors,
		animation: .snappy
	) private var _certificates: FetchedResults<CertificatePair>

	private var _bindingSelectedCert: Binding<Int>?
	private var _selectedCertBinding: Binding<Int> {
		_bindingSelectedCert ?? $_storedSelectedCert
	}
	
	init(selectedCert: Binding<Int>? = nil) {
		self._bindingSelectedCert = selectedCert
	}

	private var _isSearchable: Bool { _certificates.count > 5 }

	private var _filteredCertificates: [CertificatePair] {
		let query = _searchText.trimmingCharacters(in: .whitespaces)
		guard !query.isEmpty else { return Array(_certificates) }
		return _certificates.filter { cert in
			[cert.nickname, cert.uuid.flatMap { _searchNames[$0] }]
				.contains { $0?.localizedCaseInsensitiveContains(query) == true }
		}
	}
	
	// MARK: Body
	var body: some View {
		Group {
			if _isReordering {
				List {
					ForEach(_certificates, id: \.uuid) { cert in
						CertificatesCellView(cert: cert)
							.contextMenu { _moveToTopButton(for: cert) }
					}
					.onMove(perform: _move)
				}
				.environment(\.editMode, .constant(.active))
			} else {
				NBGrid {
					ForEach(_filteredCertificates, id: \.uuid) { cert in
						_cellButton(for: cert, at: _certificates.firstIndex(of: cert) ?? -1)
					}
				}
			}
		}
		.navigationTitle(.localized("Certificates"))
		.if(_isSearchable && !_isReordering) {
			$0.searchable(text: $_searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(.localized("Search certificates")))
		}
		.task(id: _certificates.count) {
			guard _isSearchable else { return }
			_searchNames = await _loadSearchNames()
		}
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
			if _certificates.count > 1 {
				NBToolbarButton(
					systemImage: _isReordering ? "checkmark" : "line.3.horizontal",
					style: .icon,
					placement: .topBarTrailing
				) {
					_searchText = ""
					withAnimation(.snappy) { _isReordering.toggle() }
				}
			}
			if _bindingSelectedCert == nil && !_isReordering {
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

	private func _move(from source: IndexSet, to destination: Int) {
		let binding = _selectedCertBinding
		let selected = _certificates.indices.contains(binding.wrappedValue) ? _certificates[binding.wrappedValue] : nil
		let ordered = Storage.shared.moveCertificates(fromOffsets: source, toOffset: destination)
		if let selected, let index = ordered.firstIndex(of: selected) {
			binding.wrappedValue = index
		}
	}

	private func _loadSearchNames() async -> [String: String] {
		let certs = _certificates.compactMap { cert in
			cert.uuid.flatMap { uuid in Storage.shared.getFile(.provision, from: cert).map { (uuid, $0) } }
		}
		return await Task.detached(priority: .utility) {
			var names: [String: String] = [:]
			for (uuid, url) in certs {
				guard let decoded = CertificateReader(url).decoded else { continue }
				names[uuid] = [decoded.Name, decoded.TeamName, decoded.AppIDName].joined(separator: " ")
			}
			return names
		}.value
	}
	
	@ViewBuilder
	private func _moveToTopButton(for cert: CertificatePair) -> some View {
		if let index = _certificates.firstIndex(of: cert), index > 0 {
			Button(.localized("Move to Top"), systemImage: "arrow.up.to.line") {
				withAnimation(.snappy) { _move(from: IndexSet(integer: index), to: 0) }
			}
		}
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
			Presentation.afterDismiss { _isSelectedInfoPresenting = cert }
		}
		Button(.localized("Change Nickname"), systemImage: "pencil") {
			_newNickname = cert.nickname ?? ""
			_certToRename = cert
			Presentation.afterDismiss { _isRenamingPresenting = true }
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
