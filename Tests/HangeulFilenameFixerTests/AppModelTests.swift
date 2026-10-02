// The model's decisions: what the result box says, which hint is shown and when the copy can be made, for every
// situation the screen distinguishes. Real files in a temporary folder; no window.
import Darwin
import Foundation
import Testing
@testable import HangeulFilenameFixerCore
@testable import HangeulFilenameFixer

/// The texts of the screen, written out once more: a changed wording must fail here.
enum Wording {
	static let willCreate = "생성될 사본 이름"
	static let created = "생성된 사본"
	static let loading = "저장 위치를 확인하는 중입니다."
	static let typeAName = "새 파일명을 입력하세요."
	static let notRegularFile = "일반 파일이 아니거나(폴더·앱 등) 더 이상 없습니다. 파일을 다시 선택하세요."
	static let alreadyFine = "이미 Windows 호환 이름이라 사본을 만들지 않아도 됩니다."
	static let numberAdded = "같은 이름의 파일(원본 포함)이 있어 번호가 붙습니다. 원래 이름 그대로 받으려면 저장 위치를 변경하세요."
	static let onlyOneFile = "파일 하나만 처리합니다. 첫 번째 파일만 선택했습니다."
	static let converting = "사본을 만드는 중입니다…"
	static let done = "완료되었습니다. 저장된 파일명이 NFC인지 확인했습니다."
	static let notWritable = "이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요."
}

@MainActor
@Suite struct AppModelDecisionTests {
	let folders = TestFolders()

	/// A model with `name` (spelled exactly like this) selected and its preview arrived.
	private func modelWithSource(_ name: String, shell: FakeShell? = nil) async throws -> AppModel {
		let model = AppModel(conversions: ConversionTracker())
		model.shell = shell
		model.setFile(try folders.writeSource(name))
		await model.previewSettled()
		return model
	}

	// MARK: No file, loading, not a file

	@Test func startsOnTheFirstScreen() {
		let model = AppModel(conversions: ConversionTracker())

		#expect(model.sourcePath == nil)
		#expect(model.outputDirectory == nil)
		#expect(model.input == nil)
		#expect(model.nameMode == .keep)
		#expect(model.baseName.isEmpty)
		#expect(model.status == nil)
		#expect(model.createdPlan == nil)
		#expect(!model.isConverting)
		#expect(!model.isDragging)
		#expect(!model.canConvert)
		#expect(!model.canReveal)
		#expect(model.canGoBack && model.canChangeNameMode && model.canChangeOutputDirectory)
		#expect(model.sourceName.isEmpty)
		#expect(model.windowsCompatibleName.isEmpty)
		#expect(model.pendingPreview == nil)
	}

	@Test func whileThePreviewIsLoading() async throws {
		let gate = Gate()
		let model = AppModel(
			work: FileWork(makePlan: { gate.wait(); return makePlan($0) }, copy: FileWork.real.copy),
			conversions: ConversionTracker()
		)
		let name = decomposed("한글 보고서.txt")
		let path = try folders.writeSource(name)

		model.setFile(path)

		#expect(Exact(model.sourcePath) == Exact(path))
		#expect(Exact(model.outputDirectory) == Exact(folders.source))
		#expect(model.input == PlanInput(sourcePath: path, outputDirectory: folders.source, baseName: ""))
		// Until the folder has been read, the name is the one the path carries.
		#expect(Exact(model.sourceName) == Exact(name))
		#expect(model.resultLabel == Wording.willCreate)
		#expect(Exact(model.resultName) == Exact(Wording.loading))
		#expect(!model.isShowingFileName)
		#expect(model.resultHint == nil)
		#expect(!model.canConvert)
		#expect(!model.canReveal)

		// "이름 바꾸기" without a name asks for the name first, also while loading.
		model.changeNameMode(.rename)
		#expect(Exact(model.resultName) == Exact(Wording.typeAName))
		model.changeNameMode(.keep)

		gate.open()
		await model.previewSettled()
		#expect(model.isShowingFileName)
		#expect(model.canConvert)
	}

