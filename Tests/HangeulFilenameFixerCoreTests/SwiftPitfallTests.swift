// The traps of writing this app in Swift, pinned as tests.
//
// Swift compares Strings by canonical equivalence: an NFC name and its NFD spelling are `==`. That is the right
// default for text and exactly wrong for this app, whose only job is to tell the two apart. These tests fail when the
// Core starts to rely on String equality, or when a Foundation path API sneaks into the copy and decomposes the name.
import Darwin
import Foundation
import Testing
@testable import HangeulFilenameFixerCore

@Suite("Swift pitfalls: names are compared and stored by their bytes")
struct SwiftPitfallTests {
	let folders = TestFolders()

	// "한글" as one syllable per character (NFC) and as conjoining jamo (NFD).
	static let composedName = "\u{D55C}\u{AE00}.txt"
	static let decomposedName = "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}.txt"

	@Test("the literals in the test sources are NFC, and decomposed() really decomposes")
	func literalsInTheTestSourcesAreNFC() {
		// If an editor ever saved these files decomposed, the tests would compare NFD with NFD and prove nothing.
		#expect("한글.txt".unicodeScalars.map(\.value) == [0xD55C, 0xAE00, 0x2E, 0x74, 0x78, 0x74])
		#expect(Array("한글 사본.txt".utf8) == [0xED, 0x95, 0x9C, 0xEA, 0xB8, 0x80, 0x20, 0xEC, 0x82, 0xAC, 0xEB, 0xB3, 0xB8, 0x2E, 0x74, 0x78, 0x74])
		#expect(Exact("한글.txt") == Exact(Self.composedName))
		#expect(Exact(decomposed("한글.txt")) == Exact(Self.decomposedName))
		#expect(Exact(decomposed("각")) == Exact("\u{1100}\u{1161}\u{11A8}"))
		#expect(Exact(decomposed("가")) == Exact("\u{1100}\u{1161}"))
	}

	@Test("Swift's == calls an NFC and an NFD name equal (this is why the Core never uses it for names)")
	func swiftEqualityIgnoresNormalization() {
		let composed = Self.composedName
		let decomposed = Self.decomposedName

		// Do not "simplify" the Core's scalar and byte comparisons into these: every one of them is blind to the
		// difference this app exists to fix.
		#expect(composed == decomposed)
		#expect(composed.hashValue == decomposed.hashValue)
		#expect(Set([composed, decomposed]).count == 1)
		#expect([composed: 1][decomposed] == 1)
		#expect([composed].contains(decomposed))
		#expect(composed.hasPrefix(String(decomposed.prefix(1))))
		#expect(decomposed.hasSuffix(composed))
		#expect(composed.count == decomposed.count)

		// What does see the difference.
		#expect(!composed.unicodeScalars.elementsEqual(decomposed.unicodeScalars))
		#expect(Array(composed.utf8) != Array(decomposed.utf8))
		#expect(!composed.utf16.elementsEqual(decomposed.utf16))
		#expect(composed.unicodeScalars.count == 6)
		#expect(decomposed.unicodeScalars.count == 10)
	}

	@Test("Character-based code misses dots, spaces and forbidden characters that carry a combining mark")
	func charactersHideScalars() {
		// A dot, a colon or a space followed by a combining mark is ONE Character.
		#expect("a.\u{301}txt".lastIndex(of: ".") == nil)
		#expect("CON.\u{301}x".split(separator: ".").count == 1)
		#expect(!"a:\u{301}b".contains(":"))
		#expect("\r\n".count == 1)

		// The Core finds them, as JavaScript did.
		let parts = splitFileName("a.\u{301}txt")
		#expect(Exact(parts.stem) == Exact("a"))
		#expect(Exact(parts.extension) == Exact(".\u{301}txt"))
		#expect(Exact(windowsSafeFileName(stem: "a:\u{301}b", extension: ".txt")) == Exact("a_\u{301}b.txt"))
		#expect(Exact(windowsSafeFileName(stem: "x\r\ny", extension: ".txt")) == Exact("x__y.txt"))
	}

