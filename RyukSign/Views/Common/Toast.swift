//
//  Toast.swift
//  RyukSign
//
//  A tiny shared toast/HUD system. Call `Toast.success("…")` from anywhere; a single
//  banner shows at the top of the window, queued (never stacked), de-duplicated, with
//  optional haptics. Attach `.toastLayer()` once at the app root.
//

import SwiftUI
import UIKit
import NimbleExtensions

// MARK: - Model

enum ToastHaptic {
	case success, error, light, none

	func fire() {
		switch self {
		case .success: NBHaptic.notify(.success)
		case .error: NBHaptic.notify(.error)
		case .light: NBHaptic.tap()
		case .none: break
		}
	}
}

/// How long a toast stays before auto-dismissing; `.sticky` stays until swiped/tapped away.
enum ToastDuration {
	case short, normal, long, sticky

	var seconds: TimeInterval? {
		switch self {
		case .short: return 1.6
		case .normal: return 2.4
		case .long: return 5.0
		case .sticky: return nil
		}
	}
}

struct ToastItem: Identifiable, Equatable {
	let id = UUID()
	let message: String
	let systemImage: String
	let tint: Color
	let haptic: ToastHaptic
	/// Auto-dismiss delay; `nil` means sticky (dismiss only via swipe/tap).
	let duration: TimeInterval?

	static func == (lhs: ToastItem, rhs: ToastItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Manager

final class ToastManager: ObservableObject {
	static let shared = ToastManager()

	@Published private(set) var current: ToastItem?

	/// Live banner frame — lets the toast window pass touches through except over the banner.
	var bannerFrame: CGRect = .zero

	private var _queue: [ToastItem] = []
	private var _dismissWork: DispatchWorkItem?

	private init() {}

	func show(
		_ message: String,
		systemImage: String = "checkmark.circle.fill",
		tint: Color = .accentColor,
		haptic: ToastHaptic = .success,
		duration: ToastDuration = .normal
	) {
		let item = ToastItem(message: message, systemImage: systemImage, tint: tint, haptic: haptic, duration: duration.seconds)

		DispatchQueue.main.async {
			ToastWindowManager.shared.ensure()
			// Dedup: extend if already showing, drop if already queued next.
			if self.current?.message == message {
				if let secs = item.duration { self._scheduleDismiss(after: secs) }
				return
			}
			if self._queue.last?.message == message { return }

			self._queue.append(item)
			if self._queue.count > 4 { self._queue.removeFirst(self._queue.count - 4) }

			// Hop a runloop so the host renders empty first — makes the first toast animate in.
			if self.current == nil {
				DispatchQueue.main.async { self._presentNext() }
			}
		}
	}

	func dismiss() {
		_dismissWork?.cancel()
		_advance()
	}

	// MARK: Internal

	private func _presentNext() {
		guard current == nil, !_queue.isEmpty else { return }
		let item = _queue.removeFirst()
		withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
			current = item
		}
		item.haptic.fire()
		// Sticky toasts (nil duration) only leave on swipe/tap.
		if let secs = item.duration {
			_scheduleDismiss(after: secs)
		} else {
			_dismissWork?.cancel()
		}
	}

	private func _scheduleDismiss(after duration: TimeInterval) {
		_dismissWork?.cancel()
		let work = DispatchWorkItem { [weak self] in self?._advance() }
		_dismissWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
	}

	private func _advance() {
		withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
			current = nil
		}
		bannerFrame = .zero
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
			self?._presentNext()
		}
	}
}

// MARK: - Convenience

enum Toast {
	static func success(_ message: String, systemImage: String = "checkmark.circle.fill", duration: ToastDuration = .normal) {
		ToastManager.shared.show(message, systemImage: systemImage, tint: .green, haptic: .success, duration: duration)
	}
	static func error(_ message: String, systemImage: String = "exclamationmark.triangle.fill", duration: ToastDuration = .long) {
		ToastManager.shared.show(message, systemImage: systemImage, tint: .red, haptic: .error, duration: duration)
	}
	static func info(_ message: String, systemImage: String = "info.circle.fill", duration: ToastDuration = .normal) {
		ToastManager.shared.show(message, systemImage: systemImage, tint: .accentColor, haptic: .light, duration: duration)
	}
}

// MARK: - View

struct ToastBanner: View {
	let item: ToastItem
	var onDismiss: () -> Void

	@State private var _offset: CGSize = .zero
	@State private var _iconPop = false
	@State private var _textIn = false

	private var _dragOpacity: Double {
		let distance = hypot(_offset.width, _offset.height)
		return 1.0 - Double(min(distance / 220, 0.7))
	}

