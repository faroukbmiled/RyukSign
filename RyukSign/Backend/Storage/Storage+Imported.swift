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
}