	@Test func aFolderOrAMissingFileCannotBeCopied() async throws {
		let folder = folders.source + "/폴더"
		mkdir(folder, 0o755)
		let app = folders.source + "/앱.app"
		mkdir(app, 0o755)
		let missing = folders.source + "/없는 파일.txt"

		for path in [folder, app, missing] {
			let model = AppModel(conversions: ConversionTracker())
			model.setFile(path)
			await model.previewSettled()

			#expect(model.sourcePath != nil, "\(path) is selected all the same")
			#expect(Exact(model.sourceName) == Exact(baseNameFromPath(path)))
			#expect(model.resultLabel == Wording.willCreate)
			#expect(Exact(model.resultName) == Exact(Wording.notRegularFile))
			#expect(Exact(model.resultName) == Exact(notRegularFileMessage))
			#expect(!model.isShowingFileName)
			#expect(model.resultHint == nil)
			#expect(!model.canConvert)

			// Nothing happens when the copy is asked for anyway.
			model.convertFile()
			#expect(!model.isConverting)
			#expect(model.status == nil)
			#expect(model.pendingConversion == nil)

			// With a name typed it is still not a file.
			model.changeNameMode(.rename)
			model.setBaseName("새 이름")
			await model.previewSettled()
			#expect(Exact(model.resultName) == Exact(Wording.notRegularFile))
			#expect(!model.canConvert)
		}
	}

	// MARK: Keeping the name

	@Test func decomposedSourceNextToTheOriginalGetsANumber() async throws {
		// On APFS the original, stored NFD, already answers to the NFC name the copy wants.
		guard try isNormalizationInsensitive(folders.source) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}

		let model = try await modelWithSource(decomposed("한글 보고서.txt"))

