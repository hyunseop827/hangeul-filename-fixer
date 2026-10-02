// What the Core expects from Foundation, the Swift standard library and the file system, pinned.
//
// Two kinds of tests:
// - "the Core relies on …": must hold. If a future macOS, Foundation or Swift changes one of these, the app would
//   store or judge names wrongly, and the test fails to say so.
// - "avoided …": behavior the Core deliberately does not use (and the reason the code looks the way it does). These
//   only print a note when macOS behaves differently from the Mac the app was written on; a change there cannot break
//   the app, so it must not break the suite either.
import Darwin
import Foundation
import Testing
@testable import HangeulFilenameFixerCore

@Suite("Platform behavior the Core relies on")
struct PlatformReliedOnTests {
	let folders = TestFolders()

	// Labelled NFC cases with the result of JavaScript's normalize("NFC") (Node 22, Unicode 17). Hangul first: these
	// are the rows where Foundation's own normalizer differs.
	static let normalizationCases: [(label: String, input: String, expected: String)] = [
		("ascii", "0072 0065 0070 006F 0072 0074 0020 0028 0031 0029 002E 0074 0078 0074", "0072 0065 0070 006F 0072 0074 0020 0028 0031 0029 002E 0074 0078 0074"),
		("hangul NFC stays", "D55C AE00 0020 C0AC BCF8 002E 0074 0078 0074", "D55C AE00 0020 C0AC BCF8 002E 0074 0078 0074"),
		("hangul NFD composes", "1112 1161 11AB 1100 1173 11AF 0020 1109 1161 1107 1169 11AB 002E 0074 0078 0074", "D55C AE00 0020 C0AC BCF8 002E 0074 0078 0074"),
		("first syllable L+V", "1100 1161", "AC00"),
		("last syllable L+V+T", "1112 1175 11C2", "D7A3"),
		("LV syllable + T", "AC00 11A8", "AC01"),
		("LV syllable + last T", "D788 11C2", "D7A3"),
		("LVT syllable + T does not compose", "AC01 11A8", "AC01 11A8"),
		("L alone", "1100", "1100"),
		("V alone", "1161", "1161"),
		("T alone", "11A8", "11A8"),
		("L + L + V", "1100 1100 1161", "1100 AC00"),
		("L + V + V", "1100 1161 1161", "AC00 1161"),
		("L + T (no V)", "1100 11A8", "1100 11A8"),
		("L + V + U+11A7 (not a T)", "1100 1161 11A7", "AC00 11A7"),
		("L + V + old T U+11C3", "1100 1161 11C3", "AC00 11C3"),
		("L + old V U+1176", "1100 1176", "1100 1176"),
		("old L U+1113 + V", "1113 1161", "1113 1161"),
		("old L U+1113 + V U+1175", "1113 1175", "1113 1175"),
		("L U+1112 + old V U+1176", "1112 1176", "1112 1176"),
		("choseong filler + V", "115F 1161", "115F 1161"),
		("L + jungseong filler", "1100 1160", "1100 1160"),
		("Jamo Extended-A L + V", "A960 1161", "A960 1161"),
		("L + Jamo Extended-B V", "1100 D7B0", "1100 D7B0"),
		("LV + Jamo Extended-B T", "AC00 D7CB", "AC00 D7CB"),
		("L + combining mark + V (blocked)", "1100 0301 1161", "1100 0301 1161"),
		("LV + combining mark + T (blocked)", "AC00 0301 11A8", "AC00 0301 11A8"),
		("compatibility jamo stay", "3131 314F 3134", "3131 314F 3134"),
		("halfwidth jamo stay", "FFA1 FFC2", "FFA1 FFC2"),
		("latin e + acute", "0063 0061 0066 0065 0301 002E 0074 0078 0074", "0063 0061 0066 00E9 002E 0074 0078 0074"),
		("latin precomposed stays", "0063 0061 0066 00E9 002E 0074 0078 0074", "0063 0061 0066 00E9 002E 0074 0078 0074"),
		("mark reordering", "0071 0307 0323", "0071 0323 0307"),
		("mark reordering reversed", "0071 0323 0307", "0071 0323 0307"),
		("two marks compose in order", "0061 030A 0301", "01FB"),
		("singleton OHM SIGN", "2126", "03A9"),
		("singleton ANGSTROM SIGN", "212B", "00C5"),
		("singleton KELVIN SIGN", "212A", "004B"),
		("CJK compatibility ideograph", "F900", "8C48"),
		("CJK compatibility supplement", "2F800", "4E3D"),
		("composition exclusion DEVANAGARI QA", "0958", "0915 093C"),
		("composition exclusion stays decomposed", "0915 093C", "0915 093C"),
		("Hebrew exclusion U+FB1D", "FB1D", "05D9 05B4"),
		("Tibetan U+0F73 after a mark", "0061 0320 0F73", "0061 0F71 0F72 0320"),
		("U+0344 non-starter decomposition", "0344", "0308 0301"),
		("less-than + combining solidus composes", "0061 003C 0338 0062", "0061 226E 0062"),
		("emoji with ZWJ untouched", "1F468 200D 1F469 200D 1F467", "1F468 200D 1F469 200D 1F467"),
		("NUL is kept", "0041 0000 1100 1161", "0041 0000 AC00"),
		("empty", "-", "-")
	]

