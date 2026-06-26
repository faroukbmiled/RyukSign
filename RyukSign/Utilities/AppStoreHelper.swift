//
//  AppStoreHelper.swift
//  RyukSign
//
//  Created by Ryuk on 11.10.2025.
//

import Foundation
import UIKit

struct AppStoreHelper {

	// MARK: - Response Models

	struct AppStoreResponse: Codable {
		let resultCount: Int
		let results: [AppStoreApp]
	}

	struct AppStoreApp: Codable {
		let trackName: String
		let trackViewUrl: String
		let bundleId: String
	}

	// MARK: - Public Methods

	/// Opens the App Store page for the given bundle ID.
	static func openAppStore(for bundleId: String, completion: @escaping (Result<Void, AppStoreError>) -> Void) {
		fetchAppStoreURL(for: bundleId) { result in
			DispatchQueue.main.async {
				switch result {
				case .success(let urlString):
					guard let url = URL(string: urlString) else {
						completion(.failure(.invalidURL))
						return
					}

					UIApplication.shared.open(url) { success in
						if success {
							completion(.success(()))
						} else {
							completion(.failure(.failedToOpen))
						}
					}

				case .failure(let error):
					completion(.failure(error))
				}
			}
		}
	}

	// MARK: - Private Methods

	/// Fetches the App Store URL from the iTunes Search API.
	private static func fetchAppStoreURL(for bundleId: String, completion: @escaping (Result<String, AppStoreError>) -> Void) {
		let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleId)"

		guard let url = URL(string: urlString) else {
			completion(.failure(.invalidBundleId))
			return
		}

		let task = URLSession.shared.dataTask(with: url) { data, response, error in
			if let error = error {
				completion(.failure(.networkError(error.localizedDescription)))
				return
			}

			guard let data = data else {
				completion(.failure(.noData))
				return
			}

			do {
				let decoder = JSONDecoder()
				let appStoreResponse = try decoder.decode(AppStoreResponse.self, from: data)

				if appStoreResponse.resultCount == 0 {
					completion(.failure(.notFoundOnAppStore))
					return
				}

				guard let firstResult = appStoreResponse.results.first else {
					completion(.failure(.unexpectedResponse))
					return
				}

				completion(.success(firstResult.trackViewUrl))

			} catch {
				completion(.failure(.decodingError(error.localizedDescription)))
			}
		}

		task.resume()
	}

	// MARK: - Error Types

	enum AppStoreError: LocalizedError {
		case invalidBundleId
		case networkError(String)
		case noData
		case notFoundOnAppStore
		case unexpectedResponse
		case decodingError(String)
		case invalidURL
		case failedToOpen

		var errorDescription: String? {
			switch self {
			case .invalidBundleId:
				return "Invalid bundle identifier"
			case .networkError(let message):
				return "Network error: \(message)"
			case .noData:
				return "No data received from App Store"
			case .notFoundOnAppStore:
				return "App not found on App Store"
			case .unexpectedResponse:
				return "Unexpected response from App Store"
			case .decodingError(let message):
				return "Failed to decode response: \(message)"
			case .invalidURL:
				return "Invalid App Store URL"
			case .failedToOpen:
				return "Failed to open App Store"
			}
		}
	}
}
