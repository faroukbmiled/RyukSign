//
//  NBContentUnavailable.swift
//  NimbleKit
//
//  A ContentUnavailableView wrapper that falls back to a hand-built empty state
//  on iOS 16 (ContentUnavailableView is iOS 17+), so empty screens are never blank.
//

import SwiftUI

public struct NBContentUnavailable<Actions: View>: View {
	private let title: String
	private let systemImage: String
	private let description: String
	private let actions: Actions

	public init(
		_ title: String,
		systemImage: String,
		description: String,
		@ViewBuilder actions: () -> Actions = { EmptyView() }
	) {
		self.title = title
		self.systemImage = systemImage
		self.description = description
		self.actions = actions()
	}

	public var body: some View {
		if #available(iOS 17, *) {
			ContentUnavailableView {
				Label(title, systemImage: systemImage)
			} description: {
				Text(description)
			} actions: {
				actions
			}
		} else {
			VStack(spacing: 10) {
				Image(systemName: systemImage)
					.font(.system(size: 52))
					.foregroundStyle(.secondary)
				Text(title)
					.font(.title2.weight(.bold))
					.multilineTextAlignment(.center)
				Text(description)
					.font(.callout)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
				actions
					.padding(.top, 4)
			}
			.padding(24)
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}
}
