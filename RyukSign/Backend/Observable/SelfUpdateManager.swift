//
//  SelfUpdateManager.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import CoreData
import UIKit
import IDeviceSwift
import OSLog

enum SelfUpdateMethod: Int {
	case server = 0
	case idevice = 1
}

struct SelfUpdateRelease: Identifiable, Equatable {
	let id: Int
	let tag: String
	let version: String
	let title: String
	let notes: String
	let publishedAt: Date?
	let downloadURL: URL?
	let isPrerelease: Bool
	let isSemver: Bool

	var isInstalled: Bool { SelfUpdateManager.compare(version, Bundle.main.version) == .orderedSame }
}

enum SelfUpdatePhase: Equatable {
	case idle
	case downloading(Double)
	case importing
	case signing
	case installing
	case done
	case failed(String)
}

final class SelfUpdateManager: NSObject, ObservableObject {
	static let shared = SelfUpdateManager()

	@Published private(set) var latest: SelfUpdateRelease?
	@Published private(set) var latestSemver: SelfUpdateRelease?
	@Published private(set) var available: SelfUpdateRelease?
	@Published private(set) var isChecking = false
	@Published var phase: SelfUpdatePhase = .idle
	@Published var installProgress: Double = 0
	@Published var presentUpdatePrompt = false

	private let _repo = "faroukbmiled/RyukSign"
	private let _perPage = 30

	private enum Keys {
		static let autoCheck = "Feather.selfUpdateAutoCheck"
		static let ignored = "Feather.selfUpdateIgnored"
		static let certIndex = "Feather.selfUpdateCertIndex"
		static let lastCheck = "Feather.selfUpdateLastCheck"
		static let method = "Feather.selfUpdateMethod"
	}

	private var _downloadContinuation: CheckedContinuation<URL, Error>?
	private var _progressHandler: ((Double) -> Void)?
	private var _flow: Task<Void, Never>?

	private override init() {
		super.init()
		UserDefaults.standard.register(defaults: [Keys.autoCheck: true, Keys.certIndex: -1])
	}

	// MARK: - Settings

	var isAutoCheckEnabled: Bool {
		get { UserDefaults.standard.bool(forKey: Keys.autoCheck) }
		set { UserDefaults.standard.set(newValue, forKey: Keys.autoCheck) }
	}

	var certIndex: Int {
		get { UserDefaults.standard.integer(forKey: Keys.certIndex) }
		set { UserDefaults.standard.set(newValue, forKey: Keys.certIndex); objectWillChange.send() }
	}

