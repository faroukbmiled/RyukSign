//
//  StatusViewModel.swift
//  RyukSign
//
//  Created by samara on 24.04.2025.
//

import Foundation
import Combine
import IDeviceSwift

extension InstallerStatusViewModel {
	var isFailed: Bool {
		switch status {
		case .broken, .completed(.failure): true
		default: false
		}
	}

	var failure: Error? {
		switch status {
		case .broken(let error), .completed(.failure(let error)): error
		default: nil
		}
	}

	var statusImage: String {
		if isFailed { return "exclamationmark.triangle.fill" }

		switch status {
		case .none: return "archivebox.fill"
		case .ready: return "app.gift"
		case .sendingManifest, .sendingPayload: return "paperplane.fill"
		case .installing: return "square.and.arrow.down"
		case .completed, .broken: return "app.badge.checkmark"
		}
	}
	
	var statusLabel: String {
		if isFailed { return .localized("Failed") }

		switch status {
		case .none: return .localized("Packaging")
		case .ready: return .localized("Ready")
		case .sendingManifest: return .localized("Sending Manifest")
		case .sendingPayload: return .localized("Sending Payload")
		case .installing: return .localized("Installing")
		case .completed, .broken: return .localized("Completed")
		}
	}
}
