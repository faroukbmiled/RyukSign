//
//  Storage+Imported.swift
//  RyukSign
//
//  Created by samara on 11.04.2025.
//

import CoreData
import UIKit.UIImpactFeedbackGenerator

// MARK: - Class extension: Imported Apps
extension Storage {
    func addImported(
        uuid: String,
        source: URL? = nil,

        appName: String? = nil,
        appIdentifier: String? = nil,
        appVersion: String? = nil,
        appIcon: String? = nil,
        appDescription: String? = nil,

        completion: @escaping (Error?) -> Void
    ) {
        let generator = UIImpactFeedbackGenerator(style: .light)

        let new = Imported(context: context)

        new.uuid = uuid
        new.source = source
        new.date = Date()
        new.sortIndex = nextImportedSortIndex()

        new.originalIdentifier = appIdentifier
        new.identifier = appIdentifier

        new.name = appName
        new.icon = appIcon
        new.version = appVersion
        new.appDescription = appDescription

        saveContext()
        generator.impactOccurred()
        completion(nil)
    }

    // Below the current lowest so new apps land at the top
    func nextImportedSortIndex() -> Int32 {
        let request: NSFetchRequest<Imported> = Imported.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: true)]
        request.fetchLimit = 1

        let lowest = (try? context.fetch(request))?.first?.sortIndex ?? 1
        return lowest - 1
    }
}
