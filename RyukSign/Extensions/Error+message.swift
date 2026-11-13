//
//  Error+message.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

extension Error {
	var message: String {
		if self is LocalizedError || (self as NSError).userInfo[NSLocalizedDescriptionKey] != nil {
			return localizedDescription
		}
		// IDeviceSwiftError hides its message.
		if let text = Mirror(reflecting: self).children.first(where: { $0.label == "_message" })?.value as? String, !text.isEmpty {
			return text
		}
		return String(describing: self)
	}
}