		#expect(Exact(model.sourceName) == Exact(decomposed("한글 보고서.txt")))
		#expect(Exact(model.finderDisplayName) == Exact(decomposed("한글 보고서.txt")))
		#expect(Exact(model.decomposedName) == Exact("ㅎㅏㄴㄱㅡㄹ ㅂㅗㄱㅗㅅㅓ.txt"))
		#expect(Exact(model.windowsCompatibleName) == Exact("한글 보고서.txt"))
		#expect(model.resultLabel == Wording.willCreate)
		#expect(Exact(model.resultName) == Exact("한글 보고서 (1).txt"))
		#expect(model.isShowingFileName)
		// The name is NFD: it is not "already fine", although Swift's `==` calls it equal to its NFC form.
		#expect(model.windowsCompatibleName == model.sourceName)
		#expect(!hasSameScalars(model.windowsCompatibleName, model.sourceName))
		#expect(model.resultHint == Wording.numberAdded)
		#expect(model.canConvert)
		#expect(!model.canReveal)
		#expect(model.status == nil)
	}

	@Test func decomposedSourceToAnotherFolderNeedsNoHint() async throws {
		let shell = FakeShell()
		let model = try await modelWithSource(decomposed("한글 보고서.txt"), shell: shell)
		shell.directoryAnswer = folders.output

		model.selectOutputDirectory()
		await model.previewSettled()

		#expect(shell.directoryRequests.map { Exact($0) } == [Exact(folders.source)], "the panel starts at the current folder")
		#expect(Exact(model.outputDirectory) == Exact(folders.output))
		#expect(Exact(model.resultName) == Exact("한글 보고서.txt"))
		#expect(model.isShowingFileName)
		#expect(model.resultHint == nil)
		#expect(model.canConvert)
		// Nothing is being copied: everything about the request can be changed.
		#expect(model.canGoBack && model.canChangeNameMode && model.canChangeOutputDirectory)
	}

	@Test func alreadyFineSourceSaysSo() async throws {
		let shell = FakeShell()
		// Stored precomposed, and nothing Windows would refuse.
		let model = try await modelWithSource("한글 보고서.txt", shell: shell)

		#expect(Exact(model.sourceName) == Exact("한글 보고서.txt"))
		#expect(hasSameScalars(model.windowsCompatibleName, model.sourceName))
		// Next to the original the copy gets a number, but the hint that matters is that no copy is needed.
		#expect(Exact(model.resultName) == Exact("한글 보고서 (1).txt"))
		#expect(model.preview.plan?.hasNumberSuffix == true)
		#expect(model.resultHint == Wording.alreadyFine)
		#expect(model.canConvert, "the copy can still be made")

		// The same hint in another folder, where no number is needed.
		shell.directoryAnswer = folders.output
		model.selectOutputDirectory()
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("한글 보고서.txt"))
		#expect(model.resultHint == Wording.alreadyFine)

		// Plain ASCII as well.
		let ascii = try await modelWithSource("report-final.pdf")
		#expect(ascii.resultHint == Wording.alreadyFine)
	}

	@Test func precomposedButUnsafeNameIsNotAlreadyFine() async throws {
		let model = try await modelWithSource("회의록 3:4: \"최종\"?::.txt")

		// Finder shows the stored ":" as "/": every one of them.
		#expect(Exact(model.finderDisplayName) == Exact("회의록 3/4/ \"최종\"?//.txt"))
		#expect(Exact(model.decomposedName) == Exact("회의록 3:4: \"최종\"?::.txt"))
		#expect(Exact(model.windowsCompatibleName) == Exact("회의록 3_4_ _최종____.txt"))
		// Another name than the original's, so there is no number and nothing to hint at.
		#expect(Exact(model.resultName) == Exact("회의록 3_4_ _최종____.txt"))
		#expect(model.resultHint == nil)
		#expect(model.canConvert)
	}

	// MARK: Renaming

	@Test func renamingWithoutANameAsksForOne() async throws {
		let model = try await modelWithSource(decomposed("한글 보고서.txt"))

		model.changeNameMode(.rename)
		await model.previewSettled()

		#expect(model.nameMode == .rename)
		#expect(model.customNameMissing)
		#expect(model.isNameFieldEnabled)
		#expect(model.nameFieldText.isEmpty)
		#expect(model.resultLabel == Wording.willCreate)
		#expect(Exact(model.resultName) == Exact(Wording.typeAName))
		#expect(!model.isShowingFileName)
		#expect(model.resultHint == nil, "no hint while a name is missing, not even about the number")
		#expect(!model.canConvert)

		// Only white space is no name either: every character JavaScript's trim() removes.
		for blank in [" ", "   ", "\t", "\n", "\u{00A0}", "\u{3000}", "\u{FEFF}", "\u{2003}\u{2028} \u{FEFF}"] {
			model.setBaseName(blank)
			await model.previewSettled()
			#expect(model.customNameMissing, "\(Exact(blank))")
			#expect(Exact(model.resultName) == Exact(Wording.typeAName))
			#expect(!model.isShowingFileName)
			#expect(!model.canConvert)
			#expect(Exact(model.nameFieldText) == Exact(blank), "the field keeps what was typed")
		}

		model.convertFile()
		#expect(!model.isConverting)
		#expect(model.pendingConversion == nil)
	}

	@Test func charactersThatAreNotWhiteSpaceInJavaScriptAreAName() async throws {
		let model = try await modelWithSource("report.txt")
		model.changeNameMode(.rename)

		// U+0085 and U+200B are white space for Foundation, not for JavaScript's trim().
		for (typed, expected) in [("\u{0085}", "\u{0085}.txt"), ("\u{200B}", "\u{200B}.txt"), (".", "파일.txt"), ("_", "_.txt")] {
			model.setBaseName(typed)
			await model.previewSettled()
			#expect(!model.customNameMissing, "\(Exact(typed))")
			#expect(Exact(model.resultName) == Exact(expected))
			#expect(model.isShowingFileName)
			#expect(model.canConvert)
		}
	}

	@Test func renamingShowsTheTypedNameWithTheOriginalExtension() async throws {
		let model = try await modelWithSource(decomposed("한글 보고서.txt"))
		model.changeNameMode(.rename)

		model.setBaseName("홍길동_보고서")
		await model.previewSettled()
		#expect(Exact(model.baseName) == Exact("홍길동_보고서"))
		#expect(Exact(model.nameFieldText) == Exact("홍길동_보고서"))
		#expect(model.input == PlanInput(sourcePath: folders.source + "/" + decomposed("한글 보고서.txt"), outputDirectory: folders.source, baseName: "홍길동_보고서"))
		#expect(Exact(model.resultName) == Exact("홍길동_보고서.txt"))
		#expect(model.isShowingFileName)
		#expect(model.resultHint == nil)
		#expect(model.canConvert)
		// The three cards are about the original, whatever is typed.
		#expect(Exact(model.windowsCompatibleName) == Exact("한글 보고서.txt"))

		// Typed decomposed, with the extension, with characters Windows refuses: the Core tidies all of it.
		for (typed, expected) in [
			(decomposed("새 이름"), "새 이름.txt"),
			("새 이름.txt", "새 이름.txt"),
			("  새 이름  ", "새 이름.txt"),
			("a:b", "a_b.txt"),
			("CON", "_CON.txt")
		] {
			model.setBaseName(typed)
			await model.previewSettled()
			#expect(Exact(model.resultName) == Exact(expected), "\(Exact(typed))")
			#expect(model.canConvert)
		}
	}

	@Test func renamingNeverSaysAlreadyFine() async throws {
		let model = try await modelWithSource("한글 보고서.txt")
		#expect(model.resultHint == Wording.alreadyFine)

		model.changeNameMode(.rename)
		model.setBaseName("다른 이름")
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("다른 이름.txt"))
		#expect(model.resultHint == nil)

		// The original's own name, typed: it is taken (by the original), so the number hint applies.
		model.setBaseName("한글 보고서")
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("한글 보고서 (1).txt"))
		#expect(model.resultHint == Wording.numberAdded)
		#expect(model.canConvert)
	}

	@Test func typedNameIsKeptWhileTheModeIsSwitched() async throws {
		let model = try await modelWithSource(decomposed("한글 보고서.txt"))
		let sourcePath = folders.source + "/" + decomposed("한글 보고서.txt")

		model.changeNameMode(.rename)
		model.setBaseName("제출용")
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("제출용.txt"))

		model.changeNameMode(.keep)
		#expect(model.nameMode == .keep)
		#expect(Exact(model.baseName) == Exact("제출용"), "kept for later")
		#expect(model.nameFieldText.isEmpty, "the field is empty while the name is kept")
		#expect(!model.isNameFieldEnabled)
		#expect(model.input == PlanInput(sourcePath: sourcePath, outputDirectory: folders.source, baseName: ""))
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact(model.preview.plan?.hasNumberSuffix == true ? "한글 보고서 (1).txt" : "한글 보고서.txt"))

		model.changeNameMode(.rename)
		#expect(Exact(model.nameFieldText) == Exact("제출용"))
		#expect(model.isNameFieldEnabled)
		#expect(model.input == PlanInput(sourcePath: sourcePath, outputDirectory: folders.source, baseName: "제출용"))
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("제출용.txt"))
	}

	// MARK: Icons, panels

	@Test func theIconFollowsTheStoredName() async throws {
		let model = try await modelWithSource(decomposed("발표 자료.PPTX"))
		#expect(model.fileIcon.kind == .powerPoint)
		#expect(model.fileIcon.label == "PPT")
		#expect(model.fileIcon.title == "PowerPoint 문서")
		#expect(model.fileIcon.imageName == "powerpoint")
	}

	@Test func choosingAFileThroughThePanel() async throws {
		let shell = FakeShell()
		let model = AppModel(conversions: ConversionTracker())
		model.shell = shell

		// Cancelled: nothing changes.
		model.selectFile()
		#expect(shell.fileRequests == 1)
		#expect(model.sourcePath == nil)
		#expect(model.pendingPreview == nil)

		// The panel may answer with a path spelled NFC although the file is stored NFD; the stored name is found.
		_ = try folders.writeSource(decomposed("한글 보고서.txt"))
		shell.fileAnswer = folders.source + "/한글 보고서.txt"
		model.selectFile()
		#expect(shell.fileRequests == 2)
		#expect(Exact(model.sourcePath) == Exact(folders.source + "/한글 보고서.txt"))
		#expect(Exact(model.sourceName) == Exact("한글 보고서.txt"), "from the path, until the folder was read")
		await model.previewSettled()
		if try isNormalizationInsensitive(folders.source) {
			#expect(Exact(model.sourceName) == Exact(decomposed("한글 보고서.txt")), "as stored")
			#expect(model.resultHint == Wording.numberAdded)
		}
	}

	@Test func cancellingTheFolderPanelChangesNothing() async throws {
		let shell = FakeShell()
		let model = try await modelWithSource(decomposed("한글 보고서.txt"), shell: shell)
		let previewBefore = model.pendingPreview

		for answer in [nil, ""] as [String?] {
			shell.directoryAnswer = answer
			model.selectOutputDirectory()
			#expect(Exact(model.outputDirectory) == Exact(folders.source))
			#expect(model.pendingPreview == previewBefore, "no new preview")
		}
		#expect(shell.directoryRequests.count == 2)
	}

	@Test func revealingNeedsACreatedCopy() async throws {
		let shell = FakeShell()
		let model = try await modelWithSource("report.txt", shell: shell)

		model.revealCreatedCopy()
		#expect(shell.revealedPaths.isEmpty)
	}
}