	@Test("isNFCName tells NFC from NFD although == does not")
	func isNFCNameDistinguishesSpellings() {
		#expect(isNFCName(Self.composedName))
		#expect(!isNFCName(Self.decomposedName))
		#expect(isNFCName("report (1).txt"))
		#expect(isNFCName(""))
		// A syllable followed by a final consonant is not NFC either (Foundation's normalizer thinks it is).
		#expect(!isNFCName("\u{AC00}\u{11A8}"))
		#expect(isNFCName("\u{AC01}"))
		// The naive check is true for every name.
		#expect(Self.decomposedName == Self.decomposedName.precomposedStringWithCanonicalMapping)
	}

	@Test("the reserved-name check looks at code points, not at Characters")
	func reservedNameCheckIsNotFooled() {
		// JavaScript's split(".")[0] is "CON" here; a Character-wise split would not see the dot.
		#expect(Exact(windowsSafeStem("CON.\u{301}x")) == Exact("_CON.\u{301}x"))
		// "CON" + combining acute composes to "COŃ", which is not a device name.
		#expect(Exact(windowsSafeStem("CON\u{301}")) == Exact("CO\u{143}"))
		#expect(Exact(windowsSafeStem("COM1\u{301}")) == Exact("COM1\u{301}"))
		// A space with a combining mark is not trailing white space, so "NUL" is not alone before the dot.
		#expect(Exact(windowsSafeStem("NUL \u{301}")) == Exact("NUL \u{301}"))
		// White space JavaScript trims but Swift's Character.isWhitespace does not know (U+FEFF), and the reverse (U+0085).
		#expect(Exact(windowsSafeStem("\u{FEFF}CON\u{FEFF}")) == Exact("_CON"))
		#expect(Exact(windowsSafeStem("CON\u{A0}")) == Exact("_CON"))
		#expect(Exact(windowsSafeStem("CON\u{85}")) == Exact("CON\u{85}"))
		// Look-alikes are other code points and stay.
		#expect(Exact(windowsSafeStem("\u{FF23}\u{FF2F}\u{FF2E}")) == Exact("\u{FF23}\u{FF2F}\u{FF2E}"))
		#expect(Exact(windowsSafeStem("com²")) == Exact("_com²"))
		#expect(Exact(windowsSafeStem("COM0")) == Exact("COM0"))
	}

