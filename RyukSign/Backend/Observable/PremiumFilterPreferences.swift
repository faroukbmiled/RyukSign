//
//  PremiumFilterPreferences.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

enum PremiumCatalogFilter: String, CaseIterable, Identifiable {
	case all
	case latest
	case since

	var id: String { rawValue }

	var title: String {
		switch self {
		case .all: return .localized("All Apps")
		case .latest: return .localized("Latest Apps")
		case .since: return .localized("Updated Since")
		}
	}

	var icon: String {
		switch self {
		case .all: return "square.stack.3d.up.fill"
		case .latest: return "clock.arrow.circlepath"
		case .since: return "calendar"
		}
	}

	var footer: String {
		switch self {
		case .all: return .localized("Every app in your premium repositories is downloaded.")
		case .latest: return .localized("Only the newest apps are sent by the repository server, so premium repositories load much faster.")
		case .since: return .localized("Only apps updated on or after this date are sent by the repository server.")
		}
	}
}

@MainActor
final class PremiumFilterPreferences: ObservableObject {
	static let shared = PremiumFilterPreferences()

	static let limitPresets = [250, 500, 1000, 2500, 5000]
	static let maximumLimit = 100_000

	@Published var mode: PremiumCatalogFilter { didSet { _save() } }
	@Published var limit: Int { didSet { _save() } }
	@Published var sinceDate: Date { didSet { _save() } }

	private static let _modeKey = "RyukSign.premiumFilter.mode"
	private static let _limitKey = "RyukSign.premiumFilter.limit"
	private static let _sinceKey = "RyukSign.premiumFilter.since"

	private static let _dateFormatter: DateFormatter = {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.dateFormat = "yyyy-MM-dd"
		return formatter
	}()

	private init() {
		let defaults = UserDefaults.standard
		mode = PremiumCatalogFilter(rawValue: defaults.string(forKey: Self._modeKey) ?? "") ?? .all

		let storedLimit = defaults.integer(forKey: Self._limitKey)
		limit = storedLimit > 0 ? storedLimit : 1000

		let storedSince = defaults.double(forKey: Self._sinceKey)
		sinceDate = storedSince > 0
			? Date(timeIntervalSince1970: storedSince)
			: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
	}

	var clampedLimit: Int {
		min(max(limit, 1), Self.maximumLimit)
	}

	var queryItems: [URLQueryItem] {
		switch mode {
		case .all:
			return []
		case .latest:
			return [URLQueryItem(name: "limit", value: String(clampedLimit))]
		case .since:
			return [URLQueryItem(name: "since", value: Self._dateFormatter.string(from: sinceDate))]
		}
	}

	/// Identity of the request the client would make, so callers can watch for changes.
	var stamp: String {
		queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
	}

	var summary: String {
		switch mode {
		case .all:
			return .localized("All Apps")
		case .latest:
			return .localized("Latest %lld apps", arguments: clampedLimit)
		case .since:
			return .localized("Since %@", arguments: DateFormatter.localizedString(from: sinceDate, dateStyle: .medium, timeStyle: .none))
		}
	}

	private func _save() {
		let defaults = UserDefaults.standard
		defaults.set(mode.rawValue, forKey: Self._modeKey)
		defaults.set(clampedLimit, forKey: Self._limitKey)
		defaults.set(sinceDate.timeIntervalSince1970, forKey: Self._sinceKey)
	}
}
