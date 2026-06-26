//
//  SourcesAddView+Repositories.swift
//  RyukSign
//
//  Extracted from SourcesAddView.swift for maintainability.
//

import SwiftUI
import NimbleViews
import AltSourceKit
import NimbleJSON
import OSLog
import UIKit.UIImpactFeedbackGenerator

extension SourcesAddView {
	// MARK: - Fetch Ryuk Repos List
	func _fetchRyukReposList() async {
		await MainActor.run {
			ryukReposFetchError = nil
		}

		do {
			let (data, response) = try await URLSession.shared.data(from: RyukSignAPI.reposListURL)

			guard let httpResponse = response as? HTTPURLResponse,
				httpResponse.statusCode == 200 else {
				await MainActor.run {
					ryukReposFetchError = "Failed to fetch repository list. Server returned an error."
					Logger.misc.error("Failed to fetch Ryuk repos: Invalid response")
				}
				return
			}

			let raw = try JSONSerialization.jsonObject(with: data, options: [])

			guard let strings = raw as? [String] else {
				await MainActor.run {
					ryukReposFetchError = "Unexpected JSON format in repos.json"
				}
				return
			}

			let urls = strings.compactMap { URL(string: $0) }

			await MainActor.run {
				ryukRepos = urls
				ryukReposCount = urls.count
				ryukReposFetchError = nil
				Logger.misc.info("Successfully fetched \(urls.count) Ryuk repos")
			}

		} catch {
			await MainActor.run {
				if (error as NSError).code == NSURLErrorNotConnectedToInternet ||
					(error as NSError).code == NSURLErrorTimedOut ||
					(error as NSError).code == NSURLErrorNetworkConnectionLost {
					ryukReposFetchError = "No internet connection. Please check your network and try again."
				} else {
					ryukReposFetchError = "Failed to load repositories: \(error.localizedDescription)"
				}
				ryukReposCount = 0
				Logger.misc.error("Failed to fetch Ryuk repos: \(error.localizedDescription)")
			}
		}
	}

	// MARK: - Ryuk Repos Handler
	func _addRyukRepos() {
		guard !ryukRepos.isEmpty else {
			_isAddingRyukRepos = false
			Toast.error("No Ryuk repositories available", duration: .sticky)
			return
		}

		Task {
			let fetched = await _concurrentFetchRepositories(from: ryukRepos)
			let dict = Dictionary(fetched, uniquingKeysWith: { first, _ in first })

			await MainActor.run {
				if dict.isEmpty {
					_isAddingRyukRepos = false
					Toast.error("Failed to fetch repository data. Please check your connection and try again.", duration: .sticky)
				} else {
					Storage.shared.addSources(repos: dict) { _ in
						Toast.success("Successfully added \(dict.count) Ryuk repositories")
						_isAddingRyukRepos = false
						_refreshFilteredRecommendedSourcesData()
						dismiss()
					}
				}
			}
		}
	}

	func _fetchRecommendedRepositories() async {
		let fetched = await _concurrentFetchRepositories(from: recommendedSources)
		await MainActor.run {
			recommendedSourcesData = fetched
			_refreshFilteredRecommendedSourcesData()
		}
	}

	func _fetchImportedRepositories(
		_ code: String?,
		competion: @escaping (Bool, Int) -> Void
	) {
		guard let code else {
			competion(false, 0)
			return
		}

		let handler = ASDeobfuscator(with: code)
		let repoUrls = handler.decode().compactMap { URL(string: $0) }
		guard !repoUrls.isEmpty else {
			competion(false, 0)
			return
		}

		Task {
			let fetched = await _concurrentFetchRepositories(from: repoUrls)

			let dict = Dictionary(fetched, uniquingKeysWith: { first, _ in first })

			await MainActor.run {
				if dict.isEmpty {
					competion(false, 0)
				} else {
					Storage.shared.addSources(repos: dict) { _ in
						competion(true, dict.count)
					}
				}
			}
		}
	}

	func _concurrentFetchRepositories(
		from urls: [URL],
		isPremium: Bool = false
	) async -> [(url: URL, data: ASRepository)] {
		var results: [(url: URL, data: ASRepository)] = []

		let dataService = _dataService

		await withTaskGroup(of: Void.self) { group in
			for url in urls {
				group.addTask {
					await withCheckedContinuation { continuation in
						let headers = isPremium ? RyukSignAPI.authHeaders(for: url) : [:]

						dataService.fetch<ASRepository>(from: url, headers: headers) { (result: RepositoryDataHandler) in
							switch result {
							case .success(let repo):
								Task { @MainActor in
									results.append((url: url, data: repo))
								}
							case .failure(let error):
								Logger.misc.error("Failed to fetch \(url): \(error.localizedDescription)")
							}
							continuation.resume()
						}
					}
				}
			}
			await group.waitForAll()
		}

		return results
	}

