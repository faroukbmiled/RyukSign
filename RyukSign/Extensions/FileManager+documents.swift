//
//  FileManager+documents.swift
//  RyukSign
//
//  Created by samara on 11.04.2025.
//

import Foundation.NSFileManager

extension FileManager {
	/// Gives apps Signed directory
	var archives: URL {
		URL.documentsDirectory.appendingPathComponent("Archives")
	}
	
	/// Gives apps Signed directory
	var signed: URL {
		URL.documentsDirectory.appendingPathComponent("Signed")
	}
	
	/// Gives apps Signed directory with a UUID appending path
	func signed(_ uuid: String) -> URL {
		signed.appendingPathComponent(uuid)
	}
	
	/// Gives apps Unsigned directory
	var unsigned: URL {
		URL.documentsDirectory.appendingPathComponent("Unsigned")
	}
	
	/// Gives apps Unsigned directory with a UUID appending path
	func unsigned(_ uuid: String) -> URL {
		unsigned.appendingPathComponent(uuid)
	}
	
	/// Gives apps Certificates directory
	var certificates: URL {
		URL.documentsDirectory.appendingPathComponent("Certificates")
	}
	/// Gives apps Certificates directory with a UUID appending path
	func certificates(_ uuid: String) -> URL {
		certificates.appendingPathComponent(uuid)
	}

	/// Gives the Tweak Manager library directory
	var tweaksLibrary: URL {
		URL.documentsDirectory.appendingPathComponent("Tweaks")
	}
	/// Gives the Tweak Manager library directory with a tweak ID appending path
	func tweaksLibrary(_ id: String) -> URL {
		tweaksLibrary.appendingPathComponent(id)
	}

	/// Gives the Web Manager inbox directory (uploads land here before routing)
	var webManagerInbox: URL {
		URL.documentsDirectory.appendingPathComponent("WebManager")
	}

	/// A unique temp directory URL (`tmp/<label>_<uuid>`). The caller creates it.
	func uniqueTemporaryDirectory(_ label: String) -> URL {
		temporaryDirectory.appendingPathComponent("\(label)_\(UUID().uuidString)", isDirectory: true)
	}

	/// Best-effort free bytes for an important write here; `nil` if undeterminable (don't block on it).
	func availableImportantCapacity(at url: URL) -> Int64? {
		guard
			let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
			let capacity = values.volumeAvailableCapacityForImportantUsage
		else {
			return nil
		}
		return capacity
	}
}
