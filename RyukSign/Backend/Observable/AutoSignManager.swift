//
//  AutoSignManager.swift
//  RyukSign
//
//  Created by Ryuk on 24.08.2026.
//

import Foundation
import SwiftUI

@MainActor
final class AutoSignManager {
	static let shared = AutoSignManager()

	static let enabledKey = "Feather.autoSignAfterImport"

	private var _tail: Task<Void, Never> = Task {}

	private init() {}

	nonisolated static var isEnabled: Bool {
		UserDefaults.standard.bool(forKey: enabledKey)
	}

	/// True when the saved options can produce a signed app without asking anything.
	nonisolated static var canSign: Bool {
		OptionsManager.shared.options.signingOption != .default || _certificate() != nil
	}

	/// One app at a time. Signing is memory heavy and `SigningLog` is a single shared console.
	func sign(_ app: AppInfoPresentable, installs: Bool) async -> Result<Signed, Error> {
		let previous = _tail
		let job = Task { () -> Result<Signed, Error> in
			await previous.value
			return await Self._perform(app, installs: installs)
		}

		_tail = Task { _ = await job.value }
		return await job.value
	}

	private static func _perform(_ app: AppInfoPresentable, installs: Bool) async -> Result<Signed, Error> {
		let options = Options.batchBase.resolved(for: app)
		let certificate = _certificate()

		guard options.signingOption != .default || certificate != nil else {
			return .failure(AutoSignError.noCertificate)
		}

		let result = await withCheckedContinuation { continuation in
			FR.signPackageFile(app, using: options, icon: nil, certificate: certificate) {
				continuation.resume(returning: $0)
			}
		}

		guard case .success(let signed) = result else { return result }

		// The unsigned copy only existed to feed the signer.
		Storage.shared.deleteApp(for: app)

		if installs {
			InstallQueue.shared.enqueue(signed)
		}

		return result
	}

	nonisolated private static func _certificate() -> CertificatePair? {
		Storage.shared.getCertificate(for: UserDefaults.standard.integer(forKey: "feather.selectedCert"))
	}
}

extension AutoSignManager {
	enum Action: String, CaseIterable {
		case keep, sign, install

		static var current: Self {
			guard isEnabled else { return .keep }
			return OptionsManager.shared.options.post_installAppAfterSigned ? .install : .sign
		}

		var title: String {
			switch self {
			case .keep: .localized("Add to Library")
			case .sign: .localized("Sign")
			case .install: .localized("Sign & Install")
			}
		}

		var systemImage: String {
			switch self {
			case .keep: "square.and.arrow.down"
			case .sign: "signature"
			case .install: "square.and.arrow.down.on.square"
			}
		}
	}
}

enum AutoSignError: LocalizedError {
	case noCertificate

	var errorDescription: String? {
		switch self {
		case .noCertificate: return .localized("Auto sign needs a certificate. Import one in Settings, or turn auto sign off.")
		}
	}
}