	// MARK: - Premium RyukSign API Methods

	private struct RyukSignAPIResponse: Codable {
		let success: Bool
		let urls: [RyukSignURLItem]?
	}

	private struct RyukSignURLItem: Codable {
		let name: String
		let url: String
	}

	private struct RyukSignErrorResponse: Codable {
		let detail: String
	}

	func _validatePremiumAPIKey() {
		let apiKey = _premiumAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

		guard apiKey.hasPrefix("RYK-") && apiKey.count >= 16 else {
			_premiumErrorMessage = RyukSignAPI.errorMessage("Invalid key format. Keys should be in format: RYK-XXXX-XXXX-XXXX")
			_showPremiumError = true
			return
		}

		_showPremiumKeyPrompt = false
		_isValidatingAPIKey = true

		Task {
			await _redeemPremiumAPIKey(apiKey)
		}
	}

	func _redeemPremiumAPIKey(_ apiKey: String) async {
		guard let url = URL(string: RyukSignAPI.apiValidateEndpoint) else {
			await MainActor.run {
				_isValidatingAPIKey = false
				_premiumErrorMessage = RyukSignAPI.errorMessage("Internal error: Invalid API URL configuration.")
				_showPremiumError = true
			}
			return
		}

		guard let deviceUUID = RyukSignAPI.deviceUUID else {
			await MainActor.run {
				_isValidatingAPIKey = false
				_premiumErrorMessage = RyukSignAPI.errorMessage("Unable to retrieve device identifier. Please try again.")
				_showPremiumError = true
			}
			return
		}

		let requestBody: [String: String] = ["device_uuid": deviceUUID]
		guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
			await MainActor.run {
				_isValidatingAPIKey = false
				_premiumErrorMessage = RyukSignAPI.errorMessage("Internal error: Failed to prepare request.")
				_showPremiumError = true
			}
			return
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = httpBody
		request.timeoutInterval = 30

		do {
			let (data, response) = try await URLSession.shared.data(for: request)

			guard let httpResponse = response as? HTTPURLResponse else {
				await MainActor.run {
					_isValidatingAPIKey = false
					_premiumErrorMessage = RyukSignAPI.errorMessage("Unexpected response from server. Please try again.")
					_showPremiumError = true
				}
				return
			}

			switch httpResponse.statusCode {
			case 200:
				let decoder = JSONDecoder()
				let apiResponse = try decoder.decode(RyukSignAPIResponse.self, from: data)

				guard apiResponse.success, let urlItems = apiResponse.urls, !urlItems.isEmpty else {
					await MainActor.run {
						_isValidatingAPIKey = false
						_premiumErrorMessage = RyukSignAPI.errorMessage("Key validated but no repositories were returned.")
						_showPremiumError = true
					}
					return
				}

				let validURLs = urlItems.compactMap { URL(string: $0.url) }

				guard !validURLs.isEmpty else {
					await MainActor.run {
						_isValidatingAPIKey = false
						_premiumErrorMessage = RyukSignAPI.errorMessage("No valid repository URLs received.")
						_showPremiumError = true
					}
					return
				}

				await _addPremiumRepositoriesFromAPI(urls: validURLs)

			case 401:
				let errorResponse = try? JSONDecoder().decode(RyukSignErrorResponse.self, from: data)
				await MainActor.run {
					_isValidatingAPIKey = false
					_premiumAPIKey = ""
					_premiumErrorMessage = errorResponse?.detail ?? RyukSignAPI.errorMessage("Invalid API key. The key does not exist or has already been used.")
					_showPremiumError = true
					UINotificationFeedbackGenerator().notificationOccurred(.error)
				}

			case 403:
				let errorResponse = try? JSONDecoder().decode(RyukSignErrorResponse.self, from: data)
				await MainActor.run {
					_isValidatingAPIKey = false
					_premiumAPIKey = ""
					_premiumErrorMessage = errorResponse?.detail ?? RyukSignAPI.errorMessage("This API key has been disabled.")
					_showPremiumError = true
					UINotificationFeedbackGenerator().notificationOccurred(.error)
				}

			case 422:
				let errorResponse = try? JSONDecoder().decode(RyukSignErrorResponse.self, from: data)
				await MainActor.run {
					_isValidatingAPIKey = false
					_premiumErrorMessage = errorResponse?.detail ?? RyukSignAPI.errorMessage("Request validation failed.")
					_showPremiumError = true
				}

			case 500...599:
				await MainActor.run {
					_isValidatingAPIKey = false
					_premiumErrorMessage = RyukSignAPI.errorMessage("RyukSign server is currently unavailable (Error \(httpResponse.statusCode)). Please try again later.")
					_showPremiumError = true
				}

			default:
				await MainActor.run {
					_isValidatingAPIKey = false
					_premiumErrorMessage = RyukSignAPI.errorMessage("Unexpected error (HTTP \(httpResponse.statusCode)).")
					_showPremiumError = true
				}
			}

		} catch let error as URLError {
			await MainActor.run {
				_isValidatingAPIKey = false

				switch error.code {
				case .notConnectedToInternet:
					_premiumErrorMessage = RyukSignAPI.errorMessage("No internet connection. Please check your network and try again.")
				case .timedOut:
					_premiumErrorMessage = RyukSignAPI.errorMessage("Request timed out. Please check your connection and try again.")
				case .cannotFindHost, .cannotConnectToHost:
					_premiumErrorMessage = RyukSignAPI.errorMessage("Cannot connect to RyukSign server. Please try again later.")
				default:
					_premiumErrorMessage = RyukSignAPI.errorMessage("Network error: \(error.localizedDescription)")
				}

				_showPremiumError = true
				Logger.misc.error("Premium API network error: \(error.localizedDescription)")
			}

		} catch {
			await MainActor.run {
				_isValidatingAPIKey = false
				_premiumErrorMessage = RyukSignAPI.errorMessage("Unexpected error: \(error.localizedDescription)")
				_showPremiumError = true
				Logger.misc.error("Premium API error: \(error.localizedDescription)")
			}
		}
	}

