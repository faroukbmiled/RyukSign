import Foundation
import XCTest
@testable import RyukSign

final class SSLCertificateUpdaterTests: XCTestCase {
	private var directory: URL!
	private var url: URL!
	private var session: URLSession!
	private var updater: SSLCertificateUpdater!

	override func setUpWithError() throws {
		directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		url = URL(string: "https://certificates.test/\(UUID().uuidString).json")!
		let configuration = URLSessionConfiguration.ephemeral
		configuration.protocolClasses = [CertificateURLProtocol.self]
		session = URLSession(configuration: configuration)
		updater = SSLCertificateUpdater(session: session, directory: directory)
	}

	override func tearDownWithError() throws {
		CertificateURLProtocol.removeHandler(for: url)
		session.invalidateAndCancel()
		try FileManager.default.removeItem(at: directory)
	}

	func testDownloadsCompletePack() async throws {
		stub { request in
			XCTAssertEqual(request.request.cachePolicy, .reloadIgnoringLocalCacheData)
			XCTAssertEqual(request.request.timeoutInterval, 30)
			request.respond(with: Self.pack)
		}

		try await updater.download(from: url)

		XCTAssertEqual(try contents(of: "server.pem"), "PRIVATE-KEY")
		XCTAssertEqual(try contents(of: "server.crt"), "CERTIFICATE\nCA")
		XCTAssertEqual(try contents(of: "commonName.txt"), "localhost.test")
	}

	func testHTTPFailurePreservesExistingCertificates() async throws {
		try writeExistingCertificates()
		stub { $0.respond(with: Self.pack, status: 503) }

		do {
			try await updater.download(from: url)
			XCTFail("A non-success HTTP status must fail the refresh")
		} catch {
			XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
		}
		try assertExistingCertificates()
	}

	func testInvalidPackPreservesExistingCertificates() async throws {
		try writeExistingCertificates()
		stub { $0.respond(with: Data(#"{"cert":"new certificate"}"#.utf8)) }

		do {
			try await updater.download(from: url)
			XCTFail("An incomplete pack must fail before writing any files")
		} catch {
			XCTAssertTrue(error is DecodingError)
		}
		try assertExistingCertificates()
	}

	func testOfflineRefreshCanBeRetried() async throws {
		try writeExistingCertificates()
		stub { $0.fail(with: URLError(.notConnectedToInternet)) }

		do {
			try await updater.download(from: url)
			XCTFail("An offline request must fail")
		} catch {
			XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
		}
		try assertExistingCertificates()

		stub { $0.respond(with: Self.pack) }
		try await updater.download(from: url)
		XCTAssertEqual(try contents(of: "server.pem"), "PRIVATE-KEY")
	}

	func testCompletedRefreshDoesNotSuppressManualUpdates() async throws {
		stub { $0.respond(with: Self.pack) }
		try await updater.download(from: url)

		let refreshed = expectation(description: "A later refresh makes another request")
		stub {
			refreshed.fulfill()
			$0.respond(with: Self.pack)
		}
		try await updater.download(from: url)
		await fulfillment(of: [refreshed], timeout: 2)
	}

	func testWriteFailureIsReported() async throws {
		try FileManager.default.removeItem(at: directory)
		defer { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
		stub { $0.respond(with: Self.pack) }

		do {
			try await updater.download(from: url)
			XCTFail("A failed file write must fail the refresh")
		} catch {
			XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
		}
	}

	@MainActor
	func testOverlappingRefreshesShareRequestWithoutBlockingMainActor() async throws {
		let started = expectation(description: "The launch request started")
		let duplicate = expectation(description: "No duplicate network request")
		duplicate.isInverted = true
		let pending = PendingCertificateRequests()
		stub { request in
			if pending.append(request) == 1 {
				started.fulfill()
			} else {
				duplicate.fulfill()
			}
		}

		let launch = Task { try await updater.download(from: url) }
		await fulfillment(of: [started], timeout: 2)
		XCTAssertTrue(Thread.isMainThread)

		let manualStarted = expectation(description: "The manual refresh started")
		let manual = Task {
			manualStarted.fulfill()
			try await updater.download(from: url)
		}
		await fulfillment(of: [manualStarted], timeout: 2)
		await fulfillment(of: [duplicate], timeout: 0.1)
		pending.respond(with: Self.pack)
		try await launch.value
		try await manual.value
		XCTAssertEqual(try contents(of: "server.pem"), "PRIVATE-KEY")
	}

	private func stub(_ handler: @escaping (CertificateURLProtocol) -> Void) {
		CertificateURLProtocol.setHandler(handler, for: url)
	}

	private func contents(of name: String) throws -> String {
		try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
	}

	private func writeExistingCertificates() throws {
		for name in ["server.pem", "server.crt", "commonName.txt"] {
			try "existing \(name)".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
		}
	}

	private func assertExistingCertificates() throws {
		for name in ["server.pem", "server.crt", "commonName.txt"] {
			XCTAssertEqual(try contents(of: name), "existing \(name)")
		}
	}

	private static let pack = Data(#"{"cert":"CERTIFICATE","ca":"CA","key1":"PRIVATE-","key2":"KEY","info":{"issuer":{"commonName":"Test CA"},"domains":{"commonName":"localhost.test"}}}"#.utf8)
}

private final class PendingCertificateRequests {
	private let lock = NSLock()
	private var requests: [CertificateURLProtocol] = []

	func append(_ request: CertificateURLProtocol) -> Int {
		lock.lock()
		defer { lock.unlock() }
		requests.append(request)
		return requests.count
	}

	func respond(with data: Data) {
		lock.lock()
		let pending = requests
		lock.unlock()
		for request in pending {
			request.respond(with: data)
		}
	}
}

private final class CertificateURLProtocol: URLProtocol {
	private static let lock = NSLock()
	private static var handlers: [URL: (CertificateURLProtocol) -> Void] = [:]

	static func setHandler(_ handler: @escaping (CertificateURLProtocol) -> Void, for url: URL) {
		lock.lock()
		defer { lock.unlock() }
		handlers[url] = handler
	}

	static func removeHandler(for url: URL) {
		lock.lock()
		defer { lock.unlock() }
		handlers[url] = nil
	}

	override class func canInit(with request: URLRequest) -> Bool { true }
	override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

	override func startLoading() {
		Self.lock.lock()
		let handler = request.url.flatMap { Self.handlers[$0] }
		Self.lock.unlock()
		guard let handler else {
			fail(with: URLError(.resourceUnavailable))
			return
		}
		handler(self)
	}

	override func stopLoading() {}

	func respond(with data: Data, status: Int = 200) {
		let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
		client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		client?.urlProtocol(self, didLoad: data)
		client?.urlProtocolDidFinishLoading(self)
	}

	func fail(with error: Error) {
		client?.urlProtocol(self, didFailWithError: error)
	}
}
