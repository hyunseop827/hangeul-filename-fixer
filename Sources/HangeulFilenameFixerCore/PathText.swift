// Path splitting and joining with the semantics of Node's path.posix (join, dirname, basename), done by hand on the
// path's UTF-8 bytes.
//
// Foundation's path helpers are not usable here. URL(fileURLWithPath:) decomposes every name the moment the URL is
// made, appendingPathComponent decomposes what it appends, and fileSystemRepresentation hands the kernel NFD bytes,
// so an NFC name that passes through them is stored as NFD. A path stays a plain String from the caller to the system
// call, and "/" (0x2F) never occurs inside a multi-byte UTF-8 sequence, so cutting at that byte is exact.

private let slash = UInt8(ascii: "/")
private let dot = UInt8(ascii: ".")

/// Node's `path.join(directory, name)`: joins with "/" and tidies the result (no doubled or trailing "/" before the
/// name, "." and ".." resolved as text).
func joinPath(_ directory: String, _ name: String) -> String {
	let parts = [directory, name].filter { !$0.utf8.isEmpty }
	if parts.isEmpty {
		return "."
	}

	return normalizePath(parts.joined(separator: "/"))
}

/// Node's `path.normalize(path)`.
func normalizePath(_ path: String) -> String {
	let bytes = Array(path.utf8)
	guard let first = bytes.first, let last = bytes.last else {
		return "."
	}

	let isAbsolute = first == slash
	let hasTrailingSlash = last == slash
	var segments: [ArraySlice<UInt8>] = []

	for segment in bytes.split(separator: slash) {
		if segment.elementsEqual([dot]) {
			continue
		}

		if segment.elementsEqual([dot, dot]) {
			if let previous = segments.last, !previous.elementsEqual([dot, dot]) {
				segments.removeLast()
			} else if !isAbsolute {
				// A relative path may climb above its start; "/.." is still "/".
				segments.append(segment)
			}
			continue
		}

		segments.append(segment)
	}

	var normalized = Array(segments.joined(separator: [slash]))
	if normalized.isEmpty {
		if isAbsolute {
			return "/"
		}

		return hasTrailingSlash ? "./" : "."
	}

	if hasTrailingSlash {
		normalized.append(slash)
	}
	if isAbsolute {
		normalized.insert(slash, at: 0)
	}

	return String(decoding: normalized, as: UTF8.self)
}

/// Node's `path.dirname(path)`: "/a/b.txt" and "/a/b/" give "/a", a bare name gives ".".
func directoryName(ofPath path: String) -> String {
	let bytes = Array(path.utf8)
	guard let first = bytes.first else {
		return "."
	}

	let hasRoot = first == slash
	var end: Int?
	var onlySlashesSoFar = true

	for index in stride(from: bytes.count - 1, through: 1, by: -1) {
		if bytes[index] == slash {
			if !onlySlashesSoFar {
				end = index
				break
			}
		} else {
			onlySlashesSoFar = false
		}
	}

	guard let end else {
		return hasRoot ? "/" : "."
	}
	if hasRoot, end == 1 {
		return "//"
	}

	return String(decoding: bytes[..<end], as: UTF8.self)
}

/// Node's `path.basename(path)`: the last component, ignoring trailing slashes.
func baseName(ofPath path: String) -> String {
	let bytes = Array(path.utf8)
	var start = 0
	var end: Int?

	for index in stride(from: bytes.count - 1, through: 0, by: -1) {
		if bytes[index] == slash {
			if end != nil {
				start = index + 1
				break
			}
		} else if end == nil {
			end = index + 1
		}
	}

	guard let end else {
		return ""
	}

	return String(decoding: bytes[start..<end], as: UTF8.self)
}
