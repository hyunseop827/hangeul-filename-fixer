// The screen for a selected file as SwiftUI really builds it, in a window that is never shown: which text stands
// where, which button can be pressed in which situation, and what a press does. Read and pressed through the
// description SwiftUI gives assistive apps (ScreenReader in TestSupport.swift); the buttons are pure SwiftUI and have
// no AppKit view to look at.
import AppKit
import SwiftUI
import Testing
import HangeulFilenameFixerCore
@testable import HangeulFilenameFixer

@MainActor
@Suite(.serialized) struct DetailScreenTests {
	let folders = TestFolders()

	private func hostedScreen(_ model: AppModel) -> (hosting: NSHostingView<RootView>, window: NSWindow) {
		let hosting = NSHostingView(rootView: RootView(model: model))
		hosting.frame = NSRect(x: 0, y: 0, width: 470, height: 900)
		let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: true)
		window.isReleasedWhenClosed = false
		window.contentView = hosting
		settleScreen(hosting)
		return (hosting, window)
	}

	@Test(.enabled("SwiftUI describes its views to assistive apps only; that is not possible here") { await ScreenReader.isAvailable })
	func theScreenShowsWhatTheModelSaysAndEveryButtonDoesItsOwnThing() async throws {
		guard try isNormalizationInsensitive(folders.source) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}

		let gate = Gate()
		let shell = FakeShell()
		let model = AppModel(
			work: FileWork(makePlan: FileWork.real.makePlan, copy: { input in
				gate.wait()
				return FileWork.real.copy(input)
			}),
			conversions: ConversionTracker()
		)
		model.shell = shell
		// Stored decomposed and with a ":", so the three cards show three different names.
		let sourceName = decomposed("한글 보고서 3:4.txt")
		let sourcePath = try folders.writeSource(sourceName)
		// From the first screen, as in the app.
		let (hosting, window) = hostedScreen(model)
		_ = window
		model.setFile(sourcePath)
		await model.previewSettled()
		func screen() -> ScreenReader {
			settleScreen(hosting)
			return ScreenReader(hosting)
		}
		func text(_ identifier: String, _ reader: ScreenReader) -> Exact? {
			Exact(reader[identifier]?.value)
		}
		func enabledButtons(_ reader: ScreenReader) -> [String] {
			reader.elements.filter { $0.role == NSAccessibility.Role.button.rawValue && $0.isEnabled }.map(\.identifier)
		}

		// MARK: The name is kept

		var reader = screen()
		#expect(reader.identifiers == [
			"backButton", "finderName", "decomposedName", "windowsCompatibleName", "keepNameButton", "renameButton",
			"resultLabel", "resultName", "outputDirectory", "outputDirectoryButton", "convertButton", "revealButton"
		])
		#expect(reader.plainTexts == [
			"선택된 파일", "macOS Finder에서 보이는 이름", "macOS 현재 원본", "Windows에서 보일 수 있는 이름", "변환 후 Windows 호환 이름", "변환 후 Windows 예상",
			"출력 이름", "결과"
		])
		// The three cards: as Finder shows the stored name, as Windows may show it, and tidied.
		#expect(text("finderName", reader) == Exact(decomposed("한글 보고서 3/4.txt")))
		#expect(text("decomposedName", reader) == Exact("ㅎㅏㄴㄱㅡㄹ ㅂㅗㄱㅗㅅㅓ 3:4.txt"))
		#expect(text("windowsCompatibleName", reader) == Exact("한글 보고서 3_4.txt"))
		#expect(reader["backButton"]?.label == "← 다른 파일 선택")
		#expect(reader["keepNameButton"]?.label == "기존 이름 유지")
		#expect(reader["keepNameButton"]?.value == "선택됨")
		#expect(reader["renameButton"]?.label == "이름 바꾸기")
		#expect(reader["renameButton"]?.value == "선택 안 됨")
		#expect(text("resultLabel", reader) == Exact(Wording.willCreate))
		#expect(text("resultName", reader) == Exact("한글 보고서 3_4.txt"))
		#expect(text("outputDirectory", reader) == Exact(folders.source), "the folder the copy goes to, not the file's path")
		#expect(reader["outputDirectoryButton"]?.label == "저장 위치 변경")
		#expect(reader["convertButton"]?.label == "NFC 사본 만들기")
		#expect(reader["revealButton"]?.label == "Finder에서 보기")
		#expect(enabledButtons(reader) == ["backButton", "keepNameButton", "renameButton", "outputDirectoryButton", "convertButton"])
		let field = try #require(findView(NameTextField.self, in: hosting))
		#expect(!field.isEnabled)
		// The pointer: a hand over what can be pressed, "not allowed" over the field and "Finder에서 보기".
		#expect(findViews(PointerAreaView.self, in: hosting).filter { $0.cursor == .pointingHand }.count == 5)
		#expect(findViews(PointerAreaView.self, in: hosting).filter { $0.cursor == .operationNotAllowed }.count == 2)
		// A file name is one line, however long the name.
		let nameRowHeight = try #require(reader["resultName"]).frame.height
		#expect(nameRowHeight > 15 && nameRowHeight < 25, "\(nameRowHeight)")

		// "Finder에서 보기" is off: nothing is shown.
		reader["revealButton"]?.press()
		#expect(shell.revealedPaths.isEmpty)

		// MARK: "이름 바꾸기" and back

		reader["renameButton"]?.press()
		#expect(model.nameMode == .rename)
		reader = screen()
		#expect(reader["keepNameButton"]?.value == "선택 안 됨")
		#expect(reader["renameButton"]?.value == "선택됨")
		#expect(field.isEnabled)
		#expect(text("resultName", reader) == Exact(Wording.typeAName))
		#expect(enabledButtons(reader) == ["backButton", "keepNameButton", "renameButton", "outputDirectoryButton"], "no copy without a name")
		#expect(findViews(PointerAreaView.self, in: hosting).filter { $0.cursor == .operationNotAllowed }.count == 2, "the copy button and Finder")

		reader["keepNameButton"]?.press()
		#expect(model.nameMode == .keep)
		reader = screen()
		#expect(reader["keepNameButton"]?.value == "선택됨")
		#expect(!field.isEnabled)

		// MARK: Another folder

		shell.directoryAnswer = folders.output
		reader = screen()
		reader["outputDirectoryButton"]?.press()
		#expect(shell.directoryRequests.count == 1)
		#expect(Exact(model.outputDirectory) == Exact(folders.output))
		await model.previewSettled()
		reader = screen()
		#expect(text("outputDirectory", reader) == Exact(folders.output))
		#expect(reader["status"] == nil, "no status line yet")

		// MARK: While the copy is being made

		reader["convertButton"]?.press()
		#expect(model.isConverting, "NFC 사본 만들기 starts the copy")
		#expect(shell.directoryRequests.count == 1 && shell.revealedPaths.isEmpty)
		reader = screen()
		#expect(text("status", reader) == Exact(Wording.converting))
		#expect(enabledButtons(reader) == [], "nothing can be changed while the copy is being made")
		#expect(!field.isEnabled)
		#expect(findViews(PointerAreaView.self, in: hosting).filter { $0.cursor == .pointingHand }.isEmpty)
		#expect(findViews(PointerAreaView.self, in: hosting).filter { $0.cursor == .operationNotAllowed }.count == 7)
		// Pressed all the same: nothing happens.
		for identifier in ["backButton", "renameButton", "outputDirectoryButton", "convertButton", "revealButton"] {
			reader[identifier]?.press()
		}
		#expect(Exact(model.sourcePath) == Exact(sourcePath))
		#expect(model.nameMode == .keep)
		#expect(shell.directoryRequests.count == 1)
		#expect(shell.revealedPaths.isEmpty)

		// MARK: The copy exists

		gate.open()
		await model.conversionSettled()
		reader = screen()
		#expect(model.status?.tone == .success)
		#expect(text("status", reader) == Exact(Wording.done))
		#expect(text("resultLabel", reader) == Exact(Wording.created))
		#expect(text("resultName", reader) == Exact("한글 보고서 3_4.txt"))
		#expect(enabledButtons(reader) == ["backButton", "keepNameButton", "renameButton", "outputDirectoryButton", "revealButton"], "one copy per press")
		reader["convertButton"]?.press()
		#expect(!model.isConverting)
		reader["revealButton"]?.press()
		#expect(shell.revealedPaths.map { Exact($0) } == [Exact(folders.output + "/한글 보고서 3_4.txt")])
		#expect(try storedNameBytes(in: folders.output) == [Array("한글 보고서 3_4.txt".utf8)])

		// MARK: Back to the first screen

		reader["backButton"]?.press()
		#expect(model.sourcePath == nil)
		reader = screen()
		#expect(findView(DropTargetView.self, in: hosting) != nil)
		#expect(reader.identifiers == ["dropZone", "footer"])
		#expect(text("footer", reader) == Exact("분리된 한글 파일명을 Windows 호환 이름으로 정리합니다."))
	}

	@Test(.enabled("SwiftUI describes its views to assistive apps only; that is not possible here") { await ScreenReader.isAvailable })
	func hintsAndInstructionsAreShownInTheResultBox() async throws {
		guard try isNormalizationInsensitive(folders.source) else {
			print("skipped: this filesystem is normalization-sensitive")
			return
		}

		// A very long name next to its original: the name stays on one line, and the hint about the number is there.
		let model = AppModel(conversions: ConversionTracker())
		let (hosting, window) = hostedScreen(model)
		_ = window
		model.setFile(try folders.writeSource(decomposed("매우 긴 이름을 가진 파일입니다 그래서 말줄임표가 필요합니다 정말로 아주 깁니다.txt")))
		await model.previewSettled()
		settleScreen(hosting)
		var reader = ScreenReader(hosting)
		#expect(Exact(reader["resultName"]?.value) == Exact("매우 긴 이름을 가진 파일입니다 그래서 말줄임표가 필요합니다 정말로 아주 깁니다 (1).txt"))
		#expect(Exact(reader["resultHint"]?.value) == Exact(Wording.numberAdded))
		let nameHeight = try #require(reader["resultName"]).frame.height
		#expect(nameHeight > 15 && nameHeight < 25, "a file name is cut off, not wrapped: \(nameHeight)")
		#expect(reader.identifiers.contains("convertButton") && reader["convertButton"]?.isEnabled == true)

		// A folder: the instruction takes the name's place and wraps; no hint, no copy.
		model.setFile(folders.output)
		await model.previewSettled()
		settleScreen(hosting)
		reader = ScreenReader(hosting)
		#expect(Exact(reader["resultName"]?.value) == Exact(Wording.notRegularFile))
		#expect(reader["resultHint"] == nil)
		let messageHeight = try #require(reader["resultName"]).frame.height
		#expect(messageHeight > 35, "an instruction wraps instead of being cut off: \(messageHeight)")
		#expect(reader["convertButton"]?.isEnabled == false)

		// A name that is fine already.
		model.setFile(try folders.writeSource("report.txt"))
		await model.previewSettled()
		settleScreen(hosting)
		reader = ScreenReader(hosting)
		#expect(Exact(reader["resultHint"]?.value) == Exact(Wording.alreadyFine))
	}

	/// The two tests above are the only ones that read and press the SwiftUI screen itself. Where SwiftUI does not
	/// describe its views they are skipped and the run would still pass, so where every test is expected to run (CI)
	/// the skip itself fails.
	@Test func theScreenCanBeReadWhereThatIsRequired() {
		guard ScreenReader.isRequired else {
			return
		}

		#expect(
			ScreenReader.isAvailable,
			"SwiftUI gives no accessibility description of its views here, so the tests that read the screen were skipped, and this run requires them (CI or HANGEUL_REQUIRE_SCREEN_READER=1 is set). HANGEUL_REQUIRE_SCREEN_READER=0 allows the skip."
		)
	}

	@Test func theStatusLineHasTheColorOfItsTone() {
		#expect(Theme.statusColor(.success) == Theme.success)
		#expect(Theme.statusColor(.error) == Theme.error)
		#expect(Theme.statusColor(.info) == Theme.muted)
		#expect(Theme.statusColor(nil) == Theme.muted)
		#expect(Theme.success == Color(hex: 0x15803D) && Theme.error == Color(hex: 0xB91C1C) && Theme.muted == Color(hex: 0x6B7280))
	}

	/// The pointer's shape is set by a view that never takes a click, so the SwiftUI button under it is pressed.
	@Test func thePointerAreaLetsEveryClickThrough() {
		let area = PointerAreaView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
		area.cursor = .pointingHand
		#expect(area.hitTest(NSPoint(x: 50, y: 20)) == nil)
		#expect(!area.acceptsFirstResponder)

		area.updateTrackingAreas()
		#expect(area.trackingAreas.count == 1)
		#expect(area.trackingAreas.first?.options.contains([.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect]) == true)
		#expect(area.trackingAreas.first?.owner === area)
	}

	/// The heaviest texts: Korean letters from Apple SD Gothic Neo ExtraBold (as the old app drew them), the rest
	/// from the system font. Lighter texts are the plain system font.
	@Test func heavyKoreanTextIsDrawnExtraBold() throws {
		func fontNames(_ text: String, _ font: NSFont) -> [String] {
			let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
			let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
			return runs.compactMap { run in
				let attributes = CTRunGetAttributes(run) as? [NSAttributedString.Key: Any]
				return (attributes?[.font] as? NSFont).map { $0.fontName }
			}
		}

		for weight in [NSFont.Weight.heavy, .black] {
			let font = Theme.nsFont(size: 12, weight: weight)
			#expect(font.pointSize == 12)
			#expect(fontNames("선택된", font) == ["AppleSDGothicNeo-ExtraBold"])
			// Latin letters, digits and the space stay the system's.
			let mixed = fontNames("NFC사본", font)
			#expect(mixed.count == 2 && mixed.last == "AppleSDGothicNeo-ExtraBold", "\(mixed)")
			#expect(mixed.first?.hasPrefix(".SFNS") == true, "\(mixed)")
		}
		#expect(NameField.font.fontDescriptor == Theme.nsFont(size: 12, weight: .black).fontDescriptor)

		// Up to bold nothing is changed.
		for weight in [NSFont.Weight.regular, .bold] {
			#expect(Theme.nsFont(size: 16, weight: weight) == NSFont.systemFont(ofSize: 16, weight: weight))
		}
	}
}