	@Test("the Core relies on the Any-NFC transform giving JavaScript's normalize(\"NFC\")")
	func nfcMatchesJavaScript() {
		for (label, input, expected) in Self.normalizationCases {
			#expect(Exact(nfc(text(fromHex: input))) == Exact(text(fromHex: expected)), "\(label)")
		}

		// The transform itself, without the Core's ASCII shortcut and fallback.
		let transform = StringTransform(rawValue: "Any-NFC")
		#expect("\u{AC00}\u{11A8}".applyingTransform(transform, reverse: false).map(Exact.init) == Exact("\u{AC01}"))
		#expect("".applyingTransform(transform, reverse: false) == "")
	}

	@Test("the Core relies on NFC composing every modern Hangul syllable, from L V (T) and from LV T")
	func nfcComposesEveryHangulSyllable() {
		var wrong: [String] = []

		for value in UInt32(0xAC00)...0xD7A3 {
			guard let syllable = Unicode.Scalar(value) else {
				continue
			}

			let composed = String(syllable)
			if !hasSameScalars(nfc(decomposed(composed)), composed) || !hasSameScalars(nfc(composed), composed) {
				wrong.append(String(value, radix: 16))
			}

			// A syllable with a final consonant, written as the open syllable plus that consonant (LV + T).
			let finalIndex = (value - 0xAC00) % 28
			if finalIndex != 0, let open = Unicode.Scalar(value - finalIndex), let final = Unicode.Scalar(0x11A7 + finalIndex) {
				var mixed = String.UnicodeScalarView()
				mixed.append(open)
				mixed.append(final)
				if !hasSameScalars(nfc(String(mixed)), composed) || isNFCName(String(mixed)) {
					wrong.append("LV+T " + String(value, radix: 16))
				}
			}
		}

		#expect(wrong.isEmpty, "\(wrong.prefix(5))")
	}

	@Test("the Core relies on Strings keeping their spelling through construction, concatenation and C bridging")
	func stringsKeepTheirSpelling() {
		let decomposedBytes: [UInt8] = [0xE1, 0x84, 0x92, 0xE1, 0x85, 0xA1, 0xE1, 0x86, 0xAB]   // ㅎ ㅏ ㄴ
		let composedBytes: [UInt8] = [0xED, 0x95, 0x9C]                                          // 한

		for bytes in [decomposedBytes, composedBytes] {
			let name = String(decoding: bytes, as: UTF8.self)
			#expect(Array(name.utf8) == bytes)
			#expect(name.withCString { Array(UnsafeBufferPointer(start: $0, count: strlen($0))).map { UInt8(bitPattern: $0) } } == bytes)
			#expect(Array(("/" + name + " (1)" + ".txt").utf8) == [0x2F] + bytes + Array(" (1).txt".utf8))
			#expect(Array("\(name) (\(1))\(".txt")".utf8) == bytes + Array(" (1).txt".utf8))
			#expect(Array(String(name.unicodeScalars[...]).utf8) == bytes)
			#expect(Array(String(decoding: Array(name.utf16), as: UTF16.self).utf8) == bytes)
		}

		// customStem's cut can leave half of a surrogate pair; decoding must repair it to U+FFFD, not trap or drop it.
		#expect(String(decoding: [0xD83D] as [UInt16], as: UTF16.self).unicodeScalars.map(\.value) == [0xFFFD])
	}

