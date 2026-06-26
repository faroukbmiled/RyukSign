//
//  FRAppIconView.swift
//  RyukSign
//
//  Created by samara on 18.04.2025.
//

import SwiftUI

enum FRIconAppearance: Int {
	case light = 0
	case dark = 1
}

@MainActor
final class FRIconCache {
	static let shared = FRIconCache()
	private init() {}

	private let cache = NSCache<NSString, UIImage>()

	/// NSCache purges under memory pressure (which a large install triggers), blanking
	/// the icon mid-render. This bounded LRU keeps recent icons resident so they never flash.
	private var _pinned: [NSString: UIImage] = [:]
	private var _pinnedOrder: [NSString] = []
	private let _pinnedLimit = 24

	private func key(url: URL, appearance: FRIconAppearance, tint: String, isTinted: Bool, dynamic: Bool) -> NSString {
		"\(url.path)#\(appearance.rawValue)#\(tint)#\(isTinted)#\(dynamic)" as NSString
	}

	func image(for url: URL, appearance: FRIconAppearance, tint: String, isTinted: Bool, dynamic: Bool) -> UIImage? {
		let k = key(url: url, appearance: appearance, tint: tint, isTinted: isTinted, dynamic: dynamic)
		if let img = cache.object(forKey: k) { return img }
		if let img = _pinned[k] {
			cache.setObject(img, forKey: k) // repopulate tier 1 after a purge
			// Bump recency so a frequently-shown icon isn't evicted as "oldest".
			if let idx = _pinnedOrder.firstIndex(of: k) {
				_pinnedOrder.remove(at: idx)
				_pinnedOrder.append(k)
			}
			return img
		}
		return nil
	}

	func insert(_ image: UIImage, for url: URL, appearance: FRIconAppearance, tint: String, isTinted: Bool, dynamic: Bool) {
		let k = key(url: url, appearance: appearance, tint: tint, isTinted: isTinted, dynamic: dynamic)
		cache.setObject(image, forKey: k)

		if let idx = _pinnedOrder.firstIndex(of: k) {
			_pinnedOrder.remove(at: idx)
		}
		_pinnedOrder.append(k)
		_pinned[k] = image

		if _pinnedOrder.count > _pinnedLimit {
			let evict = _pinnedOrder.removeFirst()
			_pinned[evict] = nil
		}
	}

	func invalidateAll() {
		cache.removeAllObjects()
		_pinned.removeAll()
		_pinnedOrder.removeAll()
	}
}

@MainActor
final class FRAppIconLoader: ObservableObject {
	@Published var image: UIImage?
	private var task: Task<Void, Never>?

	func load(bundleURL: URL, appearance: FRIconAppearance, tint: String, isTinted: Bool, dynamic: Bool) {
		if let cached = FRIconCache.shared.image(for: bundleURL, appearance: appearance, tint: tint, isTinted: isTinted, dynamic: dynamic) {
			self.image = cached
			return
		}

		task?.cancel()
		task = Task {
			let generated = await Task.detached(priority: .userInitiated) {
				return iconTest(bundleURL)
			}.value

			guard !Task.isCancelled else { return }

			if let generated {
				FRIconCache.shared.insert(generated, for: bundleURL, appearance: appearance, tint: tint, isTinted: isTinted, dynamic: dynamic)
				self.image = generated
			}
		}
	}

	func cancel() {
		task?.cancel()
	}
}

struct FRAppIconView: View {
	private let app: AppInfoPresentable?
	private let size: CGFloat

	@Environment(\.colorScheme) private var colorScheme
	@StateObject private var loader = FRAppIconLoader()

	@AppStorage("Feather.userTintColor") private var selectedColorHex: String = "#848ef9"
	@AppStorage("Feather.shouldTintIcons") private var shouldTintIcons: Bool = false
	@AppStorage("Feather.shouldChangeIconsBasedOffStyle") private var shouldChangeIconsBasedOffStyle: Bool = false

	init(app: AppInfoPresentable? = nil, size: CGFloat = 87) {
		self.app = app
		self.size = size
	}

	private var appearance: FRIconAppearance {
		colorScheme == .dark ? .dark : .light
	}

	private var _bundleURL: URL? {
		if let app {
			return Storage.shared.getAppDirectory(for: app)
		} else {
			return Bundle.main.bundleURL
		}
	}

	/// A fresh loader has `image == nil` until its async `.task` runs; reading the cache
	/// synchronously here shows an already-cached icon without a placeholder flash.
	private var _cachedImage: UIImage? {
		guard let bundleURL = _bundleURL else { return nil }
		return FRIconCache.shared.image(
			for: bundleURL,
			appearance: appearance,
			tint: selectedColorHex,
			isTinted: shouldTintIcons,
			dynamic: shouldChangeIconsBasedOffStyle
		)
	}

	var body: some View {
		Group {
			if let image = loader.image ?? _cachedImage {
				Image(uiImage: image)
					.appIconStyle(size: size)
			} else {
				Image("App_Unknown")
					.appIconStyle(size: size)
			}
		}
		.task(id: "\(appearance.rawValue)\(selectedColorHex)\(shouldTintIcons)\(shouldChangeIconsBasedOffStyle)") {
			_load()
		}
		.onDisappear {
			loader.cancel()
		}
	}

	private func _load() {
		guard let bundleURL = _bundleURL else { return }

		loader.load(
			bundleURL: bundleURL,
			appearance: appearance,
			tint: selectedColorHex,
			isTinted: shouldTintIcons,
			dynamic: shouldChangeIconsBasedOffStyle
		)
	}
}
