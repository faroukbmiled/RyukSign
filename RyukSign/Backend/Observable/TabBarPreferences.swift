//
//  TabBarPreferences.swift
//  RyukSign
//
//  Source of truth for tab bar order, visibility and default launch tab. Default
//  tabs carry no native `.customizationID`, so order is purely the ForEach order —
//  no conflict with `.tabViewCustomization` (which only governs Certificates + Sources).
//

import Foundation

final class TabBarPreferences: ObservableObject {
	static let shared = TabBarPreferences()

	/// `settings` excluded so the user can always reach this screen to undo changes.
	static let hideableTabs: [TabEnum] = [.sources, .library, .tweaks]

	@Published private(set) var order: [TabEnum]
	@Published private(set) var hidden: Set<TabEnum>
	@Published var defaultLaunch: TabEnum {
		didSet { _save() }
	}

	private let _key = "Feather.tabBarPreferences"

	private struct Stored: Codable {
		var order: [String]
		var hidden: [String]
		var defaultLaunch: String

		init(order: [String], hidden: [String], defaultLaunch: String) {
			self.order = order
			self.hidden = hidden
			self.defaultLaunch = defaultLaunch
		}

		// Tolerant so a future non-optional field can't fail the whole decode and reset the bar.
		init(from decoder: Decoder) throws {
			let c = try decoder.container(keyedBy: CodingKeys.self)
			order = try c.decodeIfPresent([String].self, forKey: .order) ?? []
			hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
			defaultLaunch = try c.decodeIfPresent(String.self, forKey: .defaultLaunch) ?? TabEnum.library.rawValue
		}
	}

	private init() {
		let defaults = UserDefaults.standard

		var loadedOrder = TabEnum.defaultTabs
		var loadedHidden: Set<TabEnum> = []
		var loadedLaunch: TabEnum = .library

		if
			let data = defaults.data(forKey: _key),
			let stored = try? JSONDecoder().decode(Stored.self, from: data)
		{
			loadedOrder = stored.order.compactMap { TabEnum(rawValue: $0) }
			loadedHidden = Set(stored.hidden.compactMap { TabEnum(rawValue: $0) })
			loadedLaunch = TabEnum(rawValue: stored.defaultLaunch) ?? .library
		} else if defaults.object(forKey: "Feather.showTweaksTab") != nil,
				  defaults.bool(forKey: "Feather.showTweaksTab") == false {
			// Migrate the old showTweaksTab toggle.
			loadedHidden = [.tweaks]
		}

		self.order = loadedOrder
		self.hidden = loadedHidden
		self.defaultLaunch = loadedLaunch

		_normalize()
	}

	// MARK: Derived

	/// Default tabs in saved order (stale dropped, new appended).
	var orderedTabs: [TabEnum] {
		var result = order.filter { TabEnum.defaultTabs.contains($0) }
		for tab in TabEnum.defaultTabs where !result.contains(tab) {
			result.append(tab)
		}
		return result
	}

	var visibleTabs: [TabEnum] {
		orderedTabs.filter { !hidden.contains($0) }
	}

	func isHideable(_ tab: TabEnum) -> Bool {
		Self.hideableTabs.contains(tab)
	}

	func isHidden(_ tab: TabEnum) -> Bool {
		hidden.contains(tab)
	}

	/// Launch tab, guaranteed currently visible.
	var resolvedLaunchTab: TabEnum {
		visibleTabs.contains(defaultLaunch) ? defaultLaunch : (visibleTabs.first ?? .library)
	}

	// MARK: Mutations

	func setHidden(_ tab: TabEnum, _ value: Bool) {
		guard isHideable(tab) else { return }
		if value { hidden.insert(tab) } else { hidden.remove(tab) }
		_normalize()
		_save()
	}

	func move(from source: IndexSet, to destination: Int) {
		var current = orderedTabs
		current.move(fromOffsets: source, toOffset: destination)
		order = current
		_save()
	}

	// MARK: Internal

	private func _normalize() {
		order = orderedTabs
		if !visibleTabs.contains(defaultLaunch) {
			defaultLaunch = visibleTabs.first ?? .library
		}
	}

	private func _save() {
		let stored = Stored(
			order: orderedTabs.map { $0.rawValue },
			hidden: hidden.map { $0.rawValue },
			defaultLaunch: defaultLaunch.rawValue
		)
		if let data = try? JSONEncoder().encode(stored) {
			UserDefaults.standard.set(data, forKey: _key)
		}
		objectWillChange.send()
	}
}
