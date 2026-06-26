//
//  SelectionActionBar.swift
//  RyukSign
//
//  A reusable floating action bar for multi-select modes. Rendered via
//  `.safeAreaInset(edge: .bottom)` so it sits above the tab bar / home indicator
//  and never hides list rows (unlike a `.bottomBar` toolbar item, which the
//  native tab bar covers).
//

import SwiftUI

struct SelectionBarAction: Identifiable {
	let id = UUID()
	let title: String
	let systemImage: String
	var role: ButtonRole? = nil
	var enabled: Bool = true
	let action: () -> Void
}

struct SelectionActionBar: View {
	let actions: [SelectionBarAction]

	var body: some View {
		HStack(spacing: 2) {
			ForEach(actions) { action in
				Button(role: action.role) {
					action.action()
				} label: {
					VStack(spacing: 3) {
						Image(systemName: action.systemImage)
							.font(.system(size: 18))
						Text(action.title)
							.font(.caption2)
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity)
					.foregroundStyle(action.role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
					.opacity(action.enabled ? 1 : 0.35)
					.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.disabled(!action.enabled)
			}
		}
		.padding(.vertical, 10)
		.padding(.horizontal, 6)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.strokeBorder(Color.primary.opacity(0.08))
		)
		.shadow(color: .black.opacity(0.18), radius: 14, y: 4)
		.padding(.horizontal, 12)
		.padding(.bottom, 6)
	}
}

extension View {
	/// Overlays a floating selection action bar pinned above the bottom safe area.
	@ViewBuilder
	func selectionActionBar(isActive: Bool, actions: [SelectionBarAction]) -> some View {
		safeAreaInset(edge: .bottom) {
			if isActive {
				SelectionActionBar(actions: actions)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
	}
}