	@Test("the Core relies on open(2) storing the bytes it was given, and readdir reporting them")
	func posixKeepsTheSpelling() throws {
		for (index, name) in ["한글 사본.txt", decomposed("한글 사본.txt")].enumerated() {
			let directory = folders.work + "/posix-\(index)"
			#expect(mkdir(directory, 0o755) == 0)
			try writeFile(directory + "/" + name)

			#expect(try storedNameBytes(in: directory) == [Array(name.utf8)])
			#expect(try listDirectory(atPath: directory).map(Exact.init) == [Exact(name)])
		}
	}

	@Test("the Core relies on the volume finding a file under either normalization, and O_EXCL refusing both")
	func lookupsIgnoreNormalization() throws {
		// True on APFS, where the temporary folder of every supported macOS lives.
		let stored = decomposed("원본.txt")
		let storedPath = try folders.writeSource(stored)
		let otherPath = folders.source + "/" + "원본.txt"

		let viaStored = try fileStatus(storedPath)
		let viaOther = try fileStatus(otherPath)
		#expect(viaStored.st_dev == viaOther.st_dev)
		#expect(viaStored.st_ino == viaOther.st_ino)
		#expect(nameIsTaken(otherPath))

		// This is what makes " (1)" appear when the copy is saved next to its NFD original.
		#expect(open(otherPath, O_WRONLY | O_CREAT | O_EXCL, 0o600) == -1)
		#expect(errno == EEXIST)
		#expect(try storedNameBytes(in: folders.source) == [Array(stored.utf8)], "the stored spelling does not change")
	}

	@Test("the Core relies on O_EXCL refusing a dangling symlink and a folder")
	func exclusiveCreateRefusesEveryKindOfEntry() throws {
		let link = folders.output + "/link.txt"
		let folder = folders.output + "/folder"
		#expect(symlink(folders.work + "/missing", link) == 0)
		#expect(mkdir(folder, 0o755) == 0)

		for path in [link, folder] {
			#expect(nameIsTaken(path))
			#expect(open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600) == -1)
			#expect(errno == EEXIST)
		}
		#expect(!nameIsTaken(folders.work + "/missing"), "nothing was created through the link")
	}

	@Test("the Core relies on uppercasing never turning another letter into a reserved device name")
	func uppercasingCreatesNoReservedNames() {
		// The reserved names are compared after uppercased(). Only ASCII letters, digits and ¹²³ may uppercase to text
		// made of their letters; otherwise some other spelling would be reserved here and not in the Electron app.
		// (A mapping that merely contains such a letter, like "ŉ" to "ʼN", cannot spell a reserved name.)
		let alphabet = Set("CONPRAUXLMT123456789\u{B9}\u{B2}\u{B3}".unicodeScalars.map(\.value))
		var intruders: [String] = []

		for value in UInt32(0)...0x10FFFF {
			guard let scalar = Unicode.Scalar(value), !scalar.isASCII, !alphabet.contains(value) else {
				continue
			}
			let mapping = scalar.properties.uppercaseMapping.unicodeScalars
			if !mapping.isEmpty, mapping.allSatisfy({ alphabet.contains($0.value) }) {
				intruders.append(String(value, radix: 16))
			}
		}

		#expect(intruders.isEmpty, "\(intruders.prefix(5))")
		#expect("con".uppercased().unicodeScalars.map(\.value) == [0x43, 0x4F, 0x4E])
		#expect("lpt\u{B3}".uppercased().unicodeScalars.map(\.value) == [0x4C, 0x50, 0x54, 0xB3])
	}

	@Test("the Core relies on the standard library's lowercase mapping and case properties")
	func lowercasingMatchesJavaScript() {
		// JavaScript toLowerCase() results from Node 22.
		let cases: [(String, String)] = [
			("보고서.HWP", "보고서.hwp"),
			("\u{391}\u{3A3}", "\u{3B1}\u{3C2}"),                 // ΑΣ → ας (Final_Sigma)
			("\u{391}\u{3A3}.", "\u{3B1}\u{3C2}."),
			("\u{3A3}", "\u{3C3}"),
			("\u{391}\u{3A3}\u{391}", "\u{3B1}\u{3C3}\u{3B1}"),
			("A\u{301}\u{3A3}", "a\u{301}\u{3C2}"),
			("\u{3B1}\u{3B2}\u{3B3}.\u{3A3}", "\u{3B1}\u{3B2}\u{3B3}.\u{3C2}"),
			(".\u{3A3}", ".\u{3C3}"),
			("\u{130}", "i\u{307}"),                              // İ → i + combining dot
			("\u{1C5}", "\u{1C6}"),
			("\u{1E9E}", "\u{DF}"),
			("K\u{212A}", "kk"),
			("a\u{0}B", "a\u{0}b")
		]

		for (input, expected) in cases {
			#expect(Exact(input.javaScriptLowercased()) == Exact(expected))
		}
	}

