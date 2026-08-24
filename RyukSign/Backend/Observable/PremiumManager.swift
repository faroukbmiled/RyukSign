//
//  PremiumManager.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import AltSourceKit
import OSLog

@MainActor
final class PremiumManager: ObservableObject {
	static let shared = PremiumManager()

	enum PremiumError: LocalizedError {
		case noDeviceID
		case invalidDeviceID
		case notActivated
		case unavailable
		case empty
		case message(String)

		var errorDescription: String? {
			switch self {
			case .noDeviceID: return "Unable to retrieve device identifier. Please try again."
			case .invalidDeviceID: return .localized("That doesn't look like a valid device ID.")
			case .notActivated: return .localized("No premium access is registered for this device ID.")
			case .unavailable: return .localized("Device recovery isn't available on the server yet.")
			case .empty: return "Failed to fetch repository data from the provided URLs."
			case .message(let message): return message
			}
		}
	}

	@Published private(set) var isWorking = false
	@Published private(set) var isActive = false
	@Published private(set) var sourceCount = 0

	private init() {
		refresh()
	}

	func refresh() {
		isActive = RyukSignAPI.isPremium && !RyukSignAPI.premiumSourceHosts.isEmpty
		sourceCount = Storage.shared.getSources().filter { source in
			source.sourceURL.map { RyukSignAPI.isPremiumSource($0) } ?? false
		}.count
	}

	func redeem(key: String) async throws -> Int {
		guard let endpoint = URL(string: RyukSignAPI.apiValidateEndpoint) else {
			throw PremiumError.message("Internal error: Invalid API URL configuration.")
		}

		guard let deviceUUID = RyukSignAPI.deviceUUID else { throw PremiumError.noDeviceID }

		guard let body = try? JSONSerialization.data(withJSONObject: ["device_uuid": deviceUUID]) else {
			throw PremiumError.message("Internal error: Failed to prepare request.")
		}

		var request = URLRequest(url: endpoint)
		request.httpMethod = "POST"
		request.setValue(key, forHTTPHeaderField: "X-API-Key")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = body

		isWorking = true
		defer { isWorking = false }

		let urls = try await _requestURLs(request, missingAccess: "Invalid API key. The key does not exist or has already been used.")
		return try await _activate(with: urls)
	}

	func restore() async throws -> Int {
		isWorking = true
		defer { isWorking = false }

		guard let urls = RyukSignAPI.getSavedPremiumURLs() else {
			return try await _recover()
		}

		return try await _activate(with: urls)
	}

	func recoverFromServer() async throws -> Int {
		isWorking = true
		defer { isWorking = false }

		return try await _recover()
	}

	func adopt(deviceID: String) async throws -> Int {
		guard RyukSignAPI.adoptDeviceUUID(deviceID) else { throw PremiumError.invalidDeviceID }
		return try await recoverFromServer()
	}

	func reset() {
		let hosts = RyukSignAPI.premiumSourceHosts

		for source in Storage.shared.getSources() {
			guard
				let url = source.sourceURL,
				let host = url.host?.lowercased(),
				hosts.contains(host)
			else {
				continue
			}

			Storage.shared.deleteSource(for: source)
		}

		RyukSignAPI.premiumSourceHosts = []
		RyukSignAPI.clearPremiumIdentity()
		refresh()
	}

	private func _recover() async throws -> Int {
		guard let uuid = RyukSignAPI.deviceUUID else { throw PremiumError.noDeviceID }
		guard let endpoint = URL(string: RyukSignAPI.apiURLsEndpoint) else { throw PremiumError.unavailable }

		var request = URLRequest(url: endpoint)
		request.setValue(uuid, forHTTPHeaderField: "ryukSignUUID")

		let urls = try await _requestURLs(request, missingAccess: PremiumError.notActivated.localizedDescription)
		return try await _activate(with: urls)
	}

	private func _requestURLs(_ request: URLRequest, missingAccess: String) async throws -> [URL] {
		var request = request
		request.timeoutInterval = 30

		let data: Data
		let response: URLResponse

		do {
			(data, response) = try await URLSession.shared.data(for: request)
		} catch let error as URLError {
			Logger.misc.error("Premium API network error: \(error.localizedDescription, privacy: .public)")

			switch error.code {
			case .notConnectedToInternet:
				throw PremiumError.message("No internet connection. Please check your network and try again.")
			case .timedOut:
				throw PremiumError.message("Request timed out. Please check your connection and try again.")
			case .cannotFindHost, .cannotConnectToHost:
				throw PremiumError.message("Cannot connect to RyukSign server. Please try again later.")
			default:
				throw PremiumError.message("Network error: \(error.localizedDescription)")
			}
		}

		guard let http = response as? HTTPURLResponse else {
			throw PremiumError.message("Unexpected response from server. Please try again.")
		}

		let detail = try? JSONDecoder().decode(RyukSignAPI.ErrorResponse.self, from: data).detail

		switch http.statusCode {
		case 200:
			break
		case 401:
			throw PremiumError.message(detail ?? missingAccess)
		case 403:
			throw PremiumError.message(detail ?? "This API key has been disabled.")
		case 404, 405, 501:
			throw PremiumError.unavailable
		case 422:
			throw PremiumError.message(detail ?? "Request validation failed.")
		case 500...599:
			throw PremiumError.message("RyukSign server is currently unavailable (Error \(http.statusCode)). Please try again later.")
		default:
			throw PremiumError.message("Unexpected error (HTTP \(http.statusCode)).")
		}

		let decoded = try? JSONDecoder().decode(RyukSignAPI.URLsResponse.self, from: data)
		let urls = (decoded?.urls ?? []).compactMap { URL(string: $0.url) }
		guard !urls.isEmpty else { throw PremiumError.message("Key validated but no repositories were returned.") }

		return urls
	}

	private func _activate(with urls: [URL]) async throws -> Int {
		RyukSignAPI.registerPremiumSources(urls)

		let repositories = await FR.fetchRepositories(from: urls)
		guard !repositories.isEmpty else { throw PremiumError.empty }

		RyukSignAPI.isPremium = true
		RyukSignAPI.savePremiumURLs(urls)

		let repos = Dictionary(repositories.map { ($0.url, $0.data) }, uniquingKeysWith: { first, _ in first })

		await withCheckedContinuation { continuation in
			Storage.shared.addSources(repos: repos) { _ in
				continuation.resume()
			}
		}

		refresh()
		return repos.count
	}
}