// MARK: - Helpers of the model

@Suite struct ModelTextTests {
	@Test func pathsAreCutAtTheLastSlash() {
		#expect(Exact(baseNameFromPath("/Users/me/문서/보고서.txt")) == Exact("보고서.txt"))
		#expect(Exact(directoryFromPath("/Users/me/문서/보고서.txt")) == Exact("/Users/me/문서"))
		#expect(Exact(baseNameFromPath("/보고서.txt")) == Exact("보고서.txt"))
		#expect(Exact(directoryFromPath("/보고서.txt")) == Exact("/"))
		#expect(Exact(baseNameFromPath("/a/b/")) == Exact(""))
		#expect(Exact(directoryFromPath("/a/b/")) == Exact("/a/b"))
		#expect(Exact(baseNameFromPath("/a/.hidden")) == Exact(".hidden"))
		#expect(Exact(baseNameFromPath("이름만")) == Exact("이름만"))
		#expect(Exact(directoryFromPath("이름만")) == Exact("/"))

		// Nothing is respelled or resolved on the way: NFD stays NFD, NFC stays NFC, dots stay dots.
		let nfd = "/" + decomposed("폴더") + "/" + decomposed("한글.txt")
		#expect(Exact(baseNameFromPath(nfd)) == Exact(decomposed("한글.txt")))
		#expect(Exact(directoryFromPath(nfd)) == Exact("/" + decomposed("폴더")))
		#expect(Exact(directoryFromPath("/폴더/../한글.txt")) == Exact("/폴더/.."))
		#expect(Exact(baseNameFromPath("/a/b\u{301}.txt")) == Exact("b\u{301}.txt"))
		// A "/" followed by a combining mark is one Character; the cut is made at the scalar.
		#expect(Exact(baseNameFromPath("/a/\u{301}b.txt")) == Exact("\u{301}b.txt"))
		#expect(Exact(directoryFromPath("/a/\u{301}b.txt")) == Exact("/a"))
	}

