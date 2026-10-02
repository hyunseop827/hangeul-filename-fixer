// The model over time: making the copy (really, in a temporary folder), failing, the resets after every change, a
// drop of several files, and previews that arrive too late.
import AppKit
import Darwin
import Foundation
import Testing
import HangeulFilenameFixerCore
@testable import HangeulFilenameFixer

@MainActor
@Suite struct AppModelFlowTests {
	let folders = TestFolders()

	private func selected(_ name: String, content: String = "content", work: FileWork = .real, shell: FakeShell? = nil) async throws -> AppModel {
		let model = AppModel(work: work, conversions: ConversionTracker())
		model.shell = shell
		model.setFile(try folders.writeSource(name, content))
		await model.previewSettled()
		return model
	}

	// MARK: Making the copy

	@Test func makingTheCopyStoresAnNFCNameAndLeavesTheOriginalAlone() async throws {
		let shell = FakeShell()
		let sourceName = decomposed("홍길동_보고서_진짜최종_찐최종.docx")
		let model = try await selected(sourceName, content: "과제 내용", shell: shell)
		let sourcePath = folders.source + "/" + sourceName
		let before = try fileStatus(sourcePath)
		shell.directoryAnswer = folders.output
		model.selectOutputDirectory()
		await model.previewSettled()
		#expect(model.canConvert)

		model.convertFile()

		#expect(model.isConverting)
		#expect(model.status?.tone == .info)
		#expect(model.status?.message == Wording.converting)
		await model.conversionSettled()

		// What the screen says.
		#expect(!model.isConverting)
		#expect(model.status?.tone == .success)
		#expect(model.status?.message == Wording.done)
		#expect(model.resultLabel == Wording.created)
		#expect(Exact(model.resultName) == Exact("홍길동_보고서_진짜최종_찐최종.docx"))
		#expect(model.isShowingFileName)
		#expect(model.resultHint == nil)
		#expect(!model.canConvert, "one copy per press: the button is off until something changes")
		#expect(model.canReveal)
		let created = try #require(model.createdPlan)
		#expect(Exact(created.destinationPath) == Exact(folders.output + "/홍길동_보고서_진짜최종_찐최종.docx"))
		#expect(Exact(created.sourceName) == Exact(sourceName))
		#expect(Exact(model.sourceName) == Exact(sourceName))

		// What is on disk: the copy's name is stored precomposed, byte for byte, with the original's content.
		#expect(try storedNameBytes(in: folders.output) == [Array("홍길동_보고서_진짜최종_찐최종.docx".utf8)])
		#expect(isNFCName(try #require(try storedNames(in: folders.output).first)))
		#expect(try readFile(created.destinationPath) == "과제 내용")

		// The original: same name (still NFD), same file, same content, same dates and mode.
		#expect(try storedNameBytes(in: folders.source) == [Array(sourceName.utf8)])
		let after = try fileStatus(sourcePath)
		#expect(after.st_ino == before.st_ino)
		#expect(after.st_mode == before.st_mode)
		#expect(after.st_size == before.st_size)
		#expect(after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec && after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec)
		#expect(after.st_ctimespec.tv_sec == before.st_ctimespec.tv_sec && after.st_ctimespec.tv_nsec == before.st_ctimespec.tv_nsec)
		#expect(try readFile(sourcePath) == "과제 내용")

		// The preview was asked for again: the name is taken now, so the next copy would get a number.
		#expect(Exact(model.preview.plan?.destinationName) == Exact("홍길동_보고서_진짜최종_찐최종 (1).docx"))

		// Pressing again does nothing.
		model.convertFile()
		#expect(!model.isConverting)
		#expect(try storedNames(in: folders.output).count == 1)

		// "Finder에서 보기" shows the copy.
		model.revealCreatedCopy()
		#expect(shell.revealedPaths.map { Exact($0) } == [Exact(created.destinationPath)])
	}

	@Test func aSecondCopyNextToTheOriginalGetsTheNextNumber() async throws {
		guard try isNormalizationInsensitive(folders.source) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}

		let model = try await selected(decomposed("한글 보고서.txt"))
		#expect(Exact(model.resultName) == Exact("한글 보고서 (1).txt"))

		model.convertFile()
		await model.conversionSettled()
		#expect(Exact(model.createdPlan?.destinationName) == Exact("한글 보고서 (1).txt"))
		#expect(model.createdPlan?.hasNumberSuffix == true)
		#expect(model.resultHint == nil, "no hint once the copy exists")