	func _addPremiumRepositoriesFromAPI(urls: [URL]) async {
		RyukSignAPI.registerPremiumSources(urls)

		let fetched = await _concurrentFetchRepositories(from: urls, isPremium: true)
		let dict = Dictionary(fetched, uniquingKeysWith: { first, _ in first })

		await MainActor.run {
			_isValidatingAPIKey = false
			_premiumAPIKey = ""

			if dict.isEmpty {
				_premiumErrorMessage = RyukSignAPI.errorMessage("Failed to fetch repository data from the provided URLs.")
				_showPremiumError = true
				UINotificationFeedbackGenerator().notificationOccurred(.error)
			} else {
				// Save premium state and URLs to keychain for reinstall recovery
				RyukSignAPI.isPremium = true
				RyukSignAPI.savePremiumURLsToKeychain(urls)
				_isPremium = true

				Storage.shared.addSources(repos: dict) { _ in
					Toast.success("Successfully added \(dict.count) premium repositor\(dict.count == 1 ? "y" : "ies")!")
					_refreshFilteredRecommendedSourcesData()
					dismiss()
				}
			}
		}
	}

	// MARK: - Premium Reset & Restore

	func _resetPremium() {
		// Remove only RyukSign premium repos from sources
		let premiumHosts = RyukSignAPI.premiumSourceHosts
		let allSources = Storage.shared.getSources()

		for source in allSources {
			guard let url = source.sourceURL,
				  let host = url.host?.lowercased(),
				  premiumHosts.contains(host) else { continue }
			Storage.shared.deleteSource(for: source)
		}

		RyukSignAPI.premiumSourceHosts = []
		RyukSignAPI.clearPremiumKeychain()
		_isPremium = false

		Toast.success("Premium activation has been reset")
		_refreshFilteredRecommendedSourcesData()
	}

	func _restorePremiumFromKeychain() {
		guard let savedURLs = RyukSignAPI.getSavedPremiumURLs() else {
			RyukSignAPI.clearPremiumKeychain()
			_premiumAPIKey = ""
			_showPremiumKeyPrompt = true
			return
		}

		_isValidatingAPIKey = true

		RyukSignAPI.registerPremiumSources(savedURLs)

		Task {
			let fetched = await _concurrentFetchRepositories(from: savedURLs, isPremium: true)
			let dict = Dictionary(fetched, uniquingKeysWith: { first, _ in first })

			await MainActor.run {
				_isValidatingAPIKey = false

				if dict.isEmpty {
					_premiumErrorMessage = RyukSignAPI.errorMessage("Failed to restore premium repositories. Please check your connection and try again.")
					_showPremiumError = true
					UINotificationFeedbackGenerator().notificationOccurred(.error)
				} else {
					_isPremium = true

					Storage.shared.addSources(repos: dict) { _ in
						Toast.success("Restored \(dict.count) premium repositor\(dict.count == 1 ? "y" : "ies")!")
						_refreshFilteredRecommendedSourcesData()
					}
				}
			}
		}
	}
}
