//
//  FetchService.swift
//  Loader
//
//  Created by samara on 14.03.2025.
//

import Foundation
import OSLog

// MARK: - Class
public class NBFetchService {

	private static let log = Logger(subsystem: "com.ryuksign.network", category: "NBFetchService")

	public enum NBFetchServiceError: Error, LocalizedError {
		case invalidURL
		case networkError(Error)
		case noData
		case httpError(Int)
		case parsingError(Error)

		public var errorDescription: String? {
			switch self {
			case .invalidURL: "The URL is invalid."
			case .networkError(let error): "Network error: \(error.localizedDescription)"
			case .noData: "No data received."
			case .httpError(let code): "Server returned HTTP \(code)."
			case .parsingError(let error): "Failed to parse data: \(error.localizedDescription)"
			}
		}
	}

	public init() {}
}

// MARK: - Class extension: fetch
extension NBFetchService {
	public func fetch<T: Decodable>(
		from urlString: String,
		headers: [String: String] = [:],
		completion: @escaping (Result<T, Error>) -> Void
	) {
		guard let url = URL(string: urlString) else {
			completion(.failure(NBFetchServiceError.invalidURL))
			return
		}

		fetch(from: url, headers: headers, completion: completion)
	}

	public func fetch<T: Decodable>(
		from url: URL,
		headers: [String: String] = [:],
		completion: @escaping (Result<T, Error>) -> Void
	) {
		DispatchQueue.global(qos: .userInitiated).async {
			// Create URLRequest with gzip support
			var request = URLRequest(url: url)
			request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
			request.cachePolicy = .reloadIgnoringLocalCacheData
			request.timeoutInterval = 30

			// Apply custom headers
			for (key, value) in headers {
				request.setValue(value, forHTTPHeaderField: key)
			}

			let task = URLSession.shared.dataTask(with: request) { data, response, error in
				if let error = error {
					Self.log.error("Request FAILED \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
					completion(.failure(NBFetchServiceError.networkError(error)))
					return
				}

				let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

				guard let data = data else {
					Self.log.error("Request NO DATA \(url.absoluteString, privacy: .public) (HTTP \(statusCode, privacy: .public))")
					completion(.failure(NBFetchServiceError.noData))
					return
				}

				// Non-2xx responses are logged with a body snippet so auth/server
				// rejections (e.g. premium 401/403/422) are visible instead of
				// silently failing to decode and looking like an infinite load.
				if !(200..<300).contains(statusCode) {
					let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
					Self.log.error("Request HTTP \(statusCode, privacy: .public) \(url.absoluteString, privacy: .public)\nBody: \(snippet, privacy: .public)")
					completion(.failure(NBFetchServiceError.httpError(statusCode)))
					return
				}

				// URLSession automatically decompresses gzip responses,
				// so we can use the data directly
				do {
					let decoder = JSONDecoder()
					let decodedData = try decoder.decode(T.self, from: data)
					Self.log.debug("Request OK (HTTP \(statusCode, privacy: .public)) \(url.absoluteString, privacy: .public)")
					completion(.success(decodedData))
				} catch {
					let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
					Self.log.error("Request PARSE FAIL (HTTP \(statusCode, privacy: .public)) \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)\nBody: \(snippet, privacy: .public)")
					completion(.failure(NBFetchServiceError.parsingError(error)))
				}
			}

			task.resume()
		}
	}
}
