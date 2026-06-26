//
//  DownloadFormatting.swift
//  RyukSign
//
//  Extracted from DownloadHeaderView.swift for maintainability.
//

import SwiftUI
import Foundation
import Combine
import NimbleExtensions

extension Int64 {
	var formattedByteCount: String {
		ByteCountFormatter.string(fromByteCount: self, countStyle: .binary)
	}

	var formattedFileSize: String {
		ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
	}
}

// MARK: - Date
extension Date {
    func stripTime() -> Date {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return Calendar.current.date(from: components) ?? self
    }
}

struct DownloadNavigationHelper {
    static func handleAppNameTap(for download: Download) {
        let appId = download.id
        AppNavigationManager.shared.navigateToApp(
            appId: appId,
            appName: download.fileName,
            sourceIdentifier: nil
        )
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = Foundation.pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
