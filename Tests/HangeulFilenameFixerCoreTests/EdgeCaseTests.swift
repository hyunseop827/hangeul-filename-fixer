// Edge cases beyond the TypeScript suite: odd sources, odd destinations, odd names, and every failure message.
// Expected names were taken from the TypeScript (electron/filename.ts of v1.1.0, run in Node 22 on the same inputs).
import Darwin
import Foundation
import Testing
@testable import HangeulFilenameFixerCore

@Suite("Edge cases")
struct EdgeCaseTests {
	let folders = TestFolders()

	private func input(_ sourcePath: String, baseName: String = "") -> PlanInput {
		PlanInput(sourcePath: sourcePath, outputDirectory: folders.output, baseName: baseName)
	}

	/// The destination name planned for a source stored as `sourceName` with `typed` in the rename field.
	private func plannedName(source sourceName: String, typed: String = "") throws -> Exact {
		let directory = folders.work + "/plan-\(UUID().uuidString)"
		#expect(mkdir(directory, 0o755) == 0)
		let sourcePath = try writeFile(directory + "/" + sourceName)
		let plan = try #require(makePlan(input(sourcePath, baseName: typed)))
		return Exact(plan.destinationName)
	}

	// MARK: Names

	@Test("forbidden characters in the source name are replaced in the copy's name")
	func forbiddenCharactersInTheSourceName() throws {
		let sourcePath = try folders.writeSource(decomposed("보고서: 최종?.txt"), "data")

		let created = try copyNormalizedFile(input(sourcePath))

		#expect(Exact(created.destinationName) == Exact("보고서_ 최종_.txt"))
		#expect(try exactNames(in: folders.output) == [Exact("보고서_ 최종_.txt")])
		#expect(try exactNames(in: folders.source) == [Exact(decomposed("보고서: 최종?.txt"))])

		#expect(try plannedName(source: "a\tb\nc\\d\"e|f*g<h>i.txt") == Exact("a_b_c_d_e_f_g_h_i.txt"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "a/b:c") == Exact("a_b_c.hwp"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "tab\there") == Exact("tab_here.hwp"))
	}

	@Test("an extension with forbidden characters is cleaned too")
	func forbiddenCharactersInTheExtension() throws {
		#expect(try plannedName(source: "Q&A 2024.1분기?") == Exact("Q&A 2024.1분기_"))
		#expect(try plannedName(source: "x.txt ", typed: "y") == Exact("y.txt"))
		#expect(try plannedName(source: "x.", typed: "y") == Exact("y"))
		#expect(try plannedName(source: "note.a:b") == Exact("note.a_b"))
	}

	@Test("reserved Windows names are escaped, typed or original")
	func reservedNames() throws {
		#expect(try plannedName(source: "CON.txt") == Exact("_CON.txt"))
		#expect(try plannedName(source: "aux") == Exact("_aux"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "nul") == Exact("_nul.hwp"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "con.backup") == Exact("_con.backup.hwp"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "COM\u{B9}") == Exact("_COM\u{B9}.hwp"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "console") == Exact("console.hwp"))
	}

	@Test("names of only dots and spaces fall back to 파일")
	func namesOfOnlyDotsAndSpaces() throws {
		#expect(try plannedName(source: "...") == Exact("파일"))
		#expect(try plannedName(source: " .txt") == Exact("파일.txt"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: " . . ") == Exact("파일.hwp"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "...") == Exact("파일.hwp"))
		#expect(try plannedName(source: ".bashrc") == Exact(".bashrc"))
		#expect(try plannedName(source: ".bashrc", typed: "x") == Exact("x"))
	}

	@Test("JavaScript's white space decides what a blank or padded typed name is")
	func javaScriptWhitespaceInTheTypedName() throws {
		let source = decomposed("원본.hwp")

		#expect(try plannedName(source: source, typed: "\u{A0}새 이름\u{A0}") == Exact("새 이름.hwp"))
		#expect(try plannedName(source: source, typed: "\u{3000}") == Exact("원본.hwp"), "an ideographic space alone is blank")
		#expect(try plannedName(source: source, typed: "\u{FEFF}보고서\u{FEFF}") == Exact("보고서.hwp"))
		#expect(try plannedName(source: source, typed: "\u{FEFF}") == Exact("원본.hwp"))
		// Not white space in JavaScript (Swift's Character.isWhitespace and CharacterSet disagree on these).
		#expect(try plannedName(source: source, typed: "\u{85}") == Exact("\u{85}.hwp"))
		#expect(try plannedName(source: source, typed: "\u{200B}") == Exact("\u{200B}.hwp"))
	}

