//
//  TweakSortOption.swift
//  RyukSign
//

import SwiftUI
import UIKit
import NimbleViews
import NimbleExtensions

// MARK: - Sorting
enum TweakSortOption: String, CaseIterable, Identifiable {
	case nameAZ
	case nameZA
	case dateNewest
	case dateOldest
	case sizeLargest

	var id: String { rawValue }

	var label: String {
		switch self {
		case .nameAZ: 		return .localized("Name (A–Z)")
		case .nameZA: 		return .localized("Name (Z–A)")
		case .dateNewest: 	return .localized("Newest First")
		case .dateOldest: 	return .localized("Oldest First")
		case .sizeLargest: 	return .localized("Largest First")
		}
	}

	var systemImage: String {
		switch self {
		case .nameAZ, .nameZA: 	return "textformat"
		case .dateNewest, .dateOldest: return "calendar"
		case .sizeLargest: 		return "externaldrive"
		}
	}

	var comparator: (ManagedTweak, ManagedTweak) -> Bool {
		switch self {
		case .nameAZ:
			return { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
		case .nameZA:
			return { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
		case .dateNewest:
			return { $0.dateAdded > $1.dateAdded }
		case .dateOldest:
			return { $0.dateAdded < $1.dateAdded }
		case .sizeLargest:
			return { ($0.activeVersion?.fileSize ?? 0) > ($1.activeVersion?.fileSize ?? 0) }
		}
	}
}
