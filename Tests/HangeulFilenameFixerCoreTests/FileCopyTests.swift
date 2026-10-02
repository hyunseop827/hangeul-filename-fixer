// Port of tests/filename.test.ts (the Electron app; the file is in the tag v1.1.0): one test per TypeScript test, same
// files and same expectations.
// Where the TypeScript mocked fs.lstatSync and fs.readdirSync, these tests pass a FileSystemAccess with that one
// operation replaced.
import Darwin
import Testing
@testable import HangeulFilenameFixerCore

@Suite("filename.test.ts")
struct FileCopyTests {
	let folders = TestFolders()

	var sourceDirectory: String { folders.source }
	var outputDirectory: String { folders.output }

	private func input(_ sourcePath: String, baseName: String = "") -> PlanInput {
		PlanInput(sourcePath: sourcePath, outputDirectory: outputDirectory, baseName: baseName)
	}

	@Test("makePlan keeps the original name as NFC")
	func makePlanKeepsTheOriginalNameAsNFC() throws {
		let sourcePath = try folders.writeSource(decomposed("홍길동_레포트.hwp"))
		let plan = try #require(makePlan(input(sourcePath)))

		#expect(Exact(plan.destinationName) == Exact("홍길동_레포트.hwp"))
		#expect(Exact(plan.destinationPath) == Exact(outputDirectory + "/" + "홍길동_레포트.hwp"))
		#expect(plan.hasNumberSuffix == false)
	}

	@Test("makePlan uses the typed name with the original extension")
	func makePlanUsesTheTypedName() throws {
		let sourcePath = try folders.writeSource(decomposed("원본.hwp"))
		func plan(_ baseName: String) -> Exact? {
			makePlan(input(sourcePath, baseName: baseName)).map { Exact($0.destinationName) }
		}

		#expect(plan("새 보고서") == Exact("새 보고서.hwp"))
		#expect(plan("새 보고서.HWP") == Exact("새 보고서.hwp"), "a typed copy of the extension is dropped")
		#expect(plan("보고서.hwp.") == Exact("보고서.hwp"))
		#expect(plan(".숨김") == Exact("숨김.hwp"), "a leading dot would hide the copy in Finder")
		#expect(plan(". .x") == Exact("x.hwp"))
		#expect(plan("...") == Exact("파일.hwp"))
		#expect(plan("   ") == Exact("원본.hwp"), "a blank name keeps the original")
	}

	@Test("makePlan reports the source name as stored, whatever the path's normalization")
	func makePlanReportsTheSourceNameAsStored() throws {
		let storedName = "한글.txt"
		_ = try folders.writeSource(storedName)
		let decomposedPath = sourceDirectory + "/" + decomposed(storedName)
		guard nameIsTaken(decomposedPath) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}

		// A drag or an open panel may hand over an NFD path even for an NFC file.
		let plan = try #require(makePlan(input(decomposedPath)))

