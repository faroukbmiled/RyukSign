//
//  SettingsDonationCellView.swift
//  RyukSign
//
//  Created by samara on 30.04.2025.
//
#if !NIGHTLY && !DEBUG
import SwiftUI
import NimbleViews
import NimbleExtensions

struct SettingsDonationCellView: View {
	var site: String

	var body: some View {
		Section {
			VStack(spacing: 14) {
				Image(systemName: "heart.fill")
					.font(.system(size: 54))
					.foregroundStyle(.pink)
					.padding(.top, 12)

				VStack(spacing: 4) {
					Text("RyukSign")
						.font(.title3.bold())
					Text(.localized("A modified version of Feather, by Ryuk."))
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}

				Button {
					UIApplication.open(site)
				} label: {
					Text(.localized("Donate to Ryuk"))
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 28)
						.frame(height: 42)
						.background(Color.accentColor, in: Capsule())
				}
				.buttonStyle(.plain)
				.padding(.top, 4)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 8)
		}
	}
}
#endif
