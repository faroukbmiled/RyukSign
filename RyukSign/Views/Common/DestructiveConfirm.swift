//
//  DestructiveConfirm.swift
//  RyukSign
//
//  Created by Ryuk
//

import UIKit
import NimbleExtensions

enum DestructiveConfirm {
	static func present(
		title: String,
		message: String = "",
		confirm: @escaping () -> Void
	) {
		let proceed = UIAlertAction(
			title: .localized("Proceed"),
			style: .destructive
		) { _ in
			confirm()
		}

		var body = ""
		if !message.isEmpty { body = message + "\n" }
		body.append(.localized("This action cannot be undone. Would you like to proceed?"))

		UIAlertController.showAlertWithCancel(
			title: title,
			message: body,
			style: UIDevice.current.userInterfaceIdiom == .pad ? .alert : .actionSheet,
			actions: [proceed]
		)
	}
}
