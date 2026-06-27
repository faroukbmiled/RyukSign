//
//  ArchiveEngine.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import Zip
import ZIPFoundation

enum ArchiveBackend: Int, CaseIterable {
	case zip
	case zipFoundation

	static let storageKey = "RyukSign.archiveBackend"

	static var current: ArchiveBackend {
		ArchiveBackend(rawValue: UserDefaults.standard.integer(forKey: storageKey)) ?? .zip
	}

	var label: String {
		switch self {
		case .zip: "Zip"
		case .zipFoundation: "ZIPFoundation"
		}
	}

	var engine: ArchiveEngine {
		switch self {
		case .zip: ZipArchiveEngine()
		case .zipFoundation: ZipFoundationArchiveEngine()
		}
	}
}

protocol ArchiveEngine {
	func zip(directory: URL, to destination: URL, compression: ZipCompression, progress: ((Double) -> Void)?) throws
}

struct ZipArchiveEngine: ArchiveEngine {
	func zip(directory: URL, to destination: URL, compression: ZipCompression, progress: ((Double) -> Void)?) throws {
		try Zip.zipFiles(paths: [directory], zipFilePath: destination, password: nil, compression: compression, progress: progress)
	}
}

struct ZipFoundationArchiveEngine: ArchiveEngine {
	func zip(directory: URL, to destination: URL, compression: ZipCompression, progress: ((Double) -> Void)?) throws {
		let method: CompressionMethod = compression == .NoCompression ? .none : .deflate

		var observation: NSKeyValueObservation?
		var reported: Progress?
		if let progress {
			let tracker = Progress(totalUnitCount: 1)
			observation = tracker.observe(\.fractionCompleted, options: [.new]) { tracker, _ in
				progress(tracker.fractionCompleted)
			}
			reported = tracker
		}
		defer { observation?.invalidate() }

		try FileManager.default.zipItem(
			at: directory,
			to: destination,
			shouldKeepParent: true,
			compressionMethod: method,
			progress: reported
		)
	}
}