		// Any change of the request clears the result and offers the next free name.
		model.changeNameMode(.keep)
		#expect(model.createdPlan == nil)
		#expect(model.status == nil)
		#expect(model.resultLabel == Wording.willCreate)
		#expect(Exact(model.resultName) == Exact("한글 보고서 (2).txt"))
		#expect(model.resultHint == Wording.numberAdded)
		#expect(model.canConvert)

		model.convertFile()
		await model.conversionSettled()
		#expect(try exactNames(in: folders.source) == [decomposed("한글 보고서.txt"), "한글 보고서 (1).txt", "한글 보고서 (2).txt"].map { Exact($0) }.sorted { $0.text.utf8.lexicographicallyPrecedes($1.text.utf8) })
		for name in try storedNames(in: folders.source) where !hasSameScalars(name, decomposed("한글 보고서.txt")) {
			#expect(isNFCName(name), "\(Exact(name))")
		}
	}

	@Test func renamedCopy() async throws {
		let model = try await selected(decomposed("한글 보고서.txt"), content: "본문")

		model.changeNameMode(.rename)
		model.setBaseName(decomposed("제출용 보고서"))
		await model.previewSettled()
		model.convertFile()
		await model.conversionSettled()

		#expect(model.status?.tone == .success)
		#expect(Exact(model.resultName) == Exact("제출용 보고서.txt"))
		#expect(try storedNameBytes(in: folders.source).contains(Array("제출용 보고서.txt".utf8)))
		#expect(try readFile(folders.source + "/제출용 보고서.txt") == "본문")
		#expect(Exact(model.nameFieldText) == Exact(decomposed("제출용 보고서")), "the field keeps what was typed")
	}

	@Test func whileTheCopyIsBeingMade() async throws {
		let gate = Gate()
		let copies = Counter()
		let tracker = ConversionTracker()
		let model = AppModel(
			work: FileWork(makePlan: FileWork.real.makePlan, copy: { input in
				copies.increment()
				gate.wait()
				return FileWork.real.copy(input)
			}),
			conversions: tracker
		)
		model.setFile(try folders.writeSource(decomposed("한글 보고서.txt")))
		await model.previewSettled()
		model.changeNameMode(.rename)
		model.setBaseName("사본")
		await model.previewSettled()
		var idleCalls = 0
		tracker.onIdle = { idleCalls += 1 }

		model.convertFile()

		#expect(model.isConverting)
		#expect(model.status?.tone == .info)
		#expect(model.status?.message == Wording.converting)
		#expect(!model.canConvert)
		#expect(!model.canReveal)
		// Nothing about the request can be changed now: not the file, not the mode, not the name, not the folder.
		#expect(!model.canGoBack)
		#expect(!model.canChangeNameMode)
		#expect(!model.canChangeOutputDirectory)
		#expect(!model.isNameFieldEnabled, "the field is off although the mode is 이름 바꾸기")
		#expect(Exact(model.nameFieldText) == Exact("사본"))
		#expect(model.resultLabel == Wording.willCreate)
		#expect(Exact(model.resultName) == Exact("사본.txt"))
		#expect(tracker.running == 1, "quitting waits for this copy")
		#expect(idleCalls == 0)

		// A second press while the first copy is running is ignored.
		model.convertFile()
		gate.open()
		await model.conversionSettled()

		#expect(copies.count == 1)
		#expect(!model.isConverting)
		#expect(model.status?.tone == .success)
		#expect(model.isNameFieldEnabled)
		#expect(model.canGoBack && model.canChangeNameMode && model.canChangeOutputDirectory)
		#expect(tracker.running == 0)
		#expect(idleCalls == 1)
		#expect(try storedNames(in: folders.source).count == 2)
	}

	/// Closing the window lets go of its model. A copy that is being written then is finished and counted all the
	/// same: otherwise quitting, which waits for running copies, would wait forever.
	@Test func aCopyIsFinishedAndCountedAfterItsWindowIsGone() async throws {
		let gate = Gate()
		let tracker = ConversionTracker()
		var idleCalls = 0
		tracker.onIdle = { idleCalls += 1 }
		weak var modelOfTheClosedWindow: AppModel?
		let conversion: Task<Void, Never>
		do {
			let model = AppModel(
				work: FileWork(makePlan: FileWork.real.makePlan, copy: { input in
					gate.wait()
					return FileWork.real.copy(input)
				}),
				conversions: tracker
			)
			model.setFile(try folders.writeSource(decomposed("한글 보고서.txt"), "본문"))
			await model.previewSettled()
			model.changeNameMode(.rename)
			model.setBaseName("사본")
			await model.previewSettled()
			model.convertFile()
			conversion = try #require(model.pendingConversion)
			modelOfTheClosedWindow = model
		}

		// Nobody holds the model any more, except the copy that is running.
		#expect(modelOfTheClosedWindow != nil)
		#expect(tracker.running == 1)
		#expect(idleCalls == 0)

		gate.open()
		await conversion.value

		#expect(tracker.running == 0)
		#expect(idleCalls == 1, "quitting is let through")
		#expect(try storedNameBytes(in: folders.source).contains(Array("사본.txt".utf8)))
		#expect(try readFile(folders.source + "/사본.txt") == "본문")
		// With the copy finished, the model goes too.
		for _ in 0..<500 where modelOfTheClosedWindow != nil {
			try await Task.sleep(nanoseconds: 2_000_000)
		}
		#expect(modelOfTheClosedWindow == nil)
	}

	// MARK: Failing

	@Test func aFailedCopyShowsTheCoresMessageAndCanBeTriedAgain() async throws {
		// A folder without write permission (root would be allowed to write anyway).
		guard getuid() != 0 else {
			print("skipped: root may write to a folder without write permission")
			return
		}

		let shell = FakeShell()
		let model = try await selected(decomposed("한글 보고서.txt"), shell: shell)
		let locked = folders.work + "/잠긴 폴더"
		mkdir(locked, 0o555)
		shell.directoryAnswer = locked
		model.selectOutputDirectory()
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("한글 보고서.txt"))
		#expect(model.canConvert)

		model.convertFile()
		await model.conversionSettled()

		#expect(!model.isConverting)
		#expect(model.status?.tone == .error)
		#expect(Exact(model.status?.message) == Exact(Wording.notWritable))
		#expect(model.createdPlan == nil)
		#expect(!model.canReveal)
		#expect(model.resultLabel == Wording.willCreate)
		#expect(Exact(model.resultName) == Exact("한글 보고서.txt"))
		#expect(model.canConvert, "the same request can be tried again")
		#expect(try storedNames(in: locked).isEmpty, "nothing was left behind")
		#expect(try storedNameBytes(in: folders.source) == [Array(decomposed("한글 보고서.txt").utf8)])

		// Another folder clears the error; the copy then succeeds.
		shell.directoryAnswer = folders.output
		model.selectOutputDirectory()
		#expect(model.status == nil)
		await model.previewSettled()
		model.convertFile()
		await model.conversionSettled()
		#expect(model.status?.tone == .success)
		#expect(try storedNameBytes(in: folders.output) == [Array("한글 보고서.txt".utf8)])
	}

	@Test func aSourceThatDisappearedIsReported() async throws {
		let model = try await selected(decomposed("한글 보고서.txt"))
		#expect(model.canConvert)
		unlink(folders.source + "/" + decomposed("한글 보고서.txt"))

		model.convertFile()
		await model.conversionSettled()

		#expect(model.status?.tone == .error)
		#expect(Exact(model.status?.message) == Exact(Wording.notRegularFile))
		#expect(model.createdPlan == nil)
		// The preview after the attempt knows it too.
		#expect(Exact(model.resultName) == Exact(Wording.notRegularFile))
		#expect(!model.isShowingFileName)
		#expect(!model.canConvert)
		#expect(try storedNames(in: folders.source).isEmpty)
	}

	// MARK: Resets

	@Test func everyChangeClearsTheResultOfTheLastCopy() async throws {
		let shell = FakeShell()
		let model = try await selected(decomposed("한글 보고서.txt"), shell: shell)

		func makeCopy() async {
			model.convertFile()
			await model.conversionSettled()
			#expect(model.createdPlan != nil)
			#expect(model.status?.tone == .success)
		}
		func expectCleared(_ what: String) {
			#expect(model.createdPlan == nil, "\(what)")
			#expect(model.status == nil, "\(what)")
			#expect(model.resultLabel == Wording.willCreate, "\(what)")
			#expect(!model.canReveal, "\(what)")
		}

		await makeCopy()
		model.changeNameMode(.rename)
		expectCleared("mode → 이름 바꾸기")

		model.setBaseName("가")
		await model.previewSettled()
		await makeCopy()
		model.setBaseName("가나")
		expectCleared("typing")
		#expect(Exact(model.baseName) == Exact("가나"))

		await model.previewSettled()
		await makeCopy()
		model.changeNameMode(.keep)
		expectCleared("mode → 기존 이름 유지")
		#expect(Exact(model.baseName) == Exact("가나"))

		await model.previewSettled()
		await makeCopy()
		shell.directoryAnswer = nil
		model.selectOutputDirectory()
		#expect(model.createdPlan != nil, "a cancelled folder panel leaves the result")
		#expect(model.status?.tone == .success)
		shell.directoryAnswer = folders.output
		model.selectOutputDirectory()
		expectCleared("folder")
		#expect(Exact(model.outputDirectory) == Exact(folders.output))

		await model.previewSettled()
		await makeCopy()
		// Another file: everything starts over, the copy goes next to the new file again.
		let other = try folders.writeSource("other.pdf")
		model.changeNameMode(.rename)
		model.setBaseName("이름")
		model.setFile(other)
		expectCleared("another file")
		#expect(Exact(model.sourcePath) == Exact(other))
		#expect(Exact(model.outputDirectory) == Exact(folders.source))
		#expect(model.nameMode == .keep)
		#expect(model.baseName.isEmpty)
		#expect(model.nameFieldText.isEmpty)
		#expect(Exact(model.resultName) == Exact(Wording.loading), "the old file's plan is not shown for the new file")
		#expect(Exact(model.sourceName) == Exact("other.pdf"))
		#expect(!model.canConvert)
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("other (1).pdf"))

		// nil or an empty path selects nothing and changes nothing.
		model.setFile(nil)
		model.setFile("")
		#expect(Exact(model.sourcePath) == Exact(other))
		#expect(Exact(model.resultName) == Exact("other (1).pdf"))
	}

	@Test func goingBackToTheFirstScreen() async throws {
		let model = try await selected(decomposed("한글 보고서.txt"))
		model.changeNameMode(.rename)
		model.setBaseName("이름")
		await model.previewSettled()
		model.convertFile()
		await model.conversionSettled()
		#expect(model.createdPlan != nil)

		model.clearFile()

		#expect(model.sourcePath == nil)
		#expect(model.outputDirectory == nil)
		#expect(model.input == nil)
		#expect(model.createdPlan == nil)
		#expect(model.status == nil)
		#expect(!model.canConvert)
		#expect(!model.canReveal)
		#expect(model.pendingPreview == nil)

		// The next file starts clean: the name kept, nothing typed.
		model.setFile(try folders.writeSource("next.txt"))
		#expect(model.nameMode == .keep)
		#expect(model.baseName.isEmpty)
		#expect(Exact(model.resultName) == Exact(Wording.loading))
		await model.previewSettled()
		#expect(Exact(model.sourceName) == Exact("next.txt"))
		#expect(Exact(model.resultName) == Exact("next (1).txt"))
	}

	// MARK: Dropping

	@Test func droppingSeveralFilesTakesTheFirstAndSaysSo() async throws {
		let first = try folders.writeSource(decomposed("첫째.hwp"))
		let second = try folders.writeSource("second.txt")
		let third = try folders.writeSource("third.txt")
		let model = AppModel(conversions: ConversionTracker())

		model.setDragging(true)
		#expect(model.isDragging)
		model.setDragging(false)
		#expect(!model.isDragging)

		// One file: selected, no message.
		model.setDragging(true)
		model.handleDrop(paths: [second])
		#expect(!model.isDragging)
		#expect(Exact(model.sourcePath) == Exact(second))
		#expect(model.status == nil)
		model.clearFile()

		// Several: the first one, and the message (set after the selection cleared the status).
		model.setDragging(true)
		model.handleDrop(paths: [first, second, third])
		#expect(!model.isDragging)
		#expect(Exact(model.sourcePath) == Exact(first))
		#expect(Exact(model.outputDirectory) == Exact(folders.source))
		#expect(model.status?.tone == .info)
		#expect(model.status?.message == Wording.onlyOneFile)
		#expect(model.nameMode == .keep)
		await model.previewSettled()
		#expect(Exact(model.sourceName) == Exact(decomposed("첫째.hwp")))
		#expect(model.fileIcon.kind == .hwp)
		#expect(model.status?.message == Wording.onlyOneFile, "the message stays while the preview arrives")
		#expect(model.canConvert)

		// The message goes with the next change.
		model.changeNameMode(.rename)
		#expect(model.status == nil)
	}

	@Test func droppingNothingOrAFolder() async throws {
		let model = AppModel(conversions: ConversionTracker())

		model.setDragging(true)
		model.handleDrop(paths: [])
		#expect(!model.isDragging)
		#expect(model.sourcePath == nil)
		#expect(model.status == nil)

		// A folder is selected like a file; the result box then says it cannot be copied.
		model.handleDrop(paths: [folders.output])
		#expect(Exact(model.sourcePath) == Exact(folders.output))
		#expect(Exact(model.outputDirectory) == Exact(folders.work))
		await model.previewSettled()
		#expect(Exact(model.sourceName) == Exact("output"))
		#expect(Exact(model.resultName) == Exact(Wording.notRegularFile))
		#expect(!model.canConvert)

		// A drop whose first item has no path selects nothing, but several items still give the message.
		let untouched = AppModel(conversions: ConversionTracker())
		untouched.handleDrop(paths: ["", folders.output])
		#expect(untouched.sourcePath == nil)
		#expect(untouched.status?.message == Wording.onlyOneFile)
	}

	/// The whole way of a drop: file URLs on a pasteboard, read in order, the first one selected, and the name taken
	/// from the folder, not from the URL (whose path may be spelled differently from the stored name).
	@Test func aDroppedURLIsReadFromThePasteboardInOrder() async throws {
		let stored = try folders.writeSource("한글 문서.hwp")          // stored precomposed
		let decomposedStored = try folders.writeSource(decomposed("둘째 문서.hwp"))
		let pasteboard = NSPasteboard.withUniqueName()
		defer { pasteboard.releaseGlobally() }
		pasteboard.clearContents()
		#expect(DropTargetView.filePaths(from: pasteboard).isEmpty)

		let urls = [URL(fileURLWithPath: stored), URL(fileURLWithPath: decomposedStored), URL(fileURLWithPath: folders.output, isDirectory: true)]
		#expect(pasteboard.writeObjects(urls.map { $0 as NSURL } + [NSURL(string: "https://example.com/a.txt")!]))

		let paths = DropTargetView.filePaths(from: pasteboard)
		// `==` on Strings: the same paths whatever their spelling. Web URLs are not files and are left out.
		#expect(paths == [stored, decomposedStored, folders.output])

		let model = AppModel(conversions: ConversionTracker())
		model.handleDrop(paths: paths)
		await model.previewSettled()
		#expect(Exact(model.sourceName) == Exact("한글 문서.hwp"), "the stored spelling, whatever the URL made of it")
		#expect(model.resultHint == Wording.alreadyFine)
		#expect(model.status?.message == Wording.onlyOneFile)

		// The decomposed one, dropped alone, is recognized as decomposed.
		model.handleDrop(paths: [paths[1]])
		await model.previewSettled()
		#expect(Exact(model.sourceName) == Exact(decomposed("둘째 문서.hwp")))
		#expect(model.resultHint != Wording.alreadyFine)
		#expect(model.status == nil)
	}

	// MARK: Previews that arrive late

	/// A planner that holds back every request for which a gate was registered (by the request's base name or, for
	/// requests that keep the name, by the source's file name).
	private final class HeldPlanner: @unchecked Sendable {
		private let lock = NSLock()
		private var gates: [String: Gate] = [:]
		let calls = Counter()

		func hold(_ key: String) -> Gate {
			let gate = Gate()
			lock.lock()
			gates[key] = gate
			lock.unlock()
			return gate
		}

		func makePlan(_ input: PlanInput) -> FileCopyPlan? {
			calls.increment()
			let key = input.baseName.isEmpty ? baseNameFromPath(input.sourcePath) : input.baseName
			lock.lock()
			let gate = gates[key]
			lock.unlock()
			gate?.wait()
			return HangeulFilenameFixerCore.makePlan(input)
		}
	}

	@Test func aPreviewForAFileThatIsNoLongerSelectedIsDropped() async throws {
		let planner = HeldPlanner()
		let model = AppModel(work: FileWork(makePlan: planner.makePlan, copy: FileWork.real.copy), conversions: ConversionTracker())
		let slow = try folders.writeSource("slow.txt")
		let fast = try folders.writeSource("fast.pdf")
		let slowGate = planner.hold("slow.txt")

		model.setFile(slow)
		let slowPreview = try #require(model.pendingPreview)
		model.setFile(fast)
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("fast (1).pdf"))

		// The answer for the first file arrives now, too late.
		slowGate.open()
		await slowPreview.value
		#expect(Exact(model.sourceName) == Exact("fast.pdf"))
		#expect(Exact(model.resultName) == Exact("fast (1).pdf"))
		#expect(Exact(model.preview.plan?.sourcePath) == Exact(fast))
	}

	@Test func aPreviewThatArrivesAfterGoingBackIsDropped() async throws {
		let planner = HeldPlanner()
		let model = AppModel(work: FileWork(makePlan: planner.makePlan, copy: FileWork.real.copy), conversions: ConversionTracker())
		let gate = planner.hold("slow.txt")

		model.setFile(try folders.writeSource("slow.txt"))
		let preview = try #require(model.pendingPreview)
		model.clearFile()
		gate.open()
		await preview.value

		#expect(model.sourcePath == nil)
		#expect(model.preview.plan == nil)
	}

	/// The same file chosen once more, with nothing else changed: the folder is read again (the name next to the
	/// original may have been taken or freed meanwhile), and the result box is not left at "확인하는 중".
	@Test func selectingTheSameFileAgainAsksForANewPreview() async throws {
		let planner = HeldPlanner()
		let model = AppModel(work: FileWork(makePlan: planner.makePlan, copy: FileWork.real.copy), conversions: ConversionTracker())
		let path = try folders.writeSource("report.txt")
		model.setFile(path)
		await model.previewSettled()
		#expect(planner.calls.count == 1)
		#expect(Exact(model.resultName) == Exact("report (1).txt"))
		let firstPreview = model.pendingPreview

		model.setFile(path)

		#expect(Exact(model.resultName) == Exact(Wording.loading), "starts from loading again")
		#expect(!model.canConvert)
		#expect(model.pendingPreview != nil && model.pendingPreview != firstPreview, "a new request")
		await model.previewSettled()
		#expect(planner.calls.count == 2)
		#expect(Exact(model.resultName) == Exact("report (1).txt"))
		#expect(model.canConvert)

		// Also after going back to the first screen in between.
		model.clearFile()
		model.setFile(path)
		await model.previewSettled()
		#expect(planner.calls.count == 3)
		#expect(Exact(model.resultName) == Exact("report (1).txt"))
	}

	@Test func onlyTheLastTypedNameIsShown() async throws {
		let planner = HeldPlanner()
		let model = AppModel(work: FileWork(makePlan: planner.makePlan, copy: FileWork.real.copy), conversions: ConversionTracker())
		model.setFile(try folders.writeSource("report.txt"))
		await model.previewSettled()
		model.changeNameMode(.rename)
		#expect(planner.calls.count == 1, "switching the mode with nothing typed asks for nothing new")

		let firstGate = planner.hold("가")
		model.setBaseName("가")
		let firstPreview = try #require(model.pendingPreview)
		// Until the answer arrives the last known plan stays on the screen.
		#expect(Exact(model.resultName) == Exact("report (1).txt"))
		#expect(model.isShowingFileName)

		model.setBaseName("가나")
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("가나.txt"))

		firstGate.open()
		await firstPreview.value
		#expect(Exact(model.resultName) == Exact("가나.txt"), "the answer for 가 came last and is dropped")
		#expect(planner.calls.count == 3)

		// Typing the same text again asks for nothing; selecting the same file again does.
		model.setBaseName("가나")
		#expect(planner.calls.count == 3)
		model.setFile(folders.source + "/report.txt")
		await model.previewSettled()
		#expect(planner.calls.count == 4)
	}

	/// The same path spelled the other way is a new request: the comparison is made on bytes.
	@Test func aRespelledNameIsANewRequest() async throws {
		let planner = HeldPlanner()
		let model = AppModel(work: FileWork(makePlan: planner.makePlan, copy: FileWork.real.copy), conversions: ConversionTracker())
		model.setFile(try folders.writeSource("report.txt"))
		await model.previewSettled()
		model.changeNameMode(.rename)

		model.setBaseName("한글")
		await model.previewSettled()
		let callsBefore = planner.calls.count
		model.setBaseName(decomposed("한글"))
		await model.previewSettled()

		#expect("한글" == decomposed("한글"), "equal for Swift")
		#expect(planner.calls.count == callsBefore + 1, "but not the same request")
		#expect(Exact(model.resultName) == Exact("한글.txt"))
	}
}
