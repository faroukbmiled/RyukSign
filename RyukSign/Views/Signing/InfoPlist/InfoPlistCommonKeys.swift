//
//  InfoPlistCommonKeys.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

struct InfoPlistCommonKey: Identifiable {
	let key: String
	let value: Any

	var id: String { key }
}

/// Keys worth reaching for when patching an app, grouped the way they're usually needed.
enum InfoPlistCommonKeys {
	static var groups: [(title: String, keys: [InfoPlistCommonKey])] {
		[
			(.localized("Network"), [
				InfoPlistCommonKey(key: "NSAppTransportSecurity", value: ["NSAllowsArbitraryLoads": true]),
				InfoPlistCommonKey(key: "NSLocalNetworkUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSBonjourServices", value: [String]()),
				InfoPlistCommonKey(key: "UIRequiresPersistentWiFi", value: true)
			]),
			(.localized("Privacy"), [
				InfoPlistCommonKey(key: "NSCameraUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSMicrophoneUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSPhotoLibraryUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSPhotoLibraryAddUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSLocationWhenInUseUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSLocationAlwaysAndWhenInUseUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSContactsUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSFaceIDUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSBluetoothAlwaysUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSMotionUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSSpeechRecognitionUsageDescription", value: ""),
				InfoPlistCommonKey(key: "NSUserTrackingUsageDescription", value: "")
			]),
			(.localized("Interface"), [
				InfoPlistCommonKey(key: "UIStatusBarHidden", value: true),
				InfoPlistCommonKey(key: "UIViewControllerBasedStatusBarAppearance", value: false),
				InfoPlistCommonKey(key: "UIStatusBarStyle", value: "UIStatusBarStyleDefault"),
				InfoPlistCommonKey(key: "UISupportedInterfaceOrientations", value: [
					"UIInterfaceOrientationPortrait",
					"UIInterfaceOrientationLandscapeLeft",
					"UIInterfaceOrientationLandscapeRight"
				]),
				InfoPlistCommonKey(key: "UISupportedInterfaceOrientations~ipad", value: [
					"UIInterfaceOrientationPortrait",
					"UIInterfaceOrientationPortraitUpsideDown",
					"UIInterfaceOrientationLandscapeLeft",
					"UIInterfaceOrientationLandscapeRight"
				]),
				InfoPlistCommonKey(key: "UIPrerenderedIcon", value: true)
			]),
			(.localized("Capabilities"), [
				InfoPlistCommonKey(key: "LSSupportsOpeningDocumentsInPlace", value: true),
				InfoPlistCommonKey(key: "LSApplicationQueriesSchemes", value: [String]()),
				InfoPlistCommonKey(key: "UIRequiredDeviceCapabilities", value: [String]()),
				InfoPlistCommonKey(key: "UIApplicationSupportsIndirectInputEvents", value: true),
				InfoPlistCommonKey(key: "ITSAppUsesNonExemptEncryption", value: false),
				InfoPlistCommonKey(key: "UIApplicationSceneManifest", value: ["UIApplicationSupportsMultipleScenes": true])
			])
		]
	}
}
