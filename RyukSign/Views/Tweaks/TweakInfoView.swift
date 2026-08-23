//
//  TweakInfoView.swift
//  RyukSign
//
//  The "Tweak Info" screen: inspects one tweak file and shows what it is, where it goes,
//  what it links against, whether anything it needs is missing, and offers a one-tap
//  "use recommended injection settings". Pushed from the Files list so it never crowds it.
//

import SwiftUI
import NimbleViews

// MARK: - Loader

// Owns the off-main analysis as a @StateObject so it survives view rebuilds — a `.task`
// gets cancelled on parent re-render, leaving the box stuck on "Analyzing…".
@MainActor
final class TweakAnalysisLoader: ObservableObject {
	@Published var analysis: TweakAnalysis?
	@Published var loading = false
	private var _loadedKey: URL?

	func load(fileURL: URL, type: TweakFileType, appURL: URL?) {
		guard _loadedKey != fileURL else { return } // already loaded / loading this file
		_loadedKey = fileURL
		loading = true
		analysis = nil
		Task { [weak self] in
			let result = await Task.detached(priority: .userInitiated) {
				await TweakAnalyzer.analyze(fileURL: fileURL, type: type, appURL: appURL)
			}.value
			guard let self, self._loadedKey == fileURL else { return }
			self.analysis = result
			self.loading = false
		}
	}
}

// MARK: - Info screen

struct TweakInfoView: View {
	let title: String
	let fileURL: URL
	let type: TweakFileType
	// The app being signed, when known — lets us check dependency satisfaction. Nil in the library.
	var appURL: URL? = nil
	var onApplyRecommendation: ((Options.InjectPath, Options.InjectFolder) -> Void)? = nil
	// Current persisted injection config, so we can show "already applied" across reopens.
	var currentConfig: TweakInjectConfig? = nil

	@StateObject private var _loader = TweakAnalysisLoader()
	@State private var _applied = false

	var body: some View {
		NBList(.localized("Tweak Info")) {
			if let analysis = _loader.analysis {
				_sections(analysis)
			} else {
				NBSection(title) {
					HStack(spacing: 10) {
						ProgressView()
						Text(verbatim: .localized("Analyzing…"))
							.foregroundStyle(.secondary)
					}
				}
			}
		}
		.onAppear { _loader.load(fileURL: fileURL, type: type, appURL: appURL) }
		.onChange(of: fileURL) { _ in _loader.load(fileURL: fileURL, type: type, appURL: appURL) }
	}

	// MARK: Sections

	@ViewBuilder
	private func _sections(_ a: TweakAnalysis) -> some View {
		NBSection(title) {
			_line(systemImage: a.fileType.systemImage, title: a.summary, tint: .accentColor)
			if !a.placement.isEmpty {
				_line(systemImage: "mappin.and.ellipse", title: a.placement, tint: .secondary, small: true)
			}
		}

		if !a.dependencies.isEmpty {
			NBSection(.localized("Dependencies")) {
				ForEach(a.dependencies) { _dependencyRow($0) }
			} footer: {
				Text(.localized("Frameworks the tweak links against. Add a missing one as another file if the tweak needs it."))
			}
		}

		if !a.warnings.isEmpty || !a.notes.isEmpty {
			NBSection(.localized("Notes")) {
				ForEach(a.warnings, id: \.self) { w in
					_line(systemImage: "exclamationmark.triangle.fill", title: w, tint: .orange, small: true)
				}
				ForEach(a.notes, id: \.self) { n in
					_line(systemImage: "info.circle", title: n, tint: .secondary, small: true)
				}
			}
		}

		if !a.debInstallPaths.isEmpty {
			NBSection(.localized("Package Contents"), secondary: "\(a.debInstallPaths.count)") {
				ForEach(a.debInstallPaths, id: \.self) { p in
					Text(verbatim: p)
						.font(.caption.monospaced())
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
		}

		if !a.linkedLibraries.isEmpty {
			NBSection(.localized("Linked Libraries"), secondary: "\(a.linkedLibraries.count)") {
				ForEach(a.linkedLibraries, id: \.self) { lib in
					Text(verbatim: lib)
						.font(.caption.monospaced())
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
		}

		if let onApply = onApplyRecommendation, a.hasRecommendation,
		   let path = a.recommendedPath, let folder = a.recommendedFolder {
			let applied = _applied || (currentConfig?.useCustom == true
				&& currentConfig?.customPath == path
				&& currentConfig?.customFolder == folder)
			NBSection(.localized("Recommended")) {
				Button {
					onApply(path, folder)
					_applied = true
					Toast.success(.localized("Applied recommended settings"), systemImage: "wand.and.stars")
				} label: {
					Label(
						applied
							? .localized("Applied ✓")
							: String.localized("Use Recommended (%@ · %@)", arguments: path.rawValue, folder.rawValue == "/" ? "root" : "Frameworks"),
						systemImage: applied ? "checkmark.circle.fill" : "wand.and.stars"
					)
				}
				.disabled(applied)
			} footer: {
				Text(.localized("Sets this file's injection path and folder to the values that usually work for this kind of tweak."))
			}
		}
	}

	// MARK: Rows

	@ViewBuilder
	private func _dependencyRow(_ dep: TweakDependency) -> some View {
		let (icon, tint): (String, Color) = {
			switch dep.satisfiedByApp {
			case .some(true): return ("checkmark.circle.fill", .green)
			case .some(false): return (dep.critical ? "xmark.circle.fill" : "exclamationmark.circle", dep.critical ? .red : .orange)
			case .none: return ("link.circle", .secondary)
			}
		}()
		let suffix: String = {
			switch dep.satisfiedByApp {
			case .some(true): return .localized("in app")
			case .some(false): return .localized("not in app")
			case .none: return ""
			}
		}()
		_line(
			systemImage: icon,
			title: suffix.isEmpty ? dep.name : "\(dep.name) — \(suffix)",
			tint: tint,
			small: false
		)
	}

	@ViewBuilder
	private func _line(systemImage: String, title: String, tint: Color, small: Bool = false) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Image(systemName: systemImage)
				.foregroundStyle(tint)
				.frame(width: 22)
			Text(title)
				.font(small ? .footnote : .body)
				.foregroundStyle(small ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
				.fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
	}
}
