import Foundation

actor SSLCertificateUpdater {
	static let shared = SSLCertificateUpdater()
	static let defaultPackURL = URL(string: "https://ryuksign-install.ryuksign.workers.dev/pack.json")!

	private let session: URLSession
	private let directory: URL
	private var downloads: [URL: Task<Void, Error>] = [:]

	init(session: URLSession = .shared, directory: URL = .documentsDirectory) {
		self.session = session
		self.directory = directory
	}

	func download(from url: URL = defaultPackURL) async throws {
		if let download = downloads[url] {
			try await download.value
			return
		}

		// A manual refresh can overlap the launch refresh; both must use the same pack.
		let download = Task {
			var request = URLRequest(url: url)
			request.cachePolicy = .reloadIgnoringLocalCacheData
			request.timeoutInterval = 30
			let (data, response) = try await session.data(for: request)
			guard let response = response as? HTTPURLResponse,
				(200..<300).contains(response.statusCode) else {
				throw URLError(.badServerResponse)
			}

			let pack = try JSONDecoder().decode(ServerPack.self, from: data)
			try pack.key.write(to: directory.appendingPathComponent("server.pem"), atomically: true, encoding: .utf8)
			try [pack.cert, pack.ca].joined(separator: "\n").write(
				to: directory.appendingPathComponent("server.crt"), atomically: true, encoding: .utf8
			)
			try pack.info.domains.commonName.write(
				to: directory.appendingPathComponent("commonName.txt"), atomically: true, encoding: .utf8
			)
		}
		downloads[url] = download
		defer { downloads[url] = nil }
		try await download.value
	}

	private struct ServerPack: Decodable {
		let cert: String
		let ca: String
		let key: String
		let info: Info

		private enum CodingKeys: String, CodingKey {
			case cert, ca, key1, key2, info
		}

		init(from decoder: Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			cert = try container.decode(String.self, forKey: .cert)
			ca = try container.decode(String.self, forKey: .ca)
			let key1 = try container.decode(String.self, forKey: .key1)
			let key2 = try container.decode(String.self, forKey: .key2)
			key = key1 + key2
			info = try container.decode(Info.self, forKey: .info)
		}

		struct Info: Decodable {
			let issuer: Domains
			let domains: Domains
		}

		struct Domains: Decodable {
			let commonName: String
		}
	}
}