	/// The app decides "nothing typed" with its own copy of the white-space set; it must be the Core's, or the
	/// screen would ask for a name the Core accepts (or the other way round).
	@Test func blankMeansWhatTheCoreMeans() {
		var mismatches: [UInt32] = []
		var blankScalars = 0
		for value in UInt32(0)...0x10FFFF {
			guard let scalar = Unicode.Scalar(value) else {
				continue
			}

			// The Core's own set (internal to it), code point by code point.
			let isBlank = isBlankInJavaScript(String(scalar))
			if isBlank != isJavaScriptWhitespace(scalar) {
				mismatches.append(value)
			}
			if isBlank {
				blankScalars += 1
			}
		}
		#expect(mismatches.isEmpty)
		#expect(blankScalars == 25)
		#expect(isBlankInJavaScript(""))
		#expect(!isBlankInJavaScript(" a "))
		#expect(isBlankInJavaScript(" \u{FEFF}\u{3000}\t") == " \u{FEFF}\u{3000}\t".javaScriptTrimmed().unicodeScalars.isEmpty)

		// And in effect: a blank name keeps the original's name, anything else does not.
		let folders = TestFolders()
		let path = try? folders.writeSource("original.txt")
		for typed in ["", " ", "\u{FEFF}", "\u{3000}\t", "\u{0085}", "\u{200B}", "x"] {
			let plan = makePlan(PlanInput(sourcePath: path ?? "", outputDirectory: folders.output, baseName: typed))
			let keepsOriginalName = plan.map { hasSameScalars($0.destinationName, "original.txt") }
			#expect(keepsOriginalName == isBlankInJavaScript(typed), "\(Exact(typed))")
		}
	}

