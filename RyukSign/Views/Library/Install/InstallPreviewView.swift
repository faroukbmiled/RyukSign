//
//  InstallPreview.swift
//  RyukSign
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss

	@StateObject private var _installer: AppInstaller

	var app: AppInfoPresentable

	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		__installer = StateObject(wrappedValue: AppInstaller(app: app, isSharing: isSharing))
	}

	// MARK: Body
	var body: some View {
		ZStack {
			InstallProgressView(app: app, viewModel: _installer.viewModel)
			_status()
			_button()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(NBRadius.large)
		.padding([.top, .horizontal])
		.padding(.bottom, 36)
		.ignoresSafeArea(.container, edges: .bottom)
		.sheet(isPresented: $_installer.isPresentingFallbackPage) {
			if let url = _installer.fallbackPageURL {
				SafariRepresentableView(url: url).ignoresSafeArea()
			}
		}
		.onAppear { _installer.start(completion: _handle) }
		.onDisappear { _installer.stop() }
	}

	@ViewBuilder
	private func _status() -> some View {
		Label(_installer.viewModel.statusLabel, systemImage: _installer.viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: _installer.viewModel.statusImage)
	}

	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if _installer.viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton("Open", systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: _installer.viewModel.isCompleted)
	}

	private func _handle(_ result: Result<AppInstaller.Outcome, Error>) {
		switch result {
		case .success(.installed):
			break
		case .success(.exported(let package)):
			dismiss()
			if let package {
				UIActivityViewController.show(activityItems: [package])
			}
		case .failure(let error):
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: String(describing: error),
				action: {
					HeartbeatManager.shared.start(true)
					dismiss()
				}
			)
		}
	}
}
