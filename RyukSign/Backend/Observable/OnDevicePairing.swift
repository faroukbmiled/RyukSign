//
//  OnDevicePairing.swift
//  RyukSign
//
//  Created by Ryuk
//

import UIKit
import UserNotifications
import dnssd
import IDevice
import IDeviceSwift

@available(iOS 27.0, *)
@MainActor
final class OnDevicePairing: ObservableObject {
	static let shared = OnDevicePairing()

	enum State: Equatable {
		case idle
		case waiting
		case pin(String)
		case paired
		case failed(String)

		var isActive: Bool {
			switch self {
			case .waiting, .pin: true
			default: false
			}
		}
	}

	@Published private(set) var state: State = .idle

	private var _session = UUID()
	private var _connection: Int32 = -1
	private var _service: DNSServiceRef?
	private var _keepAlive: BackgroundTaskManager?
	private var _timeout: Task<Void, Never>?

	nonisolated private static let _serviceType = "_remotepairing-pairable-host._tcp"
	nonisolated private static let _hostName = "RyukSign"
	nonisolated private static let _notificationID = "RyukSign.pairing"

	// MARK: Control

	func start() {
		guard !state.isActive else { return }

		let session = UUID()
		_session = session
		state = .waiting

		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
		_keepAlive = BackgroundTaskManager(
			taskName: "Pairing",
			expirationTitle: .localized("Pairing paused"),
			expirationBody: .localized("Open RyukSign to finish pairing.")
		)
		_keepAlive?.start()
		_timeout = Task { [weak self] in
			try? await Task.sleep(for: .seconds(600))
			guard !Task.isCancelled else { return }
			self?._finish(.failure(PairingError(.localized("Pairing timed out"))), session: session)
		}

		// Pairing blocks on sockets until Settings finishes, keep it off the cooperative pool.
		DispatchQueue.global(qos: .userInitiated).async {
			let result = Self._pair(session: session)
			Task { @MainActor in self._finish(result, session: session) }
		}
	}

	func cancel() {
		guard state.isActive else { return }
		_session = UUID()
		_teardown()
		state = .idle
	}

	func reset() {
		try? FileManager.default.removeItem(atPath: HeartbeatManager.pairingFile())
		state = .idle
	}

	// MARK: Flow

	private func _finish(_ result: Result<Void, PairingError>?, session: UUID) {
		guard _session == session, let result else { return }
		_session = UUID()
		_teardown()

		switch result {
		case .success:
			state = .paired
			_notify(.localized("Paired. The pairing file is saved."))
			HeartbeatManager.shared.start(true)
		case .failure(let error):
			state = .failed(error.message)
			_notify(error.message)
		}
	}

	fileprivate func _showPin(_ pin: String) {
		guard state.isActive else { return }
		state = .pin(pin)
		_post(title: .localized("Pairing PIN"), body: pin, timeSensitive: true)
	}

	private func _endAttempt() {
		_closeConnection()
		guard case .pin = state else { return }
		state = .waiting
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self._notificationID])
	}

	private func _notify(_ body: String) {
		guard UIApplication.shared.applicationState != .active else { return }
		_post(title: .localized("On-Device Pairing"), body: body, timeSensitive: false)
	}

	private func _post(title: String, body: String, timeSensitive: Bool) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default
		if timeSensitive { content.interruptionLevel = .timeSensitive }
		UNUserNotificationCenter.current().add(
			UNNotificationRequest(identifier: Self._notificationID, content: content, trigger: nil)
		)
	}

	private func _closeConnection() {
		guard _connection >= 0 else { return }
		shutdown(_connection, SHUT_RDWR)
		close(_connection)
		_connection = -1
	}

	private func _teardown() {
		if let service = _service {
			DNSServiceRefDeallocate(service)
			_service = nil
		}
		_closeConnection()
		_keepAlive?.stop()
		_keepAlive = nil
		_timeout?.cancel()
		_timeout = nil
		UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self._notificationID])
	}

	private func _advertise(serviceID: String, port: UInt16, txt: Data) {
		var ref: DNSServiceRef?
		let error = txt.withUnsafeBytes { bytes in
			DNSServiceRegister(
				&ref, 0, 0, serviceID, Self._serviceType, nil, nil,
				port.bigEndian, UInt16(txt.count), bytes.baseAddress, nil, nil
			)
		}
		if error == kDNSServiceErr_NoError { _service = ref }
	}
}

// MARK: - Pairing
@available(iOS 27.0, *)
extension OnDevicePairing {
	struct PairingError: Error {
		let message: String

		init(_ message: String) { self.message = message }

		init(_ error: UnsafeMutablePointer<IdeviceFfiError>, fallback: String) {
			OnDevicePairing._log(error, fallback)
			self.message = fallback
		}
	}

	nonisolated private static func _log(_ error: UnsafeMutablePointer<IdeviceFfiError>, _ context: String) {
		let detail = error.pointee.message.map { String(cString: $0) } ?? ""
		FileLogger.error("\(context): \(detail)", category: "pairing")
		idevice_error_free(error)
	}