	@Test("PlanInput equality is exact: the same path in another normalization is another input")
	func planInputEqualityIsExact() {
		let composed = PlanInput(sourcePath: "/tmp/" + Self.composedName, outputDirectory: "/tmp", baseName: "")
		let decomposed = PlanInput(sourcePath: "/tmp/" + Self.decomposedName, outputDirectory: "/tmp", baseName: "")

		#expect(composed.sourcePath == decomposed.sourcePath)
		#expect(composed != decomposed)
		#expect(composed == PlanInput(sourcePath: "/tmp/" + Self.composedName, outputDirectory: "/tmp", baseName: ""))
		#expect(composed != PlanInput(sourcePath: "/tmp/" + Self.composedName, outputDirectory: "/tmp", baseName: "가"))
		#expect(
			PlanInput(sourcePath: "a", outputDirectory: "b", baseName: "가")
				!= PlanInput(sourcePath: "a", outputDirectory: "b", baseName: "\u{1100}\u{1161}")
		)
	}

	@Test("the copy's stored name is NFC byte for byte, read back with readdir")
	func storedNameOfTheCopyIsNFCByBytes() throws {
		let sourcePath = try folders.writeSource(decomposed("한글 사본.txt"), "data")
		// Precondition: the original really is stored decomposed.
		#expect(try storedNameBytes(in: folders.source) == [Array(decomposed("한글 사본.txt").utf8)])

		let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: ""))

		let composedBytes: [UInt8] = [0xED, 0x95, 0x9C, 0xEA, 0xB8, 0x80, 0x20, 0xEC, 0x82, 0xAC, 0xEB, 0xB3, 0xB8, 0x2E, 0x74, 0x78, 0x74]
		#expect(try storedNameBytes(in: folders.output) == [composedBytes])
		#expect(Array(created.destinationName.utf8) == composedBytes)
		#expect(Array(created.destinationPath.utf8) == Array(folders.output.utf8) + [0x2F] + composedBytes)
		#expect(Exact(created.sourceName) == Exact(decomposed("한글 사본.txt")))
	}

	@Test("a typed NFD name is stored as NFC too")
	func typedDecomposedNameIsStoredComposed() throws {
		let sourcePath = try folders.writeSource(decomposed("원본.hwp"))
		let typed = "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}"

		let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: typed))

		#expect(try storedNameBytes(in: folders.output) == [Array("한글.hwp".utf8)])
		#expect(Exact(created.destinationName) == Exact("한글.hwp"))
	}

	@Test("the original is untouched by a copy: name bytes, content, mode, times and extended attributes")
	func originalIsUnchangedAfterACopy() throws {
		let name = decomposed("원본 그대로.pdf")
		let sourcePath = try folders.writeSource(name, "original content")
		try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
		try setExtendedAttribute("user.hangeul-filename-fixer.test", Array("keep me".utf8), atPath: sourcePath)
		// Read-only, the case in which the Electron app had to chmod the copy; nothing may ever chmod the original.
		#expect(chmod(sourcePath, 0o444) == 0)
		// An old modification time, so a rewrite of the file would show.
		var times = [timeval(tv_sec: 1_600_000_000, tv_usec: 0), timeval(tv_sec: 1_600_000_000, tv_usec: 0)]
		#expect(utimes(sourcePath, &times) == 0)

		let before = try fileStatus(sourcePath, followingSymlinks: false)
		let attributesBefore = extendedAttributeNames(atPath: sourcePath)
		let quarantineBefore = extendedAttribute(quarantineAttributeName, atPath: sourcePath)

		let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: ""))
		// A second copy next to the original, where the names collide.
		let beside = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.source, baseName: ""))

		let after = try fileStatus(sourcePath, followingSymlinks: false)
		#expect(try storedNameBytes(in: folders.source).contains(Array(name.utf8)), "the original keeps its NFD name")
		#expect(try readFile(sourcePath) == "original content")
		#expect(after.st_ino == before.st_ino)
		#expect(after.st_mode == before.st_mode)
		#expect(after.st_mode & 0o7777 == 0o444)
		#expect(after.st_size == before.st_size)
		#expect(after.st_flags == before.st_flags)
		#expect(after.st_nlink == before.st_nlink)
		#expect(after.st_mtimespec.tv_sec == 1_600_000_000)
		#expect(after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec)
		// The change time moves on any chmod, xattr write or rename of the original.
		#expect(after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec)
		#expect(after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec)
		#expect(extendedAttributeNames(atPath: sourcePath) == attributesBefore)
		#expect(extendedAttribute(quarantineAttributeName, atPath: sourcePath) == quarantineBefore)
		#expect(extendedAttribute("user.hangeul-filename-fixer.test", atPath: sourcePath) == Array("keep me".utf8))

		// And the copies are what was promised: new files, NFC names, same data, mode and quarantine.
		#expect(try fileStatus(created.destinationPath).st_ino != before.st_ino)
		#expect(Exact(created.destinationName) == Exact("원본 그대로.pdf"))
		#expect(try readFile(created.destinationPath) == "original content")
		#expect(try permissionBits(created.destinationPath) == 0o444)
		#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == Array(sampleQuarantine.utf8))
		// Only the quarantine flag is carried over, not other extended attributes.
		#expect(extendedAttribute("user.hangeul-filename-fixer.test", atPath: created.destinationPath) == nil)
		// The copy is a new file, dated now.
		#expect(try fileStatus(created.destinationPath).st_mtimespec.tv_sec > 1_700_000_000)

		if try isNormalizationInsensitive(folders.output) {
			#expect(Exact(beside.destinationName) == Exact("원본 그대로 (1).pdf"))
			#expect(beside.hasNumberSuffix)
			#expect(try exactNames(in: folders.source) == [Exact(name), Exact("원본 그대로 (1).pdf")].sorted { Array($0.text.utf8).lexicographicallyPrecedes(Array($1.text.utf8)) })
		}
	}

	@Test("the stored source name is found by inode: path spelled NFD, file stored NFC")
	func storedNameIsFoundWhenThePathIsDecomposed() throws {
		_ = try folders.writeSource(Self.composedName)
		let decomposedPath = folders.source + "/" + Self.decomposedName
		guard nameIsTaken(decomposedPath) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}

		let plan = try #require(makePlan(PlanInput(sourcePath: decomposedPath, outputDirectory: folders.output, baseName: "")))

		#expect(Exact(plan.sourceName) == Exact(Self.composedName), "the name on disk, not the spelling of the path")
		#expect(Exact(plan.sourcePath) == Exact(decomposedPath), "the path is handed back as it was given")
		#expect(Exact(plan.destinationName) == Exact(Self.composedName))
	}

	@Test("the stored source name is found by inode: path spelled NFC, file stored NFD")
	func storedNameIsFoundWhenThePathIsComposed() throws {
		_ = try folders.writeSource(Self.decomposedName)
		let composedPath = folders.source + "/" + Self.composedName
		guard nameIsTaken(composedPath) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}

		let plan = try #require(makePlan(PlanInput(sourcePath: composedPath, outputDirectory: folders.output, baseName: "")))

		// This is the case the app's "already NFC?" decision depends on: the path looks composed, the file is not.
		#expect(Exact(plan.sourceName) == Exact(Self.decomposedName))
		#expect(!isNFCName(plan.sourceName))
		#expect(Exact(plan.destinationName) == Exact(Self.composedName))
	}

	@Test("the stored-name lookup only considers entries that are the same name in NFC")
	func storedNameLookupSkipsOtherNames() throws {
		// The folder lists the file under its decomposed spelling only, next to names that merely look alike.
		let sourcePath = try folders.writeSource(Self.composedName)
		let source = folders.source
		let fileSystem = FileSystemAccess(entryExists: FileSystemAccess.real.entryExists, directoryEntries: { directory in
			directory.utf8.elementsEqual(source.utf8) ? ["unrelated.txt", "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}.TXT", Self.decomposedName] : []
		})

		let plan = try #require(makePlan(PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: ""), fileSystem: fileSystem))

		// The exact spelling is not listed, so the NFC-equal entry is taken (on APFS the decomposed path reaches the
		// same file). The ".TXT" entry is not NFC-equal and is never asked. That the inode decides between NFC-equal
		// entries is checked by `storedNameLookupComparesTheInode`: here every NFC-equal spelling is the same file.
		if nameIsTaken(folders.source + "/" + Self.decomposedName) {
			#expect(Exact(plan.sourceName) == Exact(Self.decomposedName))
		} else {
			#expect(Exact(plan.sourceName) == Exact(Self.composedName))
		}
	}

	@Test("the stored-name lookup compares the inode: an NFC-equal entry that is another file is not taken")
	func storedNameLookupComparesTheInode() throws {
		// On APFS every spelling of a name reaches the same file, so an NFC-equal entry with another inode needs a
		// path that the kernel and the text disagree about: a symlinked folder followed by "..".
		//   e2/한글.txt        NFC, file X: what the path reaches as text ("link/.." cancelled out)
		//   e2/b/한글.txt      NFD, file Y: what the kernel reaches (the ".." of e2/b/sub is e2/b)
		//   e2/link → b/sub
		let base = folders.work + "/e2"
		#expect(mkdir(base, 0o755) == 0)
		#expect(mkdir(base + "/b", 0o755) == 0)
		#expect(mkdir(base + "/b/sub", 0o755) == 0)
		try writeFile(base + "/" + Self.composedName, "X")
		try writeFile(base + "/b/" + Self.decomposedName, "Y")
		#expect(symlink("b/sub", base + "/link") == 0)
		guard try isNormalizationInsensitive(folders.work) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}
		let sourcePath = base + "/link/../" + Self.composedName
		#expect(try readFile(sourcePath) == "Y")

		let plan = try #require(makePlan(PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: "")))

		// The folder listing (e2/b) has the NFD entry, which is NFC-equal to the name asked for. Joined to the folder
		// as text, as Node's path.join did, it names e2/한글.txt: another inode, so the entry is not taken and the
		// spelling from the path is kept. Without the inode comparison the NFD entry would be reported.
		#expect(Exact(plan.sourceName) == Exact(Self.composedName))
	}

	@Test("when the folder cannot be listed, the name from the path is kept")
	func unreadableFolderKeepsTheNameFromThePath() throws {
		let sourcePath = try folders.writeSource(Self.decomposedName)
		let fileSystem = FileSystemAccess(entryExists: FileSystemAccess.real.entryExists, directoryEntries: { _ in throw SystemCallError(code: EACCES) })

		let plan = try #require(makePlan(PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: ""), fileSystem: fileSystem))

		#expect(Exact(plan.sourceName) == Exact(Self.decomposedName))
		#expect(Exact(plan.destinationName) == Exact(Self.composedName))
	}

	@Test("the Core's sources stay away from the APIs that change or blur a name's spelling")
	func coreSourcesAvoidNormalizingAPIs() throws {
		// A reading of the source, not of behavior: these calls compile fine and quietly store NFD names or compare
		// names loosely, so the next person to "tidy up" must be stopped here. Comments may mention them.
		let sourcesDirectory = #filePath.split(separator: "/").dropLast(3).joined(separator: "/") + "/Sources/HangeulFilenameFixerCore"
		let files = ((try? storedNames(in: "/" + sourcesDirectory)) ?? []).filter { $0.hasSuffix(".swift") }
		guard !files.isEmpty else {
			print("skipped: the Core sources are not at /\(sourcesDirectory)")
			return
		}

		let forbidden = [
			"FileManager", "URL(", "NSURL", "NSString", "fileSystemRepresentation", "Data(", "CharacterSet",
			"trimmingCharacters", "hasPrefix", "hasSuffix", ".lowercased()", "Set<String>", "decomposedStringWith"
		]
		var findings: [String] = []
		for file in files {
			for (number, line) in try readFile("/" + sourcesDirectory + "/" + file).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
				let code = line.range(of: "//").map { line[..<$0.lowerBound] } ?? line
				for word in forbidden {
					// A whole word: "copyData(" is not "Data(".
					var searchRange = code.startIndex..<code.endIndex
					while let found = code.range(of: word, range: searchRange) {
						let previous = found.lowerBound > code.startIndex ? code[code.index(before: found.lowerBound)] : " "
						if !(previous.isLetter || previous.isNumber || previous == "_") || word.hasPrefix(".") {
							findings.append("\(file):\(number + 1): \(word)")
						}
						searchRange = found.upperBound..<code.endIndex
					}
				}
				// The Foundation normalizer is allowed in one place only: the fallback inside nfc().
				if code.contains("precomposedStringWithCanonicalMapping"), !code.contains("applyingTransform(anyNFC") {
					findings.append("\(file):\(number + 1): precomposedStringWithCanonicalMapping")
				}
			}
		}

		#expect(findings.isEmpty, "\(findings)")
		#expect(files.count >= 5)
	}

	@Test("a copy next to the NFD original never replaces it")
	func copyNextToTheOriginalKeepsBoth() throws {
		let name = decomposed("같은폴더.txt")
		let sourcePath = try folders.writeSource(name, "original")

		let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.source, baseName: ""))

		#expect(try readFile(sourcePath) == "original")
		#expect(try storedNameBytes(in: folders.source).contains(Array(name.utf8)))
		#expect(try storedNames(in: folders.source).count == 2)
		#expect(isNFCName(created.destinationName))
		if try isNormalizationInsensitive(folders.output) {
			#expect(Exact(created.destinationName) == Exact("같은폴더 (1).txt"))
			#expect(created.hasNumberSuffix)
		}
	}
}
