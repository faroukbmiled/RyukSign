//
//  DownloadOverlaySheetWrapper.swift
//  RyukSign
//
//  Extracted from DownloadBubbleView.swift for maintainability.
//

import SwiftUI
import Foundation
import Combine

// MARK: - UISheetPresentationController Wrapper
struct DownloadOverlaySheetWrapper: UIViewControllerRepresentable {
    @ObservedObject var downloadManager: DownloadManager
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> SheetHostViewController {
        let viewController = SheetHostViewController()
        viewController.view.backgroundColor = .clear
        viewController.coordinator = context.coordinator
        return viewController
    }

    func updateUIViewController(_ uiViewController: SheetHostViewController, context: Context) {
        let activeDownloads = downloadManager.downloads.filter { $0.isActive || $0.progress > 0 || $0.unpackageProgress > 0 }

        DispatchQueue.main.async {
            if isPresented && uiViewController.presentedViewController == nil {
                let sheetVC = DownloadOverlaySheetViewController(
                    downloadManager: downloadManager,
                    isPresented: $isPresented
                )

                if let sheet = sheetVC.sheetPresentationController {
                    sheet.prefersGrabberVisible = false
                    sheet.preferredCornerRadius = 24
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                    sheet.prefersEdgeAttachedInCompactHeight = true
                    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true

                    let detents = context.coordinator.createDetents(for: activeDownloads.count)
                    sheet.detents = detents
                    sheet.selectedDetentIdentifier = detents.first?.identifier
                    sheet.largestUndimmedDetentIdentifier = nil
                }

                sheetVC.sheetPresentationController?.delegate = context.coordinator
                context.coordinator.sheetViewController = sheetVC

                uiViewController.present(sheetVC, animated: true)
            } else if !isPresented && uiViewController.presentedViewController != nil {
                uiViewController.dismiss(animated: true)
            } else if let sheetVC = uiViewController.presentedViewController as? DownloadOverlaySheetViewController {
                context.coordinator.updateDetents(for: activeDownloads.count, sheetVC: sheetVC)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(downloadManager: downloadManager, isPresented: $isPresented)
    }
}

// MARK: - Sheet Host View Controller
class SheetHostViewController: UIViewController {
    weak var coordinator: DownloadOverlaySheetWrapper.Coordinator?
}

// MARK: - Coordinator
extension DownloadOverlaySheetWrapper {
    class Coordinator: NSObject, UISheetPresentationControllerDelegate {
        var downloadManager: DownloadManager
        var isPresented: Binding<Bool>
        weak var sheetViewController: DownloadOverlaySheetViewController?

        private var lastDownloadCount: Int = 0

        init(downloadManager: DownloadManager, isPresented: Binding<Bool>) {
            self.downloadManager = downloadManager
            self.isPresented = isPresented
            self.lastDownloadCount = 0
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            isPresented.wrappedValue = false
        }

        func createDetents(for downloadCount: Int) -> [UISheetPresentationController.Detent] {
            let dynamicOverlaySize = UserDefaults.standard.object(forKey: "Feather.dynamicOverlaySize") as? Bool ?? true
            let height = calculateHeight(for: downloadCount, dynamicEnabled: dynamicOverlaySize)

            let detent = UISheetPresentationController.Detent.custom { context in
                return height
            }

            return [detent]
        }

        func updateDetents(for downloadCount: Int, sheetVC: DownloadOverlaySheetViewController) {
            let dynamicOverlaySize = UserDefaults.standard.object(forKey: "Feather.dynamicOverlaySize") as? Bool ?? true

            if dynamicOverlaySize {
                guard downloadCount != lastDownloadCount else { return }
            }
            lastDownloadCount = downloadCount

            guard let sheet = sheetVC.sheetPresentationController else { return }

            let height = calculateHeight(for: downloadCount, dynamicEnabled: dynamicOverlaySize)

            let detent = UISheetPresentationController.Detent.custom { context in
                return height
            }

            // Delay the height update so the fade animation finishes first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                sheet.animateChanges {
                    sheet.detents = [detent]
                    sheet.selectedDetentIdentifier = detent.identifier
                }
            }
        }

        private func calculateHeight(for downloadCount: Int, dynamicEnabled: Bool = true) -> CGFloat {
            let itemHeight: CGFloat = 110
            let headerHeight: CGFloat = 115
            let bottomPadding: CGFloat = 10
            let maxOverlayHeight: CGFloat = 800

            let screenHeight = UIScreen.main.bounds.height

            guard dynamicEnabled else {
                return min(maxOverlayHeight, screenHeight - 150)
            }

            if downloadCount == 0 {
                return 280
            }

            let count = CGFloat(downloadCount)
            let calculatedHeight = headerHeight + (itemHeight * count) + bottomPadding

            return min(calculatedHeight, maxOverlayHeight)
        }
    }
}
