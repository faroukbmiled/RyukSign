//
//  WebManagerServer+WebDAV.swift
//  RyukSign
//
//  WebDAV subset so the inbox mounts read/write in Finder (dav://) and the iOS Files app.
//

import Foundation
import Vapor

extension WebManagerServer {
	private static let davAllow = "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL, MOVE, COPY, LOCK, UNLOCK"

	func _configureWebDAV(_ app: Application) {
		let catchall: [PathComponent] = ["**"]

		for path in [[PathComponent](), catchall] {
			app.on(.OPTIONS, path) { req -> Response in
				var headers = HTTPHeaders()
				headers.replaceOrAdd(name: "DAV", value: "1, 2")
				headers.replaceOrAdd(name: "MS-Author-Via", value: "DAV")
				headers.replaceOrAdd(name: .allow, value: Self.davAllow)
				headers.replaceOrAdd(name: .contentLength, value: "0")
				return Response(status: .ok, headers: headers)
			}
		}

		for path in [[PathComponent](), catchall] {
			app.on(.init(rawValue: "PROPFIND"), path) { [weak self] req -> Response in
				self?._propfind(req) ?? Response(status: .internalServerError)
			}
		}

		// PROPPATCH — accept property writes without persisting
		app.on(.init(rawValue: "PROPPATCH"), catchall) { [weak self] req -> Response in
			self?._proppatchOK(req) ?? Response(status: .ok)
		}

		for method in [HTTPMethod.GET, .HEAD] {
			app.on(method, catchall) { [weak self] req -> Response in
				self?._get(req, includeBody: method == .GET) ?? Response(status: .notFound)
			}
		}

		// PUT — streamed write; import debounced per path (see scheduleDebouncedRoute).
		app.on(.PUT, catchall, body: .stream) { [weak self] req -> EventLoopFuture<Response> in
			guard let self, let url = self.resolve(req.url.path) else {
				return req.eventLoop.makeSucceededFuture(Response(status: .forbidden))
			}
			let path = req.url.path
			return self.streamToFile(
				req,
				destination: url,
				route: false,
				report: false,
				successStatus: .created
			).always { _ in
				self.scheduleDebouncedRoute(forPath: path, url: url)
			}
		}

		app.on(.init(rawValue: "MKCOL"), catchall) { [weak self] req -> Response in
			guard let self, let url = self.resolve(req.url.path) else { return Response(status: .forbidden) }
			do {
				try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
				return Response(status: .created)
			} catch {
				return Response(status: .conflict)
			}
		}

		app.on(.DELETE, catchall) { [weak self] req -> Response in
			guard let self, let url = self.resolve(req.url.path) else { return Response(status: .forbidden) }
			guard FileManager.default.fileExists(atPath: url.path) else { return Response(status: .notFound) }
			try? FileManager.default.removeItem(at: url)
			return Response(status: .noContent)
		}

		app.on(.init(rawValue: "MOVE"), catchall) { [weak self] req -> Response in
			self?._moveOrCopy(req, move: true) ?? Response(status: .forbidden)
		}
		app.on(.init(rawValue: "COPY"), catchall) { [weak self] req -> Response in
			self?._moveOrCopy(req, move: false) ?? Response(status: .forbidden)
		}

		// LOCK / UNLOCK — stubbed to keep Finder happy
		app.on(.init(rawValue: "LOCK"), catchall) { req -> Response in
			let token = "opaquelocktoken:\(UUID().uuidString)"
			let xml = """
			<?xml version="1.0" encoding="utf-8"?>
			<D:prop xmlns:D="DAV:"><D:lockdiscovery><D:activelock>\
			<D:locktype><D:write/></D:locktype><D:lockscope><D:exclusive/></D:lockscope>\
			<D:depth>infinity</D:depth><D:timeout>Second-3600</D:timeout>\
			<D:locktoken><D:href>\(token)</D:href></D:locktoken>\
			</D:activelock></D:lockdiscovery></D:prop>
			"""
			var headers = HTTPHeaders()
			headers.contentType = .xml
			headers.replaceOrAdd(name: "Lock-Token", value: "<\(token)>")
			return Response(status: .ok, headers: headers, body: .init(string: xml))
		}
		app.on(.init(rawValue: "UNLOCK"), catchall) { _ -> Response in
			Response(status: .noContent)
		}
	}

	// MARK: - Handlers

