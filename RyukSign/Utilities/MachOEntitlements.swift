//
//  MachOEntitlements.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

enum MachOEntitlements {
	private static let machO64: UInt32 = 0xfeedfacf
	private static let machO64Swapped: UInt32 = 0xcffaedfe
	private static let fat: UInt32 = 0xcafebabe
	private static let fat64: UInt32 = 0xcafebabf
	private static let codeSignatureCommand: UInt32 = 0x1d
	private static let embeddedSignatureMagic: UInt32 = 0xfade0cc0
	private static let entitlementsMagic: UInt32 = 0xfade7171
	private static let entitlementsSlot: UInt32 = 0x5
	private static let cpuTypeArm64: UInt32 = 0x0100000c
	private static let machHeader64Size = 32

	static func keychainAccessGroups(forExecutableAt url: URL) -> [String] {
		read(forExecutableAt: url)?["keychain-access-groups"] as? [String] ?? []
	}

	static func read(forExecutableAt url: URL) -> [String: Any]? {
		guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }

		let slice = sliceOffset(in: data)

		// iOS binaries are 64-bit
		let bigEndian: Bool
		switch u32(data, at: slice, bigEndian: false) {
		case machO64: bigEndian = false
		case machO64Swapped: bigEndian = true
		default: return nil
		}

		guard let ncmds = u32(data, at: slice + 16, bigEndian: bigEndian) else { return nil }
		var cmd = slice + machHeader64Size

		for _ in 0..<ncmds {
			guard
				let cmdId = u32(data, at: cmd, bigEndian: bigEndian),
				let cmdSize = u32(data, at: cmd + 4, bigEndian: bigEndian),
				cmdSize >= 8
			else { return nil }

			if cmdId == codeSignatureCommand, let off = u32(data, at: cmd + 8, bigEndian: bigEndian) {
				return entitlements(in: data, at: slice + Int(off))
			}

			cmd += Int(cmdSize)
		}

		return nil
	}

	// Code signature blobs are always big-endian, regardless of the host or Mach-O slice.
	private static func entitlements(in data: Data, at codeSig: Int) -> [String: Any]? {
		guard
			u32(data, at: codeSig, bigEndian: true) == embeddedSignatureMagic,
			let count = u32(data, at: codeSig + 8, bigEndian: true)
		else { return nil }

		for i in 0..<Int(count) {
			let index = codeSig + 12 + i * 8
			guard
				let type = u32(data, at: index, bigEndian: true),
				let blobOff = u32(data, at: index + 4, bigEndian: true)
			else { return nil }

			guard type == entitlementsSlot else { continue }

			let blob = codeSig + Int(blobOff)
			guard
				u32(data, at: blob, bigEndian: true) == entitlementsMagic,
				let length = u32(data, at: blob + 4, bigEndian: true),
				length > 8
			else { return nil }

			let start = blob + 8
			let end = blob + Int(length)
			guard start <= end, end <= data.count else { return nil }

			let plist = data.subdata(in: (data.startIndex + start)..<(data.startIndex + end))
			return (try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil)) as? [String: Any]
		}

		return nil
	}

	// Fat headers are always big-endian
	private static func sliceOffset(in data: Data) -> Int {
		let entrySize: Int
		switch u32(data, at: 0, bigEndian: true) {
		case fat: entrySize = 20
		case fat64: entrySize = 32
		default: return 0
		}

		guard let nfat = u32(data, at: 4, bigEndian: true) else { return 0 }
		var fallback = 0

		for i in 0..<Int(nfat) {
			let entry = 8 + i * entrySize
			let offsetField = entrySize == 32 ? entry + 12 : entry + 8
			guard
				let cpuType = u32(data, at: entry, bigEndian: true),
				let off = u32(data, at: offsetField, bigEndian: true)
			else { break }

			if cpuType == cpuTypeArm64 { return Int(off) }
			if fallback == 0 { fallback = Int(off) }
		}

		return fallback
	}

	private static func u32(_ data: Data, at offset: Int, bigEndian: Bool) -> UInt32? {
		guard offset >= 0, offset + 4 <= data.count else { return nil }
		let base = data.startIndex + offset
		let b0 = UInt32(data[base]), b1 = UInt32(data[base + 1])
		let b2 = UInt32(data[base + 2]), b3 = UInt32(data[base + 3])
		return bigEndian
			? (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
			: (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
	}
}