	@Test func iconsByExtension() {
		let expectations: [(String, FileIconType.Kind, String)] = [
			("a.doc", .word, "DOC"), ("a.docx", .word, "DOC"), ("a.hwp", .hwp, "HWP"), ("a.hwpx", .hwp, "HWP"),
			("a.pdf", .pdf, "PDF"), ("a.ppt", .powerPoint, "PPT"), ("a.pptx", .powerPoint, "PPT"),
			("a.xls", .sheet, "XLS"), ("a.xlsx", .sheet, "XLS"), ("a.csv", .sheet, "XLS"),
			("a.txt", .text, "TXT"), ("a.md", .text, "TXT"), ("a.rtf", .text, "TXT"),
			("a.png", .image, "IMG"), ("a.jpg", .image, "IMG"), ("a.jpeg", .image, "IMG"), ("a.gif", .image, "IMG"),
			("a.webp", .image, "IMG"), ("a.heic", .image, "IMG"), ("a.svg", .image, "IMG"),
			("a.zip", .archive, "ZIP"), ("a.rar", .archive, "ZIP"), ("a.7z", .archive, "ZIP"), ("a.tar", .archive, "ZIP"),
			("a.gz", .archive, "ZIP"),
			// The last dot decides, whatever the case; no extension, a hidden file and an unknown one are "FILE".
			("보고서.최종.DOCX", .word, "DOC"), ("a.tar.GZ", .archive, "ZIP"), ("A.Pdf", .pdf, "PDF"),
			("README", .generic, "FILE"), (".pdf", .generic, "FILE"), ("a.pdf.", .generic, "FILE"), ("a.key", .generic, "FILE"),
			("", .generic, "FILE"), ("a.docx ", .generic, "FILE")
		]
		for (name, kind, label) in expectations {
			let icon = FileIconType.forFileName(name)
			#expect(icon.kind == kind, "\(name)")
			#expect(icon.label == label, "\(name)")
		}

		// Nine kinds, each with its own image and tooltip.
		let all = FileIconType.known + [FileIconType.generic]
		#expect(all.count == 9)
		#expect(Set(all.map(\.imageName)) == ["word", "hwp", "pdf", "powerpoint", "excel", "text", "image", "archive", "generic"])
		#expect(all.map(\.title) == ["Word 문서", "한글 문서", "PDF 문서", "PowerPoint 문서", "스프레드시트", "텍스트 문서", "이미지 파일", "압축 파일", "일반 파일"])
	}

	/// The icons the app shows are in the repository for every kind (scripts/build-app.sh copies them into the bundle).
	@Test func everyIconHasItsImageInResources() {
		let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Resources/FileIcons")
		for icon in FileIconType.known + [FileIconType.generic] {
			let pdf = resources.appendingPathComponent(icon.imageName + ".pdf")
			#expect(FileManager.default.fileExists(atPath: pdf.path), "\(pdf.lastPathComponent)")
		}
	}
}
