//
//  FileExporter.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import Zip

enum FileExporter {
	/// A file shares as-is; a directory bundle (e.g. `.framework`) has to be zipped first.
	static func shareableURL(for source: URL) -> URL? {
		let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
		guard isDirectory else { return source }

		let exportDir = FileManager.default.uniqueTemporaryDirectory("FileExport")
		let zipURL = exportDir.appendingPathComponent("\(source.lastPathComponent).zip")
		do {
			try FileManager.default.createDirectoryIfNeeded(at: exportDir)
			try Zip.zipFiles(paths: [source], zipFilePath: zipURL, password: nil, progress: nil)
			return zipURL
		} catch {
			return nil
		}
	}
}
