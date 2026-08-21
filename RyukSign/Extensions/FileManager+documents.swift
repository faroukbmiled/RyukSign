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

	/// Gives the log directory
	var logs: URL {
		URL.documentsDirectory.appendingPathComponent("Logs", isDirectory: true)
	}

	/// Where finished downloads are staged before they get imported
	var downloadStaging: URL {
		temporaryDirectory.appendingPathComponent("FeatherDownloads", isDirectory: true)
	}

	/// A unique temp directory URL (`tmp/<label>_<uuid>`). The caller creates it.
	func uniqueTemporaryDirectory(_ label: String) -> URL {
		temporaryDirectory.appendingPathComponent("\(label)_\(UUID().uuidString)", isDirectory: true)
	}

	/// On-disk bytes for a file, or the recursive total for a directory.
	func allocatedSize(at url: URL) -> Int64 {
		let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]

		func size(of item: URL) -> Int64 {
			guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isDirectory != true else { return 0 }
			return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
		}

		guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
			return size(of: url)
		}

		guard let enumerator = enumerator(at: url, includingPropertiesForKeys: keys, options: []) else { return 0 }
		return enumerator.reduce(into: Int64(0)) { total, item in
			if let item = item as? URL { total += size(of: item) }
		}
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