	var ignoredVersions: Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: Keys.ignored) ?? [])
	}

	func resolvedCertificate() -> CertificatePair? {
		let idx = certIndex >= 0 ? certIndex : UserDefaults.standard.integer(forKey: "feather.selectedCert")
		return Storage.shared.getCertificate(for: idx)
	}

	var method: SelfUpdateMethod {
		get { SelfUpdateMethod(rawValue: UserDefaults.standard.integer(forKey: Keys.method)) ?? .server }
		set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.method); objectWillChange.send() }
	}

	var serverBaseURL: URL? {
		guard
			let url = Bundle.main.url(forResource: "SelfUpdateConfig", withExtension: "plist"),
			let dict = NSDictionary(contentsOf: url),
			let base = (dict["ServerBaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
			!base.isEmpty
		else { return nil }
		return URL(string: base)
	}

	var isServerConfigured: Bool { serverBaseURL != nil }

	var hasPairing: Bool {
		FileManager.default.fileExists(atPath: HeartbeatManager.pairingFile())
	}

	var canSelfInstall: Bool {
		switch method {
		case .server: return isServerConfigured
		case .idevice: return hasPairing
		}
	}

	func ignore(_ version: String) {
		var set = ignoredVersions
		set.insert(version)
		UserDefaults.standard.set(Array(set), forKey: Keys.ignored)
		recomputeAvailable()
	}

	func unignore(_ version: String) {
		var set = ignoredVersions
		set.remove(version)
		UserDefaults.standard.set(Array(set), forKey: Keys.ignored)
		recomputeAvailable()
	}

	// MARK: - Check

	@MainActor
	func checkOnLaunch() async {
		guard isAutoCheckEnabled else { return }
		await check()
		if available != nil { presentUpdatePrompt = true }
	}

	@MainActor
	func check() async {
		guard !isChecking else { return }
		isChecking = true
		defer { isChecking = false }

		do {
			let releases = try await fetchReleases(page: 1)
			latest = releases.first { !$0.isPrerelease } ?? releases.first
			latestSemver = releases.first { $0.isSemver && !$0.isPrerelease }
			UserDefaults.standard.set(Date(), forKey: Keys.lastCheck)
			recomputeAvailable()
		} catch {
			Logger.misc.error("Self-update check failed: \(error.localizedDescription)")
		}
	}

	private func recomputeAvailable() {
		guard let candidate = latestSemver, Self.isSemver(Bundle.main.version) else { available = nil; return }
		let isNewer = SelfUpdateManager.compare(candidate.version, Bundle.main.version) == .orderedDescending
		available = (isNewer && !ignoredVersions.contains(candidate.version)) ? candidate : nil
	}

	// MARK: - Releases fetch (paginated)

	func fetchReleases(page: Int) async throws -> [SelfUpdateRelease] {
		var comps = URLComponents(string: "https://api.github.com/repos/\(_repo)/releases")!
		comps.queryItems = [
			URLQueryItem(name: "per_page", value: String(_perPage)),
			URLQueryItem(name: "page", value: String(page))
		]
		var request = URLRequest(url: comps.url!)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw NSError(domain: "SelfUpdate", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
						  userInfo: [NSLocalizedDescriptionKey: String.localized("Couldn't reach GitHub releases.")])
		}

		let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
		return raw.compactMap(Self.parse)
	}

	private static func parse(_ json: [String: Any]) -> SelfUpdateRelease? {
		guard
			let id = json["id"] as? Int,
			let tag = json["tag_name"] as? String
		else { return nil }

		let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
		guard version.first?.isNumber == true else { return nil }

		let assets = json["assets"] as? [[String: Any]] ?? []
		let ipa = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".ipa") == true }
		let downloadURL = (ipa?["browser_download_url"] as? String).flatMap(URL.init)

		var published: Date?
		if let str = json["published_at"] as? String {
			published = ISO8601DateFormatter().date(from: str)
		}

		return SelfUpdateRelease(
			id: id,
			tag: tag,
			version: version,
			title: (json["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? tag,
			notes: (json["body"] as? String) ?? "",
			publishedAt: published,
			downloadURL: downloadURL,
			isPrerelease: (json["prerelease"] as? Bool) ?? false,
			isSemver: Self.isSemver(version)
		)
	}

	static func isSemver(_ version: String) -> Bool {
		version.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil
	}

	// MARK: - Version compare

	static func compare(_ a: String, _ b: String) -> ComparisonResult {
		func parts(_ s: String) -> [Int] {
			s.split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
		}
		let l = parts(a), r = parts(b)
		for i in 0..<max(l.count, r.count) {
			let lv = i < l.count ? l[i] : 0
			let rv = i < r.count ? r[i] : 0
			if lv != rv { return lv < rv ? .orderedAscending : .orderedDescending }
		}
		return .orderedSame
	}

	// MARK: - Install

	/// One cancellable task per run, cancelling on sheet dismiss stops the poll republishing
	@MainActor
	func beginUpdate(to release: SelfUpdateRelease) {
		_flow?.cancel()
		_flow = Task { await performUpdate(to: release) }
	}

	@MainActor
	func endFlow() {
		_flow?.cancel()
		_flow = nil
		if case .failed = phase {} else {
			phase = .idle
			installProgress = 0
		}
	}

	@MainActor
	func performUpdate(to release: SelfUpdateRelease) async {
		guard canSelfInstall else {
			let message: String = method == .server
				? .localized("The updater server isn't available in this build.")
				: .localized("IDevice updates need a pairing file. Set it up in Installation settings, or switch to Server.")
			phase = .failed(message)
			return
		}
		guard let certificate = resolvedCertificate() else {
			phase = .failed(.localized("No signing certificate selected. Choose one in Update settings."))
			return
		}

		installProgress = 0
		FileLogger.log("Update \(release.version) [\(method == .server ? "server" : "idevice")] cert=\(certificate.nickname ?? Storage.shared.getProvisionFileDecoded(for: certificate)?.Name ?? "?")", category: "update")

		let keepAlive = BackgroundTaskManager(
			taskName: "SelfUpdate",
			expirationTitle: .localized("Update continuing"),
			expirationBody: .localized("The update will continue when you reopen the app")
		)
		keepAlive.start()
		defer { keepAlive.stop() }

		do {
			switch method {
			case .server:
				let installed = try await installViaServer(release: release, certificate: certificate)
				phase = installed ? .done : .idle
			case .idevice:
				try await installViaIDevice(release: release, certificate: certificate)
				phase = .done
			}
		} catch is CancellationError {
			phase = .idle
		} catch let error as URLError where error.code == .cancelled {
			phase = .idle
		} catch {
			let reason = Self.describe(error)
			Logger.misc.error("Self-update failed: \(reason)")
			FileLogger.error("Failed: version=\(release.version) — \(reason)", category: "update")
			phase = .failed(reason)
		}
	}

	/// IDeviceSwift errors hide their text behind no LocalizedError, so reflect out the real message.
	static func describe(_ error: Error) -> String {
		var message: String?
		var code: Int?
		for child in Mirror(reflecting: error).children {
			if child.label == "_message", let value = child.value as? String, !value.isEmpty { message = value }
			if child.label == "_code", let value = child.value as? Int32 { code = Int(value) }
		}
		guard let message else { return error.localizedDescription }
		if let code, code != 0, code != -7001 { return "\(message) (\(code))" }
		return message
	}

	@MainActor
	private func installViaServer(release: SelfUpdateRelease, certificate: CertificatePair) async throws -> Bool {
		phase = .signing
		let installURL = try await requestServerSign(version: release.version, certificate: certificate)
		phase = .installing
		guard await UIApplication.shared.open(installURL) else { return false }
		return await pollInstallProgress()
	}

	/// True once the OTA install begins; false if it never starts (prompt dismissed) so the UI can reset.
	@MainActor
	private func pollInstallProgress() async -> Bool {
		guard let bundleId = Bundle.main.bundleIdentifier else { return false }
		var started = false
		var ticks = 0
		while ticks < 2400 && !Task.isCancelled {
			let raw = await UIApplication.installProgress(for: bundleId) ?? 0
			if raw > 0 { started = true }
			_setInstallProgress(started ? min(1, max(0, (raw - 0.6) / 0.3)) : 0)
			if started && raw == 0 {
				_setInstallProgress(1)
				return true
			}
			if !started && ticks > 160 { return false }
			ticks += 1
			try? await Task.sleep(nanoseconds: 250_000_000)
		}
		return started
	}

	private func _setInstallProgress(_ value: Double) {
		if installProgress != value { installProgress = value }
	}

	@MainActor
	private func installViaIDevice(release: SelfUpdateRelease, certificate: CertificatePair) async throws {
		guard let url = release.downloadURL else {
			throw NSError(domain: "SelfUpdate", code: -1,
						  userInfo: [NSLocalizedDescriptionKey: String.localized("This release has no downloadable IPA.")])
		}

		phase = .downloading(0)
		let ipa = try await download(from: url)

		phase = .importing
		let imported = try await withCheckedThrowingContinuation { (c: CheckedContinuation<AppInfoPresentable, Error>) in
			FR.handlePackageFile(ipa) { c.resume(with: $0) }
		}
		try? FileManager.default.removeItem(at: ipa)

		// A self-update must not leave its temp import/signed entries in the Library, whatever the outcome.
		var scratch: [AppInfoPresentable] = [imported]
		defer { scratch.forEach { Storage.shared.deleteApp(for: $0) } }

		phase = .signing
		var options = OptionsManager.shared.options
		options.appIdentifier = Bundle.main.bundleIdentifier
		options.appVersion = release.version
		let signed = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Signed, Error>) in
			FR.signPackageFile(imported, using: options, icon: nil, certificate: certificate) { result in
				c.resume(with: result)
			}
		}
		scratch.append(signed)

		phase = .installing
		let viewModel = InstallerStatusViewModel(isIdevice: true)
		let handler = ArchiveHandler(app: signed, viewModel: viewModel)
		try await handler.move()
		let package = try await handler.archive()

		scratch.forEach { Storage.shared.deleteApp(for: $0) }
		scratch.removeAll()

		let proxy = InstallationProxy(viewModel: viewModel)
		try await proxy.install(at: package, suspend: true)
	}

	// MARK: - Server signing

	private func requestServerSign(version: String, certificate: CertificatePair) async throws -> URL {
		guard let base = serverBaseURL else {
			throw NSError(domain: "SelfUpdate", code: -4,
						  userInfo: [NSLocalizedDescriptionKey: String.localized("The updater server isn't available in this build.")])
		}
		guard
			let p12URL = Storage.shared.getFile(.certificate, from: certificate),
			let provisionURL = Storage.shared.getFile(.provision, from: certificate),
			let p12Data = try? Data(contentsOf: p12URL),
			let provisionData = try? Data(contentsOf: provisionURL)
		else {
			throw NSError(domain: "SelfUpdate", code: -5,
						  userInfo: [NSLocalizedDescriptionKey: String.localized("Selected certificate files are missing.")])
		}

		let boundary = "RyukSign-\(UUID().uuidString)"
		var body = Data()
		func field(_ name: String, _ value: String) {
			body.append("--\(boundary)\r\n")
			body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
			body.append("\(value)\r\n")
		}
		func file(_ name: String, _ filename: String, _ data: Data) {
			body.append("--\(boundary)\r\n")
			body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
			body.append("Content-Type: application/octet-stream\r\n\r\n")
			body.append(data)
			body.append("\r\n")
		}

		field("version", version)
		field("bundleId", Bundle.main.bundleIdentifier ?? "")
		field("p12password", certificate.password ?? "")
		file("p12", "certificate.p12", p12Data)
		file("provision", "profile.mobileprovision", provisionData)
		body.append("--\(boundary)--\r\n")

		var request = URLRequest(url: base.appendingPathComponent("ryuksign/sign"))
		request.httpMethod = "POST"
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		var lastError: Error = NSError(domain: "SelfUpdate", code: -6,
									   userInfo: [NSLocalizedDescriptionKey: String.localized("The updater server returned no install link.")])

		for attempt in 0..<2 {
			let data: Data, response: URLResponse
			do {
				(data, response) = try await URLSession.shared.upload(for: request, from: body)
			} catch {
				lastError = error
				if attempt == 0 { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
				throw error
			}

			let status = (response as? HTTPURLResponse)?.statusCode ?? -1
			let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

			if (200..<300).contains(status) {
				guard let install = json?["install"] as? String, let url = URL(string: install) else {
					throw NSError(domain: "SelfUpdate", code: -6,
								  userInfo: [NSLocalizedDescriptionKey: String.localized("The updater server returned no install link.")])
				}
				return url
			}

			let rawBody = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
			FileLogger.error("sign HTTP \(status): \(rawBody)", category: "update")
			let code = json?["error"] as? String
			lastError = NSError(domain: "SelfUpdate", code: status,
								userInfo: [NSLocalizedDescriptionKey: Self.serverErrorMessage(status: status, code: code)])

			let transient = [500, 502, 503].contains(status)
			if transient && attempt == 0 {
				try? await Task.sleep(nanoseconds: 2_000_000_000)
				continue
			}
			throw lastError
		}
		throw lastError
	}

	private static func serverErrorMessage(status: Int, code: String?) -> String {
		switch code {
		case "unknown_version", "bad_version": return .localized("That version isn't a published release.")
		case "bad_cert": return .localized("Couldn't read your certificate. Check the certificate and its password.")
		case "bad_provision", "missing_provision": return .localized("Couldn't read your provisioning profile.")
		case "missing_p12": return .localized("Selected certificate files are missing.")
		case "bundle_not_allowed": return .localized("This build isn't permitted by the updater server.")
		case "rate_limited": return .localized("The updater is busy. Try again in a moment.")
		default:
			if status == 429 { return .localized("The updater is busy. Try again in a moment.") }
			return .localized("The update couldn't be prepared. Please try again.")
		}
	}

	// MARK: - Download

	private func download(from url: URL) async throws -> URL {
		let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
		_progressHandler = { [weak self] progress in
			Task { @MainActor in self?.phase = .downloading(progress) }
		}
		return try await withCheckedThrowingContinuation { continuation in
			_downloadContinuation = continuation
			session.downloadTask(with: url).resume()
		}
	}
}

extension SelfUpdateManager: URLSessionDownloadDelegate {
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
					didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		guard totalBytesExpectedToWrite > 0 else { return }
		_progressHandler?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
	}

	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		let dest = FileManager.default.temporaryDirectory
			.appendingPathComponent("SelfUpdate-\(downloadTask.taskIdentifier).ipa")
		try? FileManager.default.removeItem(at: dest)
		do {
			try FileManager.default.moveItem(at: location, to: dest)
			_downloadContinuation?.resume(returning: dest)
		} catch {
			_downloadContinuation?.resume(throwing: error)
		}
		_downloadContinuation = nil
		session.invalidateAndCancel()
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let error else { return }
		_downloadContinuation?.resume(throwing: error)
		_downloadContinuation = nil
		session.invalidateAndCancel()
	}
}

private extension Data {
	mutating func append(_ string: String) {
		append(Data(string.utf8))
	}
}