	@Test("the Core relies on xattr-then-chmod: the quarantine flag goes on before the copy turns read-only")
	func extendedAttributeIsWrittenBeforeTheReadOnlyMode() throws {
		let path = folders.output + "/order.txt"
		let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		try #require(descriptor >= 0)
		defer { close(descriptor) }

		let value = Array(sampleQuarantine.utf8)
		#expect(value.withUnsafeBytes { fsetxattr(descriptor, quarantineAttributeName, $0.baseAddress, $0.count, 0, 0) } == 0)
		#expect(fchmod(descriptor, 0o444) == 0)

		#expect(extendedAttribute(quarantineAttributeName, atPath: path) == value, "the kernel stores the value unchanged")
		#expect(try permissionBits(path) == 0o444)

		// A file without the attribute: reading it is an error (ENOATTR), which the Core takes as "nothing to copy".
		let plain = try writeFile(folders.output + "/plain.txt")
		let plainDescriptor = open(plain, O_RDONLY)
		try #require(plainDescriptor >= 0)
		defer { close(plainDescriptor) }
		#expect(fgetxattr(plainDescriptor, quarantineAttributeName, nil, 0, 0, 0) == -1)
		#expect(errno == ENOATTR)
	}

	@Test("the Core relies on a text without a strings table coming back as it is")
	func localizationFallsBackToTheKey() {
		// The Korean text is its own key in the app's Localizable.strings; the unit tests have no such table.
		for message in Message.all {
			#expect(Exact(localized(message)) == Exact(message))
			#expect(isNFCName(message), "the sources are saved in NFC")
			#expect(!containsConjoiningJamo(message))
		}
		#expect(Set(Message.all.map { Array($0.utf8) }).count == Message.all.count)
		#expect(Exact(notRegularFileMessage) == Exact("일반 파일이 아니거나(폴더·앱 등) 더 이상 없습니다. 파일을 다시 선택하세요."))
	}
}

/// Prints a note when an avoided behavior is no longer what it was. Never fails: see the header of this file.
private func observe(_ stillTrue: Bool, _ behavior: String) {
	if !stillTrue {
		print("note: this macOS no longer shows an avoided behavior (the Core does not depend on it): \(behavior)")
	}
}

@Suite("Platform behavior the Core avoids (informational, never fails)")
struct PlatformAvoidedTests {
	let folders = TestFolders()

	@Test("avoided: Foundation's precomposedStringWithCanonicalMapping is not JavaScript's NFC for Hangul")
	func foundationNormalizerDiffers() {
		// U+AC00 U+11A8 (가 + ㄱ) must compose to U+AC01 (각). Foundation leaves it, so an "is it NFC?" check built on
		// it would call such a name NFC.
		let foundation = "\u{AC00}\u{11A8}".precomposedStringWithCanonicalMapping
		observe(foundation.unicodeScalars.map(\.value) == [0xAC00, 0x11A8], "precomposedStringWithCanonicalMapping leaves U+AC00 U+11A8 uncomposed")
		// Whatever Foundation does, the Core's own answer is fixed.
		#expect(Exact(nfc("\u{AC00}\u{11A8}")) == Exact("\u{AC01}"))
	}

	@Test("avoided: URL(fileURLWithPath:) decomposes the name when the URL is made")
	func urlDecomposesNames() {
		let path = "/tmp/hangeul-filename-fixer-does-not-exist/한글.txt"
		let url = URL(fileURLWithPath: path)
		observe(!hasSameScalars(url.path, path), "URL(fileURLWithPath:).path is decomposed")
		observe(!hasSameScalars(url.lastPathComponent, "한글.txt"), "URL.lastPathComponent is decomposed")
		observe(
			!hasSameScalars(URL(fileURLWithPath: "/tmp").appendingPathComponent("한글.txt").lastPathComponent, "한글.txt"),
			"URL.appendingPathComponent decomposes what it appends"
		)
	}

