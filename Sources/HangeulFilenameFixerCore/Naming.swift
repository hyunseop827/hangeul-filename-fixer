// Filename rules shared by the copy engine and the app's preview.
// Pure functions: nothing here touches the file system.
//
// Every rule works on Unicode scalars, as the JavaScript original worked on code points. Do not "simplify" a loop into
// `==`, `hasSuffix`, `split` or a `Set<String>`: those treat an NFC and an NFD spelling as the same name (see
// JavaScriptText.swift).

private let reservedDeviceNames: [String] = ["CON", "PRN", "AUX", "NUL"]
	+ ["1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"].flatMap { suffix in ["COM\(suffix)", "LPT\(suffix)"] }

private let choseongLetters = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".unicodeScalars)
private let jungseongLetters = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ".unicodeScalars)
private let jongseongLetters = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ".unicodeScalars)

/// Splits at the last dot, like Node's path.parse: ".bashrc" has no extension, "a.tar.gz" has ".gz".
public func splitFileName(_ fileName: String) -> (stem: String, extension: String) {
	let scalars = fileName.unicodeScalars
	// The dot is searched as a scalar. As a Character, the dot of "a.\u{301}txt" (a dot with a combining accent) would
	// not be found.
	guard let dotIndex = scalars.lastIndex(of: "."), dotIndex != scalars.startIndex else {
		return (stem: fileName, extension: "")
	}

	return (stem: String(scalars[..<dotIndex]), extension: String(scalars[dotIndex...]))
}

public func windowsSafeStem(_ rawStem: String) -> String {
	var stem = replacingForbiddenCharacters(in: nfc(rawStem))
		.javaScriptTrimmed()
		.removingTrailingScalars(while: isDotOrSpace)

	if stem.unicodeScalars.isEmpty {
		stem = "파일"
	}

	// Windows treats "CON", "con.tar.gz" and "NUL .txt" alike: the part before the first dot decides.
	let scalars = stem.unicodeScalars
	let beforeFirstDot = String(scalars[..<(scalars.firstIndex(of: ".") ?? scalars.endIndex)])
	let deviceName = beforeFirstDot.javaScriptTrimmedEnd().uppercased()
	if reservedDeviceNames.contains(where: { hasSameScalars($0, deviceName) }) {
		stem = "_" + stem
	}

	return stem
}

/// Builds the NFC, Windows-safe file name from a stem and the original extension.
public func windowsSafeFileName(stem: String, extension: String) -> String {
	let safeExtension = replacingForbiddenCharacters(in: nfc(`extension`))

	// Windows also drops a dot or space at the very end ("file." or "a.txt ").
	return (windowsSafeStem(stem) + safeExtension).removingTrailingScalars(while: isDotOrSpace)
}

/// True when the name is spelled in NFC.
///
/// Compared scalar by scalar: `fileName == nfc(fileName)` would be true for every name, because Swift's `==` calls an
/// NFD spelling and its NFC form equal.
public func isNFCName(_ fileName: String) -> Bool {
	hasSameScalars(fileName, nfc(fileName))
}

/// Shows a decomposed (NFD) name the way Windows often renders it: one letter per jamo.
public func decomposedDisplayName(_ fileName: String) -> String {
	var shown = String.UnicodeScalarView()

	for scalar in fileName.unicodeScalars {
		switch scalar.value {
		case 0x1100...0x1112:
			shown.append(choseongLetters[Int(scalar.value - 0x1100)])
		case 0x1161...0x1175:
			shown.append(jungseongLetters[Int(scalar.value - 0x1161)])
		case 0x11A8...0x11C2:
			shown.append(jongseongLetters[Int(scalar.value - 0x11A8)])
		default:
			shown.append(scalar)
		}
	}

	return String(shown)
}

/// `< > : " / \ | ? *` and the control characters U+0000–U+001F, which Windows does not allow in a file name.
private func isForbiddenOnWindows(_ scalar: Unicode.Scalar) -> Bool {
	switch scalar {
	case "<", ">", ":", "\"", "/", "\\", "|", "?", "*":
		return true
	default:
		return scalar.value <= 0x1F
	}
}

/// Replaces each forbidden code point with "_". Per scalar: a ":" followed by a combining mark, or CR LF, is a single
/// Character that a Character-wise replacement would leave in the name.
private func replacingForbiddenCharacters(in text: String) -> String {
	var replaced = String.UnicodeScalarView()
	for scalar in text.unicodeScalars {
		replaced.append(isForbiddenOnWindows(scalar) ? "_" : scalar)
	}

	return String(replaced)
}

/// Only the ASCII dot and space, the two characters Windows drops from the end of a name. Other white space stays.
private func isDotOrSpace(_ scalar: Unicode.Scalar) -> Bool {
	scalar == "." || scalar == " "
}