	@Test("a typed copy of the extension is dropped whatever its letter case")
	func typedExtensionInAnotherCase() throws {
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "보고서.HWP") == Exact("보고서.hwp"))
		#expect(try plannedName(source: "x.HWP", typed: "보고서.hwp") == Exact("보고서.HWP"))
		#expect(try plannedName(source: "a.tar.gz", typed: "b.tar.gz") == Exact("b.tar.gz"))
		#expect(try plannedName(source: "noext", typed: "새 이름.txt") == Exact("새 이름.txt"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: "hwp") == Exact("hwp.hwp"))
		#expect(try plannedName(source: decomposed("원본.hwp"), typed: ".hwp") == Exact("hwp.hwp"))
		#expect(try plannedName(source: "x.txt", typed: "\u{1F600}.TXT") == Exact("\u{1F600}.txt"))
		// Full Unicode case mapping, as toLowerCase() did it.
		#expect(try plannedName(source: "x.\u{130}", typed: "보고서.i\u{307}") == Exact("보고서.\u{130}"))
		#expect(try plannedName(source: "\u{3B1}.\u{3A3}", typed: "\u{3B1}\u{3B2}\u{3B3}.\u{3A3}") == Exact("\u{3B1}\u{3B2}\u{3B3}.\u{3A3}.\u{3A3}"))
		#expect(try plannedName(source: "x.\u{DF}", typed: "STRASSE.SS") == Exact("STRASSE.SS.\u{DF}"))
		#expect(try plannedName(source: "x.\u{E9}", typed: "cafe.e\u{301}") == Exact("cafe.\u{E9}"))
		// The cut lands inside the emoji's surrogate pair; JavaScript kept half of it, which reaches the disk as U+FFFD.
		#expect(try plannedName(source: "x.i\u{307}", typed: "\u{1F600}.\u{130}") == Exact("\u{FFFD}.i\u{307}"))
		// The app's normal case: the source, extension included, is stored decomposed and the user types NFC.
		#expect(try plannedName(source: decomposed("자료.한글"), typed: "보고서.한글") == Exact("보고서.한글"))
		#expect(try plannedName(source: decomposed("자료.한글"), typed: decomposed("보고서.한글")) == Exact("보고서.한글"))
	}

	// MARK: Taken names

	@Test("a dangling symlink is a taken name, and the copy leaves it alone")
	func danglingSymlinkIsTaken() throws {
		let sourcePath = try folders.writeSource(decomposed("링크.txt"), "data")
		let linkPath = folders.output + "/" + "링크.txt"
		let target = folders.work + "/" + "없는 대상"
		#expect(symlink(target, linkPath) == 0)

		let created = try copyNormalizedFile(input(sourcePath))

		#expect(Exact(created.destinationName) == Exact("링크 (1).txt"))
		#expect(created.hasNumberSuffix)
		#expect(try fileStatus(linkPath, followingSymlinks: false).st_mode & S_IFMT == S_IFLNK)
		#expect(!nameIsTaken(target), "nothing was written through the link")
		#expect(try readFile(created.destinationPath) == "data")
	}

	@Test("(n) skips every taken number, whatever kind of entry holds it")
	func numberSuffixSkipsTakenNumbers() throws {
		let sourcePath = try folders.writeSource(decomposed("과제.docx"), "new")
		try writeFile(folders.output + "/" + "과제.docx", "0")
		try writeFile(folders.output + "/" + decomposed("과제 (1).docx"), "1")              // taken in the other spelling
		#expect(mkdir(folders.output + "/" + "과제 (2).docx", 0o755) == 0)                    // a folder
		#expect(symlink("/nonexistent", folders.output + "/" + "과제 (3).docx") == 0)        // a dangling symlink
		try writeFile(folders.output + "/" + "과제 (5).docx", "5")

		// On a volume that told NFC and NFD apart, the decomposed " (1)" would not count and (1) would be free.
		let insensitive = try isNormalizationInsensitive(folders.work)
		let plan = try #require(makePlan(input(sourcePath)))
		let expected = insensitive ? "과제 (4).docx" : "과제 (1).docx"
		#expect(Exact(plan.destinationName) == Exact(expected))
		#expect(plan.hasNumberSuffix)

		let created = try copyNormalizedFile(input(sourcePath))
		#expect(Exact(created.destinationName) == Exact(expected))
		#expect(try readFile(folders.output + "/" + "과제.docx") == "0")
		#expect(try readFile(folders.output + "/" + "과제 (5).docx") == "5")

		// The next one fills the gap after it.
		let next = try copyNormalizedFile(input(sourcePath))
		#expect(Exact(next.destinationName) == Exact(insensitive ? "과제 (6).docx" : "과제 (4).docx"))
	}

	@Test("(n) goes before the last extension of the cleaned name")
	func numberSuffixPosition() throws {
		for (name, expected) in [("a.tar.gz", "a.tar (1).gz"), (".bashrc", ".bashrc (1)"), ("README", "README (1)"), ("note.a_b", "note (1).a_b")] {
			let directory = folders.work + "/suffix-\(UUID().uuidString)"
			#expect(mkdir(directory, 0o755) == 0)
			let sourcePath = try writeFile(directory + "/" + name)

			// Saving next to the original: its own name is the taken one.
			let plan = try #require(makePlan(PlanInput(sourcePath: sourcePath, outputDirectory: directory, baseName: "")))
			#expect(Exact(plan.destinationName) == Exact(expected))
			#expect(Exact(plan.destinationPath) == Exact(directory + "/" + expected))
		}
	}

	// MARK: Sources

	@Test("a hard-linked source: the plan names the link that was chosen, and the copy is a file of its own")
	func hardLinkedSource() throws {
		let stored = decomposed("원본.txt")
		let sourcePath = try folders.writeSource(stored, "shared data")
		let otherLink = folders.source + "/" + decomposed("다른 이름.txt")
		#expect(link(sourcePath, otherLink) == 0)

		// Asked through the NFC spelling, so the name must be found by inode; the other link has the same inode but
		// another name and must not be picked.
		let composedPath = folders.source + "/" + "원본.txt"
		let insensitive = try isNormalizationInsensitive(folders.work)
		let plan = try #require(makePlan(input(insensitive ? composedPath : sourcePath)))
		#expect(Exact(plan.sourceName) == Exact(stored))

		let created = try copyNormalizedFile(input(sourcePath))
		let original = try fileStatus(sourcePath)
		let copy = try fileStatus(created.destinationPath)
		#expect(original.st_nlink == 2)
		#expect(copy.st_nlink == 1)
		#expect(copy.st_ino != original.st_ino)
		#expect(try readFile(created.destinationPath) == "shared data")
		#expect(try readFile(otherLink) == "shared data")
	}

	@Test("a symlinked source: the link's own name is used, the target's data is copied, the link stays a link")
	func symlinkedSource() throws {
		let targetDirectory = folders.work + "/" + "대상 폴더"
		#expect(mkdir(targetDirectory, 0o755) == 0)
		let targetPath = try writeFile(targetDirectory + "/" + decomposed("실제 파일.txt"), "target data")
		let linkName = decomposed("바로가기.txt")
		let linkPath = folders.source + "/" + linkName
		#expect(symlink(targetPath, linkPath) == 0)

		let plan = try #require(makePlan(input(linkPath)))
		#expect(Exact(plan.sourceName) == Exact(linkName))
		#expect(Exact(plan.destinationName) == Exact("바로가기.txt"))

		if try isNormalizationInsensitive(folders.work) {
			// Through the other spelling the link is found by the inode stat reports for it, which is the target's.
			let viaComposed = try #require(makePlan(input(folders.source + "/" + "바로가기.txt")))
			#expect(Exact(viaComposed.sourceName) == Exact(linkName))
		}

		let created = try copyNormalizedFile(input(linkPath))
		#expect(try readFile(created.destinationPath) == "target data")
		#expect(try fileStatus(created.destinationPath, followingSymlinks: false).st_mode & S_IFMT == S_IFREG, "the copy is a regular file")
		#expect(try fileStatus(linkPath, followingSymlinks: false).st_mode & S_IFMT == S_IFLNK)
		#expect(try readFile(targetPath) == "target data")
		#expect(try exactNames(in: targetDirectory) == [Exact(decomposed("실제 파일.txt"))])
	}

	@Test("a symlink to a folder, a FIFO and a path with a trailing slash are not regular files")
	func notRegularSources() throws {
		let folderLink = folders.source + "/folder-link"
		#expect(symlink(folders.output, folderLink) == 0)
		let fifo = folders.source + "/fifo"
		#expect(mkfifo(fifo, 0o644) == 0)
		let filePath = try folders.writeSource("file.txt")

		#expect(makePlan(input(folderLink)) == nil)
		#expect(makePlan(input(fifo)) == nil)
		#expect(makePlan(input(filePath + "/")) == nil)
		#expect(makePlan(input("")) == nil)
		#expect(makePlan(input(filePath + "\u{0}.txt")) == nil, "a NUL would cut the path short in C")
		#expect(failureMessage { try copyNormalizedFile(input(fifo)) } == Exact(notRegularFileMessage))
		#expect(try storedNames(in: folders.output).isEmpty)
	}

	@Test("an unreadable source is reported, and its mode is not changed to read it")
	func unreadableSource() throws {
		let sourcePath = try folders.writeSource(decomposed("잠김.txt"))
		#expect(chmod(sourcePath, 0o000) == 0)

		#expect(failureMessage { try copyNormalizedFile(input(sourcePath)) } == Exact("원본 파일을 읽을 권한이 없습니다. 파일 권한을 확인하세요."))

		#expect(try permissionBits(sourcePath) == 0o000)
		#expect(try storedNames(in: folders.output).isEmpty)
		// The preview still works: planning needs no read permission.
		#expect(makePlan(input(sourcePath)) != nil)
	}

	@Test("a source that vanished, or turned into a folder, between the preview and the copy")
	func sourceVanishedAfterThePlan() throws {
		let sourcePath = try folders.writeSource(decomposed("사라짐.txt"))
		#expect(makePlan(input(sourcePath)) != nil)

		#expect(unlink(sourcePath) == 0)
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath)) } == Exact(notRegularFileMessage))

		#expect(mkdir(sourcePath, 0o755) == 0)
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath)) } == Exact(notRegularFileMessage))
		#expect(try storedNames(in: folders.output).isEmpty)
	}

	@Test("data is copied exactly: an empty file, and one larger than a copy buffer")
	func dataIsCopiedExactly() throws {
		let emptyPath = try folders.writeSource(decomposed("빈 파일.txt"), "")
		let empty = try copyNormalizedFile(input(emptyPath))
		#expect(try fileStatus(empty.destinationPath).st_size == 0)
		#expect(Exact(empty.destinationName) == Exact("빈 파일.txt"))

		// 3 MiB of a pattern that never repeats at a block boundary.
		var bytes = [UInt8](repeating: 0, count: 3 * 1024 * 1024 + 123)
		for index in bytes.indices {
			bytes[index] = UInt8(truncatingIfNeeded: index &* 31 &+ index / 251)
		}
		let largePath = folders.source + "/" + decomposed("큰 파일.bin")
		#expect(FileManager.default.createFile(atPath: largePath, contents: Data(bytes)))
		#expect(chmod(largePath, 0o755) == 0)

		let large = try copyNormalizedFile(input(largePath))

		#expect(FileManager.default.contents(atPath: large.destinationPath) == Data(bytes))
		#expect(try permissionBits(large.destinationPath) == 0o755, "the executable bits are kept")
	}

	@Test("only the permission bits are carried over: setuid, setgid and sticky are dropped")
	func specialModeBitsAreDropped() throws {
		// (mode of the source, mode of the copy). The copy gets the nine permission bits and nothing else. (In the
		// Electron app setuid and setgid were lost too, cleared by the kernel when the data was written after the
		// mode; only the sticky bit of a file came along there, and it does not here.)
		let cases: [(mode_t, mode_t)] = [(0o6755, 0o755), (0o1640, 0o640), (0o4500, 0o500)]
		var checked = 0

		for (index, (sourceMode, copyMode)) in cases.enumerated() {
			let sourcePath = try folders.writeSource("tool-\(index).command")
			guard chmod(sourcePath, sourceMode) == 0, try permissionBits(sourcePath) == sourceMode else {
				print("skipped: mode \(String(sourceMode, radix: 8)) cannot be set on a file here")
				continue
			}

			let created = try copyNormalizedFile(input(sourcePath))

			#expect(try permissionBits(created.destinationPath) == copyMode)
			#expect(try permissionBits(sourcePath) == sourceMode, "the original's mode is not touched")
			checked += 1
		}

		#expect(checked > 0)
	}

	// MARK: Quarantine

	@Test("no quarantine on the source: none on the copy")
	func quarantineAbsent() throws {
		let sourcePath = try folders.writeSource(decomposed("깨끗한 파일.txt"))
		try setExtendedAttribute("user.other", Array("x".utf8), atPath: sourcePath)

		let created = try copyNormalizedFile(input(sourcePath))

		#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == nil)
		#expect(!extendedAttributeNames(atPath: created.destinationPath).contains(quarantineAttributeName))
	}

	@Test("the quarantine value is carried over byte for byte, whatever it contains")
	func quarantineValueIsCopiedExactly() throws {
		let values: [[UInt8]] = [
			Array("0083;66f00000;Safari;".utf8),
			Array("0081;5f0e1b2c;Google Chrome;8A1F3C2D-0000-4E5F-9A6B-123456789ABC".utf8),
			Array("0083;66f00000;사파리;".utf8),
			Array("0083;66f00000;Safari;\n".utf8),
			Array("hello".utf8),
			[],
			[UInt8](repeating: UInt8(ascii: "q"), count: 2000)
		]

		for (index, value) in values.enumerated() {
			let sourcePath = try folders.writeSource("download-\(index).command")
			try setExtendedAttribute(quarantineAttributeName, value, atPath: sourcePath)
			// Read-only as well for every other case.
			#expect(chmod(sourcePath, index % 2 == 0 ? 0o444 : 0o644) == 0)

			let created = try copyNormalizedFile(input(sourcePath))

			#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == value, "value \(index)")
			#expect(extendedAttribute(quarantineAttributeName, atPath: sourcePath) == value, "the source's value \(index) is untouched")
		}
	}

	@Test("a quarantine flag that cannot be asked for is taken as no flag, as the Electron app did")
	func quarantineThatCannotBeRead() throws {
		// With an ACL that denies reading extended attributes, fgetxattr fails with EACCES whether the file has the
		// flag or not, so the two cannot be told apart. The Electron app's `xattr -p` failed the same way and the
		// file was copied; refusing here would also refuse files that never had a flag.
		for (index, hasFlag) in [false, true].enumerated() {
			let sourcePath = try folders.writeSource("locked-\(index).command", "data")
			if hasFlag {
				try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
			}
			let denied = try run("/bin/chmod", ["+a", "everyone deny readextattr", sourcePath]).status == 0
			let result = getxattr(sourcePath, quarantineAttributeName, nil, 0, 0, 0)
			let code = errno
			guard denied, result == -1, code == EACCES else {
				print("skipped: an ACL does not stop this user from reading extended attributes here")
				return
			}

			let created = try copyNormalizedFile(input(sourcePath))

			#expect(Exact(created.destinationName) == Exact("locked-\(index).command"))
			#expect(try readFile(created.destinationPath) == "data")
			if !hasFlag {
				#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == nil)
			}
			// (For the flagged file, fcopyfile stamps a flag of its own on the copy. The Core does not rely on that.)
		}
	}

	@Test("a quarantine flag that is there but cannot be read: the copy is refused and removed")
	func quarantineValueCannotBeRead() throws {
		let sourcePath = try folders.writeSource(decomposed("내려받은 파일.command"), "data")
		try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
		let real = FileSystemAccess.real
		let refused = "다운로드 보안 표시(quarantine)를 사본에 옮기지 못했습니다. 다른 저장 위치를 선택하세요."

		// The size of the value is reported, so the file has the flag; then reading the value fails. (Staged: no
		// real volume can be made to fail between two calls on the same open file.)
		var fileSystem = real
		fileSystem.readAttribute = { descriptor, name, buffer in
			if buffer != nil {
				throw SystemCallError(code: EIO)
			}
			return try real.readAttribute(descriptor, name, nil)
		}
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem) } == Exact(refused))
		#expect(try storedNames(in: folders.output).isEmpty, "a copy that lost the flag is not left behind")

		// The value keeps growing between the two calls (ERANGE): asked again a few times, then refused.
		let attempts = Recorded<Int>()
		fileSystem.readAttribute = { descriptor, name, buffer in
			guard let buffer else {
				return try real.readAttribute(descriptor, name, nil)
			}
			attempts.add(buffer.count)
			throw SystemCallError(code: ERANGE)
		}
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem) } == Exact(refused))
		#expect(attempts.values == [sampleQuarantine.utf8.count, sampleQuarantine.utf8.count, sampleQuarantine.utf8.count, sampleQuarantine.utf8.count])
		#expect(try storedNames(in: folders.output).isEmpty)

		// It grew once: the second try reads it, and the copy carries the exact value.
		let firstTry = Recorded<Int>()
		fileSystem.readAttribute = { descriptor, name, buffer in
			if buffer != nil, firstTry.values.isEmpty {
				firstTry.add(1)
				throw SystemCallError(code: ERANGE)
			}
			return try real.readAttribute(descriptor, name, buffer)
		}
		let created = try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem)
		#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == Array(sampleQuarantine.utf8))
		#expect(firstTry.values == [1])

		// The flag was taken off the file between the two calls (ENOATTR): nothing to carry over, the copy is made.
		fileSystem.readAttribute = { descriptor, name, buffer in
			if buffer != nil {
				throw SystemCallError(code: ENOATTR)
			}
			return try real.readAttribute(descriptor, name, nil)
		}
		let withoutFlag = try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem)
		#expect(Exact(withoutFlag.destinationName) == Exact("내려받은 파일 (1).command"))

		// The real read, for the record: the size first, then the bytes.
		let descriptor = open(sourcePath, O_RDONLY)
		try #require(descriptor >= 0)
		defer { close(descriptor) }
		#expect(try real.readAttribute(descriptor, quarantineAttributeName, nil) == sampleQuarantine.utf8.count)
		var value = [UInt8](repeating: 0, count: 64)
		let length = try value.withUnsafeMutableBytes { try real.readAttribute(descriptor, quarantineAttributeName, $0) }
		#expect(Array(value.prefix(length)) == Array(sampleQuarantine.utf8))
		#expect(throws: SystemCallError(code: ENOATTR)) { try real.readAttribute(descriptor, "user.hangeul-filename-fixer.none", nil) }
	}

	// MARK: Destinations

	@Test("a destination folder written with a trailing slash, doubled slashes or dots")
	func destinationFolderSpelling() throws {
		let sourcePath = try folders.writeSource(decomposed("슬래시.txt"), "data")

		for (index, directory) in [folders.output + "/", folders.output + "//", folders.work + "/./output/", folders.source + "/../output"].enumerated() {
			let created = try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: directory, baseName: "이름 \(index)"))

			#expect(Exact(created.destinationPath) == Exact(folders.output + "/" + "이름 \(index).txt"))
			#expect(Exact(created.destinationName) == Exact("이름 \(index).txt"))
			#expect(try readFile(folders.output + "/" + "이름 \(index).txt") == "data")
		}
		#expect(try storedNames(in: folders.output).count == 4)
	}

	@Test("a name that is too long")
	func nameTooLong() throws {
		let sourcePath = try folders.writeSource(decomposed("원본.txt"), "data")
		let tooLong = "파일명이 너무 깁니다. 더 짧은 이름을 입력하세요."

		// APFS allows 255 UTF-16 units: 252 syllables + ".txt" is one too many.
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath, baseName: String(repeating: "가", count: 252))) } == Exact(tooLong))
		#expect(try storedNames(in: folders.output).isEmpty)

		// 251 syllables + ".txt" fits (757 bytes: the limit is not 255 bytes).
		let longest = String(repeating: "가", count: 251)
		let created = try copyNormalizedFile(input(sourcePath, baseName: longest))
		#expect(Exact(created.destinationName) == Exact(longest + ".txt"))
		#expect(try exactNames(in: folders.output) == [Exact(longest + ".txt")])

		// Taken now, and " (1)" does not fit: the name is reported as too long, the first copy is left alone.
		let plan = try #require(makePlan(input(sourcePath, baseName: longest)))
		#expect(Exact(plan.destinationName) == Exact(longest + " (1).txt"))
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath, baseName: longest)) } == Exact(tooLong))
		#expect(try exactNames(in: folders.output) == [Exact(longest + ".txt")])
		#expect(try readFile(created.destinationPath) == "data")
	}

	@Test("a read-only folder, a missing folder and a folder that is a file")
	func destinationFolderProblems() throws {
		let sourcePath = try folders.writeSource(decomposed("문서.txt"))

		#expect(chmod(folders.output, 0o555) == 0)
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath)) } == Exact("이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요."))
		#expect(chmod(folders.output, 0o755) == 0)
		#expect(try storedNames(in: folders.output).isEmpty)

		let missing = PlanInput(sourcePath: sourcePath, outputDirectory: folders.work + "/" + "없는 폴더", baseName: "")
		#expect(failureMessage { try copyNormalizedFile(missing) } == Exact("원본 파일이나 저장 위치를 찾을 수 없습니다. 파일을 다시 선택하세요."))
		#expect(!nameIsTaken(folders.work + "/" + "없는 폴더"), "the folder is not created")

		let filePath = try writeFile(folders.work + "/" + "폴더가 아님", "a file")
		let notAFolder = PlanInput(sourcePath: sourcePath, outputDirectory: filePath, baseName: "")
		#expect(failureMessage { try copyNormalizedFile(notAFolder) } == Exact("사본을 만들지 못했습니다. (ENOTDIR)"))
		#expect(try readFile(filePath) == "a file")

		let withNUL = PlanInput(sourcePath: sourcePath, outputDirectory: folders.output + "\u{0}/elsewhere", baseName: "")
		#expect(failureMessage { try copyNormalizedFile(withNUL) } == Exact("사본을 만들지 못했습니다. (EINVAL)"))
		#expect(try storedNames(in: folders.output).isEmpty, "the path is not cut at the NUL")
	}

	@Test("a folder that takes the copy but cannot be listed: the copy is removed again")
	func destinationFolderThatCannotBeListed() throws {
		let sourcePath = try folders.writeSource(decomposed("문서.txt"))
		// Write and search permission without read permission: open(2) works, readdir does not.
		#expect(chmod(folders.output, 0o300) == 0)

		let message = failureMessage { try copyNormalizedFile(input(sourcePath)) }

		#expect(chmod(folders.output, 0o755) == 0)
		#expect(message == Exact("이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요."))
		#expect(try storedNames(in: folders.output).isEmpty, "a copy whose name could not be checked is not left behind")
	}

	@Test("a folder whose listing fails after the copy was made: the copy is removed, the error is named")
	func listingFailsAfterTheCopy() throws {
		let sourcePath = try folders.writeSource(decomposed("문서.txt"))
		let output = folders.output
		let fileSystem = FileSystemAccess(entryExists: FileSystemAccess.real.entryExists, directoryEntries: { directory in
			if directory.utf8.elementsEqual(output.utf8) {
				throw SystemCallError(code: EIO)
			}
			return try FileSystemAccess.real.directoryEntries(directory)
		})

		#expect(failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem) } == Exact("사본을 만들지 못했습니다. (EIO)"))
		#expect(try storedNames(in: folders.output).isEmpty)
	}

	@Test("a write error that the volume reports only when the copy is closed: the copy is removed, the error is named")
	func closeReportsAWriteError() throws {
		let sourcePath = try folders.writeSource(decomposed("늦은 오류.txt"), "data")
		let real = FileSystemAccess.real
		let cases: [(Int32, String)] = [
			(EIO, "사본을 만들지 못했습니다. (EIO)"),
			(EDQUOT, "사본을 만들지 못했습니다. (EDQUOT)"),
			(ENOSPC, "저장 공간이 부족합니다.")
		]

		// No local volume fails in close(2); a network share or a volume with a quota does. The staged close closes
		// the descriptor, as the real one does also when it reports an error, and then reports that error.
		for (code, expected) in cases {
			let closed = Recorded<Int32>()
			let fileSystem = FileSystemAccess(entryExists: real.entryExists, directoryEntries: real.directoryEntries, closeCopy: { descriptor in
				closed.add(descriptor)
				close(descriptor)
				throw SystemCallError(code: code)
			})

			let message = failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem) }

			#expect(message == Exact(expected))
			#expect(try storedNames(in: folders.output).isEmpty, "a copy that may be incomplete is not left behind")
			#expect(closed.values.count == 1)
		}

		#expect(openDescriptorPaths(under: folders.work) == [])
		#expect(try readFile(sourcePath) == "data")
	}

	@Test("the copy is closed once, when it is complete, and its result is the real close(2)'s")
	func copyIsClosedOnceWhenComplete() throws {
		let sourcePath = try folders.writeSource(decomposed("닫기.txt"), "data")
		try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
		#expect(chmod(sourcePath, 0o444) == 0)
		let real = FileSystemAccess.real
		let output = folders.output

		// What the copy looks like at the moment it is closed: everything is written, so close(2) has the last word.
		let seen = Recorded<String>()
		let watching = FileSystemAccess(entryExists: real.entryExists, directoryEntries: real.directoryEntries, closeCopy: { descriptor in
			var status = stat()
			var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
			var flag = [UInt8](repeating: 0, count: 64)
			let flagLength = fgetxattr(descriptor, quarantineAttributeName, &flag, flag.count, 0, 0)
			if fstat(descriptor, &status) == 0, fcntl(descriptor, F_GETPATH, &path) == 0 {
				let name = baseName(ofPath: path.withUnsafeBufferPointer { String(cString: $0.baseAddress!) })
				seen.add("\(name) size=\(status.st_size) mode=\(String(status.st_mode & 0o7777, radix: 8)) flag=\(String(decoding: flag.prefix(max(flagLength, 0)), as: UTF8.self))")
			}
			try real.closeCopy(descriptor)
			// Closed for good: the number no longer names the copy. (Another test's file may have taken the number.)
			var pathAfter = [CChar](repeating: 0, count: Int(MAXPATHLEN))
			let stillTheCopy = fcntl(descriptor, F_GETPATH, &pathAfter) == 0 && strcmp(pathAfter, path) == 0
			seen.add(stillTheCopy ? "still open" : "closed")
		})

		let created = try copyNormalizedFile(input(sourcePath), fileSystem: watching)

		#expect(seen.values == ["닫기.txt size=4 mode=444 flag=\(sampleQuarantine)", "closed"])
		#expect(try readFile(created.destinationPath) == "data")

		// A copy that is refused before that point is closed as well, without asking for the result.
		let neverCalled = Recorded<Int32>()
		let listsDecomposed = FileSystemAccess(
			entryExists: real.entryExists,
			directoryEntries: { directory in
				let entries = try real.directoryEntries(directory)
				return directory.utf8.elementsEqual(output.utf8) ? entries.map(decomposed) : entries
			},
			closeCopy: { neverCalled.add($0) }
		)
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath, baseName: "한글 이름"), fileSystem: listsDecomposed) } != nil)
		#expect(neverCalled.values == [])
		#expect(openDescriptorPaths(under: folders.work) == [])

		// The real close reports what close(2) reports.
		#expect(throws: SystemCallError(code: EBADF)) { try closeDescriptor(-1) }
	}

	@Test("the preview does not need the destination folder to exist")
	func planForAMissingFolder() throws {
		let sourcePath = try folders.writeSource(decomposed("문서.txt"))
		let missing = folders.work + "/" + "없는 폴더"

		let plan = try #require(makePlan(PlanInput(sourcePath: sourcePath, outputDirectory: missing, baseName: "")))

		#expect(Exact(plan.destinationPath) == Exact(missing + "/" + "문서.txt"))
		#expect(plan.hasNumberSuffix == false)
		#expect(!nameIsTaken(missing), "planning creates nothing")
		#expect(try storedNames(in: folders.output).isEmpty)
	}

	@Test("no descriptor stays open, whether the copy succeeds or fails")
	func descriptorsAreClosedOnEveryPath() throws {
		let sourcePath = try folders.writeSource(decomposed("열린 파일.txt"), "data")
		try setExtendedAttribute(quarantineAttributeName, Array(sampleQuarantine.utf8), atPath: sourcePath)
		let output = folders.output
		let real = FileSystemAccess.real
		let neverTaken = FileSystemAccess(entryExists: { _ in false }, directoryEntries: real.directoryEntries)
		let listsDecomposed = FileSystemAccess(entryExists: real.entryExists, directoryEntries: { directory in
			let entries = try real.directoryEntries(directory)
			return directory.utf8.elementsEqual(output.utf8) ? entries.map(decomposed) : entries
		})
		let cannotList = FileSystemAccess(entryExists: real.entryExists, directoryEntries: { directory in
			if directory.utf8.elementsEqual(output.utf8) {
				throw SystemCallError(code: EIO)
			}
			return try real.directoryEntries(directory)
		})

		// One success, then every way to fail: before the copy exists, while creating it, and after it was made.
		_ = try copyNormalizedFile(input(sourcePath))
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: neverTaken) } != nil)
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: listsDecomposed) } != nil)
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: cannotList) } != nil)
		#expect(failureMessage { try copyNormalizedFile(input(sourcePath, baseName: String(repeating: "가", count: 300))) } != nil)
		#expect(failureMessage { try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.work + "/missing", baseName: "")) } != nil)
		#expect(failureMessage { try copyNormalizedFile(input(folders.source)) } != nil)
		#expect(makePlan(input(sourcePath)) != nil)

		#expect(openDescriptorPaths(under: folders.work) == [])
		#expect(try exactNames(in: folders.output) == [Exact("열린 파일.txt")], "only the one successful copy is left")
	}

	@Test("a read-only volume")
	func readOnlyVolume() throws {
		// The system volume is mounted read-only on every supported macOS; nothing can be created there.
		guard access("/", W_OK) != 0, errno == EROFS else {
			print("skipped: / is not a read-only volume here")
			return
		}

		let sourcePath = try folders.writeSource("hangeul-filename-fixer-test-\(UUID().uuidString).txt")
		let message = failureMessage { try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: "/", baseName: "")) }

		#expect(message == Exact("읽기 전용 위치에는 저장할 수 없습니다. 다른 저장 위치를 선택하세요."))
	}

	@Test("every errno has its Korean message, and unknown ones name the error")
	func errorMessages() {
		let notWritable = "이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요."
		let expected: [(Int32, String)] = [
			(EACCES, notWritable),
			(EPERM, notWritable),
			(EROFS, "읽기 전용 위치에는 저장할 수 없습니다. 다른 저장 위치를 선택하세요."),
			(ENOSPC, "저장 공간이 부족합니다."),
			(ENOENT, "원본 파일이나 저장 위치를 찾을 수 없습니다. 파일을 다시 선택하세요."),
			(ENAMETOOLONG, "파일명이 너무 깁니다. 더 짧은 이름을 입력하세요."),
			(EEXIST, "같은 이름의 파일이 방금 생겼습니다. 다시 시도하세요."),
			(EIO, "사본을 만들지 못했습니다. (EIO)"),
			(ENOTDIR, "사본을 만들지 못했습니다. (ENOTDIR)"),
			(EISDIR, "사본을 만들지 못했습니다. (EISDIR)"),
			(EDQUOT, "사본을 만들지 못했습니다. (EDQUOT)"),
			(EFBIG, "사본을 만들지 못했습니다. (EFBIG)"),
			(9999, "사본을 만들지 못했습니다. (errno 9999)")
		]

		for (code, message) in expected {
			#expect(Exact(userFacingError(forErrno: code).message) == Exact(message))
		}
		#expect(UserFacingError(message: "한국어").localizedDescription == "한국어")

		// The public function can throw nothing but a UserFacingError; this line stops compiling if that changes.
		let copy: (PlanInput) throws(UserFacingError) -> FileCopyPlan = copyNormalizedFile
		#expect(failureMessage { try copy(PlanInput(sourcePath: "", outputDirectory: "", baseName: "")) } == Exact(notRegularFileMessage))
	}

	@Test("an error without a message of its own is named as Node named it")
	func errorNames() {
		// util.getSystemErrorName(-code) of Node 22 (libuv 1.53) on macOS, for every errno it has a name for. The
		// Electron app showed this name in "사본을 만들지 못했습니다. (…)".
		let nodeNames: [(Int32, String)] = [
			(1, "EPERM"), (2, "ENOENT"), (3, "ESRCH"), (4, "EINTR"), (5, "EIO"), (6, "ENXIO"), (7, "E2BIG"), (8, "ENOEXEC"),
			(9, "EBADF"), (12, "ENOMEM"), (13, "EACCES"), (14, "EFAULT"), (16, "EBUSY"), (17, "EEXIST"), (18, "EXDEV"),
			(19, "ENODEV"), (20, "ENOTDIR"), (21, "EISDIR"), (22, "EINVAL"), (23, "ENFILE"), (24, "EMFILE"), (25, "ENOTTY"),
			(26, "ETXTBSY"), (27, "EFBIG"), (28, "ENOSPC"), (29, "ESPIPE"), (30, "EROFS"), (31, "EMLINK"), (32, "EPIPE"),
			(34, "ERANGE"), (35, "EAGAIN"), (37, "EALREADY"), (38, "ENOTSOCK"), (39, "EDESTADDRREQ"), (40, "EMSGSIZE"),
			(41, "EPROTOTYPE"), (42, "ENOPROTOOPT"), (43, "EPROTONOSUPPORT"), (44, "ESOCKTNOSUPPORT"), (45, "ENOTSUP"),
			(47, "EAFNOSUPPORT"), (48, "EADDRINUSE"), (49, "EADDRNOTAVAIL"), (50, "ENETDOWN"), (51, "ENETUNREACH"),
			(53, "ECONNABORTED"), (54, "ECONNRESET"), (55, "ENOBUFS"), (56, "EISCONN"), (57, "ENOTCONN"), (58, "ESHUTDOWN"),
			(60, "ETIMEDOUT"), (61, "ECONNREFUSED"), (62, "ELOOP"), (63, "ENAMETOOLONG"), (64, "EHOSTDOWN"),
			(65, "EHOSTUNREACH"), (66, "ENOTEMPTY"), (78, "ENOSYS"), (79, "EFTYPE"), (84, "EOVERFLOW"), (89, "ECANCELED"),
			(92, "EILSEQ"), (96, "ENODATA"), (100, "EPROTO")
		]
		// Node had no name for these ("Unknown system error -69"); the name from <sys/errno.h> says more.
		let darwinOnlyNames: [(Int32, String)] = [(11, "EDEADLK"), (69, "EDQUOT"), (70, "ESTALE"), (93, "ENOATTR"), (102, "EOPNOTSUPP")]
		let ownMessage: Set<Int32> = [EACCES, EPERM, EROFS, ENOSPC, ENOENT, ENAMETOOLONG, EEXIST]
		#expect(nodeNames.count == 65)

		var named: Set<Int32> = []
		for (code, name) in nodeNames + darwinOnlyNames {
			named.insert(code)
			#expect(errnoName(code) == name, "errno \(code)")
			if !ownMessage.contains(code) {
				#expect(Exact(userFacingError(forErrno: code).message) == Exact("사본을 만들지 못했습니다. (\(name))"), "errno \(code)")
			}
		}
		// Every other number is shown as a number.
		for code in Int32(0)...200 where !named.contains(code) {
			#expect(errnoName(code) == "errno \(code)")
		}
		// A share that drops the connection in the middle of a copy.
		#expect(Exact(userFacingError(forErrno: ENOTCONN).message) == Exact("사본을 만들지 못했습니다. (ENOTCONN)"))
	}

	// MARK: Threads

	@Test("copies made at the same moment from many threads never overwrite each other")
	func concurrentCopies() throws {
		let sourcePath = try folders.writeSource(decomposed("동시에.txt"), "same data")
		let request = input(sourcePath)
		let results = Results()

		DispatchQueue.concurrentPerform(iterations: 24) { _ in
			do {
				results.add(.success(try copyNormalizedFile(request).destinationName))
			} catch let error as UserFacingError {
				results.add(.failure(error))
			} catch {
				results.add(.failure(UserFacingError(message: "unexpected error type: \(error)")))
			}
		}

		// Two threads may pick the same free name; O_EXCL lets one of them win and the other is told to try again.
		let names = results.values.compactMap { try? $0.get() }
		let failures = results.values.compactMap { result -> String? in
			if case .failure(let error) = result {
				return error.message
			}
			return nil
		}
		#expect(names.count + failures.count == 24)
		#expect(failures.allSatisfy { Exact($0) == Exact("같은 이름의 파일이 방금 생겼습니다. 다시 시도하세요.") })
		#expect(!names.isEmpty)

		let stored = try storedNames(in: folders.output)
		#expect(stored.count == names.count, "one file per successful copy, no leftovers from the refused ones")
		#expect(Set(names.map { Array($0.utf8) }) == Set(stored.map { Array($0.utf8) }))
		for name in stored {
			#expect(isNFCName(name))
			#expect(try readFile(folders.output + "/" + name) == "same data")
		}
	}
}

/// Collects what a staged file-system operation was called with.
private final class Recorded<Value: Sendable>: @unchecked Sendable {
	private let lock = NSLock()
	private var collected: [Value] = []

	func add(_ value: Value) {
		lock.lock()
		collected.append(value)
		lock.unlock()
	}

	var values: [Value] {
		lock.lock()
		defer { lock.unlock() }
		return collected
	}
}

/// Collects results from several threads.
private final class Results: @unchecked Sendable {
	private let lock = NSLock()
	private var collected: [Result<String, UserFacingError>] = []

	func add(_ result: Result<String, UserFacingError>) {
		lock.lock()
		collected.append(result)
		lock.unlock()
	}

	var values: [Result<String, UserFacingError>] {
		lock.lock()
		defer { lock.unlock() }
		return collected
	}
}