	@Test("avoided: the file-system representation Foundation hands to the kernel is decomposed")
	func fileSystemRepresentationDecomposes() {
		let name = "한글.txt"
		let representation = String(cString: (name as NSString).fileSystemRepresentation)
		observe(!hasSameScalars(representation, name), "NSString.fileSystemRepresentation is decomposed")
	}

	@Test("avoided: FileManager stores an NFC name decomposed")
	func fileManagerStoresDecomposedNames() throws {
		let directory = folders.work + "/filemanager"
		#expect(mkdir(directory, 0o755) == 0)
		let created = FileManager.default.createFile(atPath: directory + "/" + "한글.txt", contents: Data("x".utf8))
		try #require(created)

		let stored = try storedNameBytes(in: directory)
		observe(stored == [Array(decomposed("한글.txt").utf8)], "FileManager.createFile stores the name decomposed")
		// The Core's way, for contrast, must store what it was given.
		let posixDirectory = folders.work + "/posix"
		#expect(mkdir(posixDirectory, 0o755) == 0)
		try writeFile(posixDirectory + "/" + "한글.txt")
		#expect(try storedNameBytes(in: posixDirectory) == [Array("한글.txt".utf8)])
	}

	@Test("avoided: Swift's and Foundation's white space is not JavaScript's")
	func swiftWhitespaceDiffers() {
		observe(Character("\u{85}").isWhitespace, "Character.isWhitespace is true for U+0085 (JavaScript: false)")
		observe(!Character("\u{FEFF}").isWhitespace, "Character.isWhitespace is false for U+FEFF (JavaScript: true)")
		observe(CharacterSet.whitespacesAndNewlines.contains("\u{200B}"), "CharacterSet.whitespacesAndNewlines contains U+200B (JavaScript: no)")
		observe(
			String(" \u{301}x".drop(while: \.isWhitespace)).unicodeScalars.count == 1,
			"dropping white-space Characters also removes a combining mark that follows a space (JavaScript keeps the mark)"
		)
		// The Core's own set is fixed.
		#expect(!isJavaScriptWhitespace("\u{85}"))
		#expect(isJavaScriptWhitespace("\u{FEFF}"))
		#expect(Exact(" \u{301}x ".javaScriptTrimmed()) == Exact("\u{301}x"))
	}

	@Test("avoided: lowercased() has no Final_Sigma rule, and hasSuffix matches across spellings")
	func swiftLowercasingDiffers() {
		observe("\u{391}\u{3A3}".lowercased().unicodeScalars.map(\.value) == [0x3B1, 0x3C3], "String.lowercased() maps a final Σ to σ (JavaScript: ς)")
		observe("a\u{0}B".lowercased(with: nil).unicodeScalars.count < 3, "lowercased(with:) stops at U+0000")
		// "resumé" spelled with a combining accent "ends with" the precomposed é for Swift; JavaScript says no, and
		// cutting by the suffix's length would then remove the wrong text.
		observe("resume\u{301}".hasSuffix("\u{E9}"), "hasSuffix matches a canonically equivalent ending")
	}

	@Test("avoided: fcopyfile stamps its own quarantine value, and a read-only file takes no extended attribute")
	func copyfileAndExtendedAttributeQuirks() throws {
		let sourcePath = try folders.writeSource("quarantined.txt")
		try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
		let source = open(sourcePath, O_RDONLY)
		let copyPath = folders.output + "/copy.txt"
		let copy = open(copyPath, O_WRONLY | O_CREAT | O_EXCL, 0o600)
		try #require(source >= 0 && copy >= 0)
		defer {
			close(source)
			close(copy)
		}

		#expect(fcopyfile(source, copy, nil, copyfile_flags_t(COPYFILE_DATA)) == 0)
		let stamped = extendedAttribute(quarantineAttributeName, atPath: copyPath)
		// The reason the Core writes the source's value AFTER fcopyfile: the value fcopyfile leaves has a new time
		// and no agent name.
		observe(stamped != nil && stamped != Array(sampleQuarantine.utf8), "fcopyfile(COPYFILE_DATA) writes a re-stamped quarantine value on the copy")

		// The reason the Core sets the mode last: with a read-only mode, even our own write descriptor is refused.
		#expect(fchmod(copy, 0o444) == 0)
		let value = Array(sampleQuarantine.utf8)
		let result = value.withUnsafeBytes { fsetxattr(copy, quarantineAttributeName, $0.baseAddress, $0.count, 0, 0) }
		observe(result == -1 && errno == EACCES, "fsetxattr fails with EACCES on a file whose mode is read-only")
	}
}
