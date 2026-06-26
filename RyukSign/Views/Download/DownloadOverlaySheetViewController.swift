//
//  DownloadOverlaySheetViewController.swift
//  RyukSign
//
//  Extracted from DownloadOverlayView.swift for maintainability.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Sheet View Controller
class DownloadOverlaySheetViewController: UIViewController {
    private let downloadManager: DownloadManager
    private let isPresented: Binding<Bool>
    private var hostingController: UIHostingController<DownloadOverlaySheetContent>?

    init(downloadManager: DownloadManager, isPresented: Binding<Bool>) {
        self.downloadManager = downloadManager
        self.isPresented = isPresented
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        updateBackgroundColor()

        let content = DownloadOverlaySheetContent(
            downloadManager: downloadManager,
            isPresented: isPresented
        )

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    private func updateBackgroundColor() {
        let overlayTheme = UserDefaults.standard.string(forKey: "Feather.downloadOverlayTheme") ?? "default"
        let isDarkMode = traitCollection.userInterfaceStyle == .dark

        if overlayTheme == "greyish" {
            view.backgroundColor = isDarkMode ? UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0) : .systemBackground
        } else if overlayTheme == "darkGrey" {
            view.backgroundColor = isDarkMode ? UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0) : .systemBackground
        } else {
            // AMOLED black in dark mode
            view.backgroundColor = isDarkMode ? UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0) : .systemBackground
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBackgroundColor()
        }
    }
}
