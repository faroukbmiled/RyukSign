//
//  SigningOptionsDylibSharedView.swift
//  RyukSign
//
//  Created by samara on 19.04.2025.
//

import SwiftUI
import NimbleViews
import ZsignSwift

// MARK: - View
struct SigningDylibView: View {
	@State private var _dylibs: [String] = []
	@State private var _dylibURLs: [String: URL] = [:]
	@State private var _hiddenDylibCount: Int = 0
	@State private var _query = ""

	var app: AppInfoPresentable
	@Binding var options: Options?

	private var _filteredDylibs: [String] {
		_query.isEmpty ? _dylibs : _dylibs.filter { $0.localizedCaseInsensitiveContains(_query) }
	}

	var body: some View {
		NBList(.localized("Dylibs"), type: .list) {
			Section {
				ForEach(_filteredDylibs, id: \.self) { dylib in
					SigningToggleCellView(
						title: dylib,
						options: $options,
						arrayKeyPath: \.disInjectionFiles,
						fileURL: _dylibURLs[dylib]
					)
				}
			}
			.disabled(options == nil)

			NBSection(.localized("Hidden")) {
				Text(verbatim: .localized("%lld required system dylibs not shown.", arguments: _hiddenDylibCount))
					.font(.footnote)
					.foregroundColor(.disabled())
			}
		}
		.searchable(
			text: $_query,
			placement: .navigationBarDrawer(displayMode: .automatic),
			prompt: Text(.localized("Search Dylibs"))
		)
		.onAppear(perform: _loadDylibs)
	}
}

// MARK: - Extension: View
extension SigningDylibView {
	private func _loadDylibs() {
		guard let path = Storage.shared.getAppDirectory(for: app) else { return }

		let bundle = Bundle(url: path)
		let execPath = path.appendingPathComponent(bundle?.exec ?? "").relativePath

		let allDylibs = Zsign.listDylibs(appExecutable: execPath).map { $0 as String }

		_dylibs = allDylibs.filter { $0.hasPrefix("@rpath") || $0.hasPrefix("@executable_path") }
		_hiddenDylibCount = allDylibs.count - _dylibs.count
		_dylibURLs = _resolveURLs(for: _dylibs, appRoot: path)
	}

	/// `@rpath/X` lives under `Frameworks/`, `@executable_path/X` under the app root anything else is skipped.
	private func _resolveURLs(for dylibs: [String], appRoot: URL) -> [String: URL] {
		var resolved: [String: URL] = [:]
		for dylib in dylibs {
			let candidate: URL
			if dylib.hasPrefix("@rpath/") {
				candidate = appRoot.appendingPathComponent("Frameworks").appendingPathComponent(String(dylib.dropFirst("@rpath/".count)))
			} else if dylib.hasPrefix("@executable_path/") {
				candidate = appRoot.appendingPathComponent(String(dylib.dropFirst("@executable_path/".count)))
			} else {
				continue
			}
			if FileManager.default.fileExists(atPath: candidate.path) {
				resolved[dylib] = candidate
			}
		}
		return resolved
	}
}