	private func _get(_ req: Request, includeBody: Bool) -> Response {
		guard let url = resolve(req.url.path) else { return Response(status: .forbidden) }
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
			return Response(status: .notFound)
		}
		if isDir.boolValue {
			return Response(status: .ok)
		}
		if !includeBody {
			var headers = HTTPHeaders()
			let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue ?? 0
			headers.replaceOrAdd(name: .contentLength, value: "\(size)")
			return Response(status: .ok, headers: headers)
		}
		return req.fileio.streamFile(at: url.path)
	}

	private func _moveOrCopy(_ req: Request, move: Bool) -> Response {
		guard
			let source = resolve(req.url.path),
			let destHeader = req.headers.first(name: "Destination"),
			let destPath = _path(fromDestination: destHeader),
			let destination = resolve(destPath)
		else {
			return Response(status: .forbidden)
		}

		let fm = FileManager.default
		guard fm.fileExists(atPath: source.path) else { return Response(status: .notFound) }

		let existed = fm.fileExists(atPath: destination.path)
		if existed { try? fm.removeItem(at: destination) }

		do {
			if move {
				try fm.moveItem(at: source, to: destination)
			} else {
				try fm.copyItem(at: source, to: destination)
			}
			// Debounced + dedup'd with any earlier PUT to the same destination.
			if WebManagerRouter.destination(for: destination) != .inbox {
				scheduleDebouncedRoute(forPath: destination.path, url: destination)
			}
			return Response(status: existed ? .noContent : .created)
		} catch {
			return Response(status: .conflict)
		}
	}

	private func _proppatchOK(_ req: Request) -> Response {
		let href = _xmlEscape(req.url.path)
		let xml = """
		<?xml version="1.0" encoding="utf-8"?>
		<D:multistatus xmlns:D="DAV:"><D:response><D:href>\(href)</D:href>\
		<D:propstat><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>
		"""
		var headers = HTTPHeaders()
		headers.contentType = .xml
		return Response(status: .init(statusCode: 207), headers: headers, body: .init(string: xml))
	}

	private func _propfind(_ req: Request) -> Response {
		guard let url = resolve(req.url.path) else { return Response(status: .forbidden) }
		let fm = FileManager.default
		var isDir: ObjCBool = false
		guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
			return Response(status: .notFound)
		}

		let depth = req.headers.first(name: "Depth") ?? "1"

		var basePath = req.url.path
		if isDir.boolValue && !basePath.hasSuffix("/") { basePath += "/" }

		var entries = _propEntry(for: url, href: basePath, isDirectory: isDir.boolValue)

		if isDir.boolValue && depth != "0" {
			let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
			for child in children {
				var childIsDir: ObjCBool = false
				fm.fileExists(atPath: child.path, isDirectory: &childIsDir)
				let childHref = basePath + _urlEncode(child.lastPathComponent) + (childIsDir.boolValue ? "/" : "")
				entries += _propEntry(for: child, href: childHref, isDirectory: childIsDir.boolValue)
			}
		}

		let xml = """
		<?xml version="1.0" encoding="utf-8"?>
		<D:multistatus xmlns:D="DAV:">\(entries)</D:multistatus>
		"""
		var headers = HTTPHeaders()
		headers.contentType = .xml
		return Response(status: .init(statusCode: 207), headers: headers, body: .init(string: xml))
	}

	// MARK: - XML / path helpers

	private func _propEntry(for url: URL, href: String, isDirectory: Bool) -> String {
		let fm = FileManager.default
		let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
		let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
		let modified = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)

		let resourceType = isDirectory ? "<D:collection/>" : ""
		let lengthProp = isDirectory ? "" : "<D:getcontentlength>\(size)</D:getcontentlength>"

		return """
		<D:response><D:href>\(_xmlEscape(href))</D:href><D:propstat><D:prop>\
		<D:displayname>\(_xmlEscape(url.lastPathComponent))</D:displayname>\
		\(lengthProp)\
		<D:getlastmodified>\(Self.httpDate(modified))</D:getlastmodified>\
		<D:resourcetype>\(resourceType)</D:resourcetype>\
		</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response>
		"""
	}

	private func _path(fromDestination header: String) -> String? {
		if let comps = URLComponents(string: header), comps.scheme != nil {
			return comps.percentEncodedPath
		}
		return header
	}

	private func _urlEncode(_ component: String) -> String {
		component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
	}

	private func _xmlEscape(_ string: String) -> String {
		string
			.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
	}

	static func httpDate(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = TimeZone(identifier: "GMT")
		formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
		return formatter.string(from: date)
	}
}
