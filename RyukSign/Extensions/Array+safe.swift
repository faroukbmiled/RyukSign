//
//  Array+safe.swift
//  RyukSign
//
//  Extracted from SourceAppsTableRepresentableView.swift for maintainability.
//

import SwiftUI
import AltSourceKit
import CoreData

// MARK: - Array Extension
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