		#expect(Exact(plan.sourceName) == Exact(storedName))
		#expect(Exact(plan.destinationName) == Exact(storedName))
	}

	@Test("makePlan adds (n) when the name is taken")
	func makePlanAddsANumberWhenTheNameIsTaken() throws {
		let sourcePath = try folders.writeSource(decomposed("과제.docx"))
		try writeFile(outputDirectory + "/" + "과제.docx", "existing")
		try writeFile(outputDirectory + "/" + "과제 (1).docx", "existing")

		let plan = try #require(makePlan(input(sourcePath)))

		#expect(Exact(plan.destinationName) == Exact("과제 (2).docx"))
		#expect(plan.hasNumberSuffix == true)
	}

	@Test("makePlan treats the NFD original as taken when saving next to it on APFS")
	func makePlanTreatsTheNFDOriginalAsTaken() throws {
		let sourcePath = try folders.writeSource(decomposed("같은폴더.txt"))
		let nfcPath = sourceDirectory + "/" + "같은폴더.txt"
		let plan = try #require(makePlan(PlanInput(sourcePath: sourcePath, outputDirectory: sourceDirectory, baseName: "")))

		// APFS and HFS+ look names up regardless of normalization; other filesystems do not.
		let expected = nameIsTaken(nfcPath) ? "같은폴더 (1).txt" : "같은폴더.txt"
		#expect(Exact(plan.destinationName) == Exact(expected))
	}

	@Test("makePlan treats a dangling symlink as a taken name")
	func makePlanTreatsADanglingSymlinkAsTaken() throws {
		let sourcePath = try folders.writeSource(decomposed("링크.txt"))
		#expect(symlink(folders.work + "/" + "없는 대상", outputDirectory + "/" + "링크.txt") == 0)

		let plan = try #require(makePlan(input(sourcePath)))
		#expect(Exact(plan.destinationName) == Exact("링크 (1).txt"))
	}

	@Test("makePlan returns null for folders and missing files")
	func makePlanReturnsNilForFoldersAndMissingFiles() {
		#expect(makePlan(input(sourceDirectory)) == nil)
		#expect(makePlan(input(sourceDirectory + "/" + "없음.txt")) == nil)
	}

	@Test("copyNormalizedFile writes an NFC-named copy and leaves the original alone")
	func copyWritesAnNFCNamedCopy() throws {
		let sourcePath = try folders.writeSource(decomposed("홍길동_레포트.hwp"), "hwp content")

		let created = try copyNormalizedFile(input(sourcePath))

		#expect(Exact(created.destinationName) == Exact("홍길동_레포트.hwp"))
		#expect(try exactNames(in: outputDirectory) == [Exact("홍길동_레포트.hwp")])
		#expect(try readFile(created.destinationPath) == "hwp content")
		#expect(try exactNames(in: sourceDirectory) == [Exact(decomposed("홍길동_레포트.hwp"))])
	}

	@Test("copyNormalizedFile never overwrites: a second copy gets (1)")
	func secondCopyGetsANumber() throws {
		let sourcePath = try folders.writeSource(decomposed("두번.txt"))

		_ = try copyNormalizedFile(input(sourcePath))
		let second = try copyNormalizedFile(input(sourcePath))

		#expect(Exact(second.destinationName) == Exact("두번 (1).txt"))
		#expect(try storedNames(in: outputDirectory).count == 2)
	}

	@Test("copyNormalizedFile never overwrites a file that appears after the name was chosen")
	func copyNeverOverwritesAFileThatAppearsLater() throws {
		let sourcePath = try folders.writeSource(decomposed("경합.txt"), "new")
		let existingPath = outputDirectory + "/" + "경합.txt"
		try writeFile(existingPath, "existing")
		// Make the free-name check miss the existing file, as if it was created a moment later.
		let fileSystem = FileSystemAccess(entryExists: { _ in false }, directoryEntries: FileSystemAccess.real.directoryEntries)

		let message = failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem) }

		#expect(message == Exact("같은 이름의 파일이 방금 생겼습니다. 다시 시도하세요."))
		#expect(try readFile(existingPath) == "existing")
		#expect(try exactNames(in: outputDirectory) == [Exact("경합.txt")])
	}

	@Test("copyNormalizedFile keeps the download quarantine flag")
	func copyKeepsTheQuarantineFlag() throws {
		let sourcePath = try folders.writeSource(decomposed("설치.command"))
		try run("/usr/bin/xattr", ["-w", quarantineAttributeName, sampleQuarantine, sourcePath])

		let created = try copyNormalizedFile(input(sourcePath))
		let copied = try run("/usr/bin/xattr", ["-p", quarantineAttributeName, created.destinationPath]).output

		#expect(copied == "\(sampleQuarantine)\n")
		// Byte for byte: fcopyfile stamps a value of its own (new time, no agent name) that must not survive.
		#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == Array(sampleQuarantine.utf8))
	}

	@Test("copyNormalizedFile copies the quarantine flag onto a read-only copy")
	func copyKeepsTheQuarantineFlagOnAReadOnlyCopy() throws {
		let sourcePath = try folders.writeSource(decomposed("읽기전용.pdf"))
		try run("/usr/bin/xattr", ["-w", quarantineAttributeName, sampleQuarantine, sourcePath])
		#expect(chmod(sourcePath, 0o444) == 0)

		let created = try copyNormalizedFile(input(sourcePath))

		#expect(try permissionBits(created.destinationPath) == 0o444, "the copy keeps the source's mode")
		#expect(try run("/usr/bin/xattr", ["-p", quarantineAttributeName, created.destinationPath]).output.contains("Safari"))
		#expect(extendedAttribute(quarantineAttributeName, atPath: created.destinationPath) == Array(sampleQuarantine.utf8))
		#expect(try permissionBits(sourcePath) == 0o444, "the original's mode is not touched")
	}

	@Test("copyNormalizedFile removes the copy when the stored name is not NFC")
	func copyIsRemovedWhenTheStoredNameIsNotNFC() throws {
		let sourcePath = try folders.writeSource(decomposed("외장.txt"))
		let output = outputDirectory
		// HFS+, exFAT and FAT32 volumes list names decomposed; pretend the output folder is one of them.
		let fileSystem = FileSystemAccess(entryExists: FileSystemAccess.real.entryExists, directoryEntries: { directory in
			let entries = try FileSystemAccess.real.directoryEntries(directory)
			return directory.utf8.elementsEqual(output.utf8) ? entries.map(decomposed) : entries
		})

		let message = failureMessage { try copyNormalizedFile(input(sourcePath), fileSystem: fileSystem) }

		#expect(message == Exact("이 저장 위치는 파일명을 NFC로 유지하지 못합니다(외장 드라이브 등). 내장 디스크의 다른 폴더를 선택하세요."))
		#expect(try storedNames(in: outputDirectory).isEmpty)
	}

	@Test("copyNormalizedFile works for files without a quarantine flag")
	func copyWorksWithoutAQuarantineFlag() throws {
		let sourcePath = try folders.writeSource("plain.txt")
		let created = try copyNormalizedFile(input(sourcePath))

		#expect(Exact(created.destinationName) == Exact("plain.txt"))
	}

	@Test("copyNormalizedFile reports failures in Korean")
	func copyReportsFailuresInKorean() throws {
		let sourcePath = try folders.writeSource("a.txt")

		#expect(failureMessage { try copyNormalizedFile(input(sourceDirectory)) } == Exact(notRegularFileMessage))
		#expect(
			failureMessage {
				try copyNormalizedFile(PlanInput(sourcePath: sourcePath, outputDirectory: folders.work + "/" + "없는 폴더", baseName: ""))
			} == Exact("원본 파일이나 저장 위치를 찾을 수 없습니다. 파일을 다시 선택하세요.")
		)

		#expect(chmod(outputDirectory, 0o555) == 0)
		#expect(
			failureMessage { try copyNormalizedFile(input(sourcePath)) }
				== Exact("이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요.")
		)
		#expect(chmod(outputDirectory, 0o755) == 0)

		#expect(chmod(sourcePath, 0o000) == 0)
		#expect(
			failureMessage { try copyNormalizedFile(input(sourcePath)) }
				== Exact("원본 파일을 읽을 권한이 없습니다. 파일 권한을 확인하세요.")
		)
		#expect(chmod(sourcePath, 0o644) == 0)
	}
}
