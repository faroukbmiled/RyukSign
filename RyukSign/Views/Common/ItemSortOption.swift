//
//  ItemSortOption.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import NimbleExtensions

protocol SortableItem {
	var sortName: String { get }
	var sortDate: Date { get }
	var sortSize: Int64 { get }
}

enum ItemSortOption: String, CaseIterable, Identifiable {
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

	func comparator<T: SortableItem>() -> (T, T) -> Bool {
		switch self {
		case .nameAZ:
			return { $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedAscending }
		case .nameZA:
			return { $0.sortName.localizedCaseInsensitiveCompare($1.sortName) == .orderedDescending }
		case .dateNewest:
			return { $0.sortDate > $1.sortDate }
		case .dateOldest:
			return { $0.sortDate < $1.sortDate }
		case .sizeLargest:
			return { $0.sortSize > $1.sortSize }
		}
	}
}