	var body: some View {
		HStack(spacing: 11) {
			Image(systemName: item.systemImage)
				.font(.system(size: 16, weight: .semibold))
				.foregroundStyle(.white)
				.frame(width: 30, height: 30)
				.background(item.tint.gradient, in: Circle())
				.shadow(color: item.tint.opacity(0.45), radius: 5, y: 2)
				.scaleEffect(_iconPop ? 1 : 0.3)
				.rotationEffect(.degrees(_iconPop ? 0 : -35))
				.opacity(_iconPop ? 1 : 0)

			Text(item.message)
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.primary)
				.lineLimit(2)
				.fixedSize(horizontal: false, vertical: true)
				.opacity(_textIn ? 1 : 0)
				.offset(x: _textIn ? 0 : -8)
		}
		.padding(.leading, 10)
		.padding(.trailing, 18)
		.padding(.vertical, 9)
		.background(
			Capsule(style: .continuous)
				.fill(.ultraThinMaterial)
				.overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
		)
		.shadow(color: .black.opacity(0.22), radius: 16, y: 6)
		.padding(.horizontal, 20)
		.contentShape(Capsule())
		.background(
			GeometryReader { geo in
				Color.clear
					.onAppear { ToastManager.shared.bannerFrame = geo.frame(in: .global) }
					.onChange(of: geo.frame(in: .global)) { ToastManager.shared.bannerFrame = $0 }
			}
		)
		.offset(_offset)
		.opacity(_dragOpacity)
		.onTapGesture { onDismiss() }
		.gesture(
			DragGesture()
				.onChanged { _offset = $0.translation }
				.onEnded { value in
					// Fling away in whatever direction the user swiped.
					let distance = hypot(value.translation.width, value.translation.height)
					if distance > 44 {
						withAnimation(.easeOut(duration: 0.2)) {
							_offset = CGSize(width: value.translation.width * 4, height: value.translation.height * 4)
						}
						DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { onDismiss() }
					} else {
						withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { _offset = .zero }
					}
				}
		)
		.onAppear {
			withAnimation(.spring(response: 0.5, dampingFraction: 0.5).delay(0.08)) { _iconPop = true }
			withAnimation(.easeOut(duration: 0.28).delay(0.12)) { _textIn = true }
		}
	}
}

/// The SwiftUI content hosted by the toast window — a top-anchored banner.
private struct ToastHostView: View {
	@ObservedObject private var manager = ToastManager.shared

	var body: some View {
		VStack(spacing: 0) {
			if let item = manager.current {
				ToastBanner(item: item, onDismiss: { manager.dismiss() })
					.padding(.top, 8)
					.transition(.asymmetric(
						insertion: .scale(scale: 0.82, anchor: .top)
							.combined(with: .offset(y: -34))
							.combined(with: .opacity),
						removal: .scale(scale: 0.92, anchor: .top)
							.combined(with: .offset(y: -16))
							.combined(with: .opacity)
					))
					.id(item.id)
			}
			Spacer(minLength: 0)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.animation(.spring(response: 0.45, dampingFraction: 0.62), value: manager.current?.id)
	}
}

/// A transparent window that floats above sheets / full-screen covers so toasts are
/// visible from anywhere. Touches pass straight through except over the banner.
private final class ToastPassthroughWindow: UIWindow {
	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		// Gate on a live toast — a stale bannerFrame must never keep eating taps once the banner is gone.
		let manager = ToastManager.shared
		guard manager.current != nil, manager.bannerFrame.contains(point) else { return nil }
		return super.hitTest(point, with: event)
	}
}

final class ToastWindowManager {
	static let shared = ToastWindowManager()
	private var _window: UIWindow?
	private var _retries = 0

	private init() {}

	/// Lazily creates the overlay window on a foreground scene. On cold launch via a shared
	/// file no scene is `.foregroundActive` yet, so fall back to any scene and retry briefly —
	/// otherwise the toast is silently dropped (only the window-independent haptic fires).
	func ensure() {
		guard _window == nil else { return }

		let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
		guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
			?? scenes.first(where: { $0.activationState == .foregroundInactive })
			?? scenes.first
		else {
			// No window scene yet — retry shortly (bounded).
			guard _retries < 20 else { return }
			_retries += 1
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.ensure() }
			return
		}

		_retries = 0

		let host = UIHostingController(rootView: ToastHostView())
		host.view.backgroundColor = .clear
		host.view.isOpaque = false

		let window = ToastPassthroughWindow(windowScene: scene)
		window.windowLevel = .alert + 1
		window.backgroundColor = .clear
		window.isOpaque = false
		window.rootViewController = host
		window.isHidden = false

		_window = window
	}
}
