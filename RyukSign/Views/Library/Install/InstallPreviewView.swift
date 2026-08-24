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
			InstallStatusView(app: app, viewModel: _installer.viewModel)
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

// MARK: - View: Status
/// Observes the status model directly
private struct InstallStatusView: View {
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel

	var body: some View {
		ZStack {
			_status()
			_button()
		}
	}

	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}

	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if viewModel.isCompleted {
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
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
}