	@discardableResult
	nonisolated private static func _ifCurrent(_ session: UUID, _ body: @MainActor () -> Void = {}) -> Bool {
		DispatchQueue.main.sync {
			MainActor.assumeIsolated {
				guard shared._session == session else { return false }
				body()
				return true
			}
		}
	}

	// nil means the session was cancelled.
	nonisolated private static func _pair(session: UUID) -> Result<Void, PairingError>? {
		let setupFailed = PairingError(.localized("Couldn't start pairing"))
		var host: OpaquePointer?
		var serviceID: UnsafeMutablePointer<CChar>?
		var txt: UnsafeMutablePointer<UInt8>?
		var txtLength: UInt = 0

		if let error = pairable_host_prepare(_hostName, nil, false, &host, &serviceID, &txt, &txtLength, nil) {
			return .failure(PairingError(error, fallback: setupFailed.message))
		}
		defer {
			pairable_host_free(host)
			idevice_string_free(serviceID)
			idevice_data_free(txt, txtLength)
		}
		guard
			let host, let serviceID, let txt,
			let record = _txtRecord(Data(bytes: txt, count: Int(txtLength)))
		else {
			return .failure(setupFailed)
		}

		let listener = _makeListener()
		guard listener >= 0 else { return .failure(setupFailed) }
		defer { close(listener) }

		let name = String(cString: serviceID)
		guard _ifCurrent(session, { shared._advertise(serviceID: name, port: _port(of: listener), txt: record) }) else {
			return nil
		}

		let pinCallback: PairableHostPinCb = { pin, _ in
			guard let pin else { return }
			let value = String(cString: pin)
			Task { @MainActor in OnDevicePairing.shared._showPin(value) }
		}

		// Settings can drop a connection or retry, so keep listening until one attempt succeeds.
		while let connection = _nextConnection(listener, session: session) {
			defer { close(connection) }

			// Any iPhone on the network can see the service, only accept this device.
			guard _isLoopback(connection), _ifCurrent(session, { shared._connection = dup(connection) }) else {
				continue
			}

			var file: OpaquePointer?
			let error = pairable_host_accept_fd(host, connection, pinCallback, nil, nil, &file)
			_ifCurrent(session) { shared._endAttempt() }
			if let error {
				_log(error, "pairing attempt failed")
				continue
			}
			guard let file else { continue }
			defer { rp_pairing_file_free(file) }

			if let error = rp_pairing_file_write(file, HeartbeatManager.pairingFile()) {
				return .failure(PairingError(error, fallback: .localized("Couldn't save the pairing file")))
			}
			return .success(())
		}
		return nil
	}

	nonisolated private static func _nextConnection(_ listener: Int32, session: UUID) -> Int32? {
		var pending = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
		while _ifCurrent(session) {
			guard poll(&pending, 1, 250) > 0 else { continue }
			let connection = accept(listener, nil, nil)
			if connection >= 0 { return connection }
		}
		return nil
	}

	nonisolated private static func _makeListener() -> Int32 {
		let fd = socket(AF_INET, SOCK_STREAM, 0)
		guard fd >= 0 else { return -1 }

		var address = sockaddr_in()
		address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
		address.sin_family = sa_family_t(AF_INET)
		address.sin_addr.s_addr = INADDR_ANY

		let bound = withUnsafePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
				bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
			}
		}
		guard bound == 0, listen(fd, 4) == 0 else {
			close(fd)
			return -1
		}
		return fd
	}

	nonisolated private static func _port(of fd: Int32) -> UInt16 {
		var address = sockaddr_in()
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		_ = withUnsafeMutablePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
		}
		return UInt16(bigEndian: address.sin_port)
	}

	nonisolated private static func _isLoopback(_ fd: Int32) -> Bool {
		var peer = sockaddr_in()
		var local = sockaddr_in()
		var length = socklen_t(MemoryLayout<sockaddr_in>.size)
		let peerResult = withUnsafeMutablePointer(to: &peer) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getpeername(fd, $0, &length) }
		}
		length = socklen_t(MemoryLayout<sockaddr_in>.size)
		let localResult = withUnsafeMutablePointer(to: &local) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
		}
		return peerResult == 0 && localResult == 0 && peer.sin_addr.s_addr == local.sin_addr.s_addr
	}

	nonisolated private static func _txtRecord(_ plist: Data) -> Data? {
		guard let entries = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any] else {
			return nil
		}
		var record = Data()
		for (key, value) in entries.sorted(by: { $0.key < $1.key }) {
			let bytes: Data
			switch value {
			case let data as Data: bytes = data
			case let string as String: bytes = Data(string.utf8)
			default: bytes = Data("\(value)".utf8)
			}
			let entry = Data(key.utf8) + Data("=".utf8) + bytes
			guard entry.count <= 255 else { return nil }
			record.append(UInt8(entry.count))
			record.append(entry)
		}
		return record
	}
}
