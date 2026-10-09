// The window: as tall as its content, only its width is the user's, no full screen. And what the app answers AppKit
// about windows and quitting. The window is built as the app builds it, but never put on the screen.
import AppKit
import SwiftUI
import Testing
import HangeulFilenameFixerCore
@testable import HangeulFilenameFixer

/// The arithmetic of the window's size, without a window. AppKit's coordinates: y points up.
@Suite struct WindowFitTests {
	/// A screen of 1440 × 900 with a menu bar of 30 and a Dock of 60.
	private let visible = CGRect(x: 0, y: 60, width: 1440, height: 810)

	@Test func theCardDecidesTheHeightOfTheContent() {
		// The first screen's content is lower than the card's smallest height: 14 above, the card, the 22 of the row with
		// the update link, 10 below.
		#expect(WindowFit.cardHeight(forContent: 0) == 300)
		#expect(WindowFit.cardHeight(forContent: 286) == 300)
		#expect(WindowFit.contentHeight(forCardContent: 286) == 346)
		// The border (1 pt above and below) belongs to the card.
		#expect(WindowFit.cardHeight(forContent: 298) == 300)
		#expect(WindowFit.cardHeight(forContent: 299) == 301)
		#expect(WindowFit.cardHeight(forContent: 700) == 702)
		#expect(WindowFit.contentHeight(forCardContent: 700) == 748)
		// Whole points, never less than the card needs.
		#expect(WindowFit.contentHeight(forCardContent: 700.25) == 749)
		#expect(WindowFit.contentHeight(forCardContent: 700.75) == 749)

		#expect(WindowFit.initialWidth == 470)
		#expect(WindowFit.minimumWidth == 440)
	}

	@Test func theWindowGrowsDownwardFromItsTopLeftCorner() {
		let compact = CGRect(x: 485, y: 500, width: 470, height: 356)

		let taller = WindowFit.frame(compact, withHeight: 700, in: visible)
		#expect(taller == CGRect(x: 485, y: 156, width: 470, height: 700))
		#expect(taller.maxY == compact.maxY, "the top edge stays")
		#expect(taller.minX == compact.minX && taller.width == compact.width)

		// And back: the same corner again.
		#expect(WindowFit.frame(taller, withHeight: 356, in: visible) == compact)
		// Nothing to do.
		#expect(WindowFit.frame(compact, withHeight: 356, in: visible) == compact)

		// The width and the horizontal position are the user's, also half off the screen.
		let wide = CGRect(x: -200, y: 500, width: 900, height: 356)
		#expect(WindowFit.frame(wide, withHeight: 700, in: visible) == CGRect(x: -200, y: 156, width: 900, height: 700))
	}

	@Test func theWindowStaysInsideTheVisibleAreaOfTheScreen() {
		// Growing downward would end below the Dock's edge: the window moves up just far enough.
		let low = CGRect(x: 485, y: 300, width: 470, height: 356)
		let moved = WindowFit.frame(low, withHeight: 700, in: visible)
		#expect(moved == CGRect(x: 485, y: 60, width: 470, height: 700))
		#expect(moved.minY == visible.minY && moved.maxY <= visible.maxY)

		// Taller than the screen has room for: as tall as the visible area, where the card then scrolls.
		let capped = WindowFit.frame(low, withHeight: 2000, in: visible)
		#expect(capped == CGRect(x: 485, y: 60, width: 470, height: 810))

		// A window that hangs out at the top (it was moved there on a bigger screen) comes down.
		let high = CGRect(x: 485, y: 700, width: 470, height: 356)
		#expect(WindowFit.frame(high, withHeight: 356, in: visible) == CGRect(x: 485, y: 514, width: 470, height: 356))

		// A screen whose visible area does not start at 0 (a second screen above the first).
		let upper = CGRect(x: 0, y: 900, width: 1920, height: 1050)
		#expect(WindowFit.frame(CGRect(x: 100, y: 1000, width: 470, height: 356), withHeight: 700, in: upper) == CGRect(x: 100, y: 900, width: 470, height: 700))

		// Not on any screen: only the top-left corner is kept.
		#expect(WindowFit.frame(low, withHeight: 2000, in: nil) == CGRect(x: 485, y: -1344, width: 470, height: 2000))
	}

	@Test func zoomingOnlyWidensTheWindow() {
		let frame = CGRect(x: 485, y: 156, width: 470, height: 700)

		// As wide as the card can use: 900 and the space on both sides.
		#expect(WindowFit.zoomedFrame(frame, in: visible) == CGRect(x: 485, y: 156, width: 924, height: 700))
		// Moved left when it would leave the screen on the right; never wider than the screen.
		#expect(WindowFit.zoomedFrame(CGRect(x: 900, y: 156, width: 470, height: 700), in: visible) == CGRect(x: 516, y: 156, width: 924, height: 700))
		#expect(WindowFit.zoomedFrame(frame, in: CGRect(x: 0, y: 0, width: 800, height: 600)) == CGRect(x: 0, y: 156, width: 800, height: 700))
		#expect(WindowFit.zoomedFrame(CGRect(x: -50, y: 156, width: 470, height: 700), in: visible).minX == 0)
	}
}

/// The window as MainWindowController builds it, with the real screen inside. Never ordered in.
@MainActor
@Suite struct MainWindowTests {
	let folders = TestFolders()

	private func makeWindow(_ model: AppModel? = nil) async -> MainWindowController {
		_ = NSApplication.shared
		let controller = MainWindowController(model: model ?? AppModel(conversions: ConversionTracker()))
		await settleWindow(controller.window)
		return controller
	}

	private func titleBarHeight(_ window: NSWindow) -> CGFloat {
		window.frame.height - window.contentRect(forFrameRect: window.frame).height
	}

	/// What the controller must have made of `frame` for the content the screen reported last.
	private func fitted(_ frame: NSRect, _ controller: MainWindowController) -> NSRect {
		let window = controller.window
		let height = WindowFit.contentHeight(forCardContent: controller.cardContentHeight) + titleBarHeight(window)
		return WindowFit.frame(frame, withHeight: height, in: window.screen?.visibleFrame)
	}

	@Test func theWindowIsAsTallAsTheCardOfTheScreenItShows() async throws {
		let controller = await makeWindow()
		let window = controller.window
		let model = controller.model

		// The first screen: the drop zone and the footer, in the card at its smallest height, and the row with the update
		// link under the card.
		#expect(window.title == "한글 파일명 정리기")
		#expect(controller.cardContentHeight > 250 && controller.cardContentHeight + 2 <= Theme.cardMinHeight)
		let first = window.frame
		#expect(window.contentRect(forFrameRect: first).size == NSSize(width: 470, height: 14 + 300 + 22 + 10))

		// A file is selected: the window is as tall as the taller screen needs.
		model.setFile(try folders.writeSource(decomposed("홍길동_보고서_진짜최종_찐최종.docx")))
		await model.previewSettled()
		await settleWindow(window)
		let detailContent = controller.cardContentHeight
		#expect(detailContent > 550, "\(detailContent)")
		let detail = window.frame
		#expect(detail == fitted(first, controller), "\(detail)")
		#expect(detail.width == 470)
		#expect(detail.height > first.height + 250)
		if window.screen == nil {
			#expect(detail.maxY == first.maxY, "grown downward")
		}

		// A change within the screen: asking for a name takes the hint away (or, without a hint, changes nothing).
		let hadHint = model.resultHint != nil
		model.changeNameMode(.rename)
		await settleWindow(window)
		#expect(model.resultHint == nil)
		#expect(hadHint ? controller.cardContentHeight < detailContent : controller.cardContentHeight == detailContent)
		#expect(window.frame == fitted(detail, controller))

		// Back to the first screen: compact again.
		model.clearFile()
		await settleWindow(window)
		#expect(window.frame.size == first.size)
		#expect(window.frame == fitted(detail, controller))
	}

	@Test func onlyTheWidthIsTheUsersAndThereIsNoFullScreen() async throws {
		let controller = await makeWindow()
		let window = controller.window

		#expect(window.styleMask == [.titled, .closable, .miniaturizable, .resizable])
		#expect(window.collectionBehavior.contains(.fullScreenNone))
		#expect(!window.collectionBehavior.contains(.fullScreenPrimary))
		#expect(window.standardWindowButton(.zoomButton)?.isEnabled == true)
		#expect(!window.isRestorable)
		#expect(window.tabbingMode == .disallowed)
		// The window follows the system's appearance, light or dark (nothing of its own is set); the colors are dynamic.
		#expect(window.appearance == nil)
		#expect(window.backgroundColor == Theme.windowBackground)

		// The smallest and the largest height are the content's; the width starts at 440 and has no end.
		func expectHeightIsHeld() {
			let contentHeight = window.contentRect(forFrameRect: window.frame).height
			#expect(window.contentMinSize == NSSize(width: 440, height: contentHeight))
			#expect(window.contentMaxSize.height == contentHeight)
			#expect(window.contentMaxSize.width >= 100_000)
		}
		expectHeightIsHeld()
		#expect(window.contentRect(forFrameRect: window.frame).height == 346)

		controller.model.setFile(try folders.writeSource("report.txt"))
		await controller.model.previewSettled()
		await settleWindow(window)
		expectHeightIsHeld()

		// Zooming widens to what the card can use; the height stays.
		let zoomed = controller.windowWillUseStandardFrame(window, defaultFrame: NSRect(x: 0, y: 0, width: 3000, height: 2000))
		#expect(zoomed.width == 924)
		#expect(zoomed.height == window.frame.height && zoomed.maxY == window.frame.maxY)
	}

	/// "확대/축소" on the first screen, a file is selected, "확대/축소" again. Zooming back, AppKit puts the window where its
	/// bottom-left corner was and at least as tall as the (taller) content: the top edge would move. The controller puts
	/// it back before the window is fitted to the content at its old width.
	@Test func zoomingBackKeepsTheTopEdge() async throws {
		let controller = await makeWindow()
		let window = controller.window
		func settle() async {
			for _ in 0..<3 {
				await settleWindow(window)
			}
		}
		/// `frame` with its top edge kept, at `x`, as wide as `width` and as tall as the content needs now.
		func fittedKeepingTheTop(of frame: NSRect, x: CGFloat, width: CGFloat) -> NSRect {
			fitted(NSRect(x: x, y: frame.minY, width: width, height: frame.height), controller)
		}

		let first = window.frame
		window.zoom(nil)
		await settle()
		let zoomedFirst = window.frame
		#expect(zoomedFirst.width == controller.windowWillUseStandardFrame(window, defaultFrame: window.screen?.visibleFrame ?? .infinite).width)
		#expect(zoomedFirst.width > first.width && zoomedFirst.height == first.height && zoomedFirst.maxY == first.maxY, "\(zoomedFirst)")
		#expect(window.isZoomed)

		controller.model.setFile(try folders.writeSource(decomposed("한글 보고서.txt")))
		await controller.model.previewSettled()
		await settle()
		let zoomedDetail = window.frame
		#expect(zoomedDetail == fittedKeepingTheTop(of: zoomedFirst, x: zoomedFirst.minX, width: zoomedFirst.width), "\(zoomedDetail)")
		#expect(zoomedDetail.height > zoomedFirst.height + 250)

		window.zoom(nil)
		await settle()
		let back = window.frame
		#expect(back.width == first.width && back.minX == first.minX, "\(back)")
		#expect(back == fittedKeepingTheTop(of: zoomedDetail, x: first.minX, width: first.width), "\(back), zoomed \(zoomedDetail)")
		if let visible = window.screen?.visibleFrame {
			#expect(back.minY >= visible.minY && back.maxY <= visible.maxY, "inside the screen")
		}
		window.close()
	}

	/// The Dock is shown or made bigger, or the resolution changes: the screen's visible area is another one, and the
	/// window is fitted to it again. (Its height is held, so the user could not make it fit.)
	@Test func theWindowIsFittedAgainWhenTheScreensVisibleAreaChanges() async throws {
		let controller = await makeWindow()
		let window = controller.window
		controller.model.setFile(try folders.writeSource("report.txt"))
		await controller.model.previewSettled()
		await settleWindow(window)
		guard let visible = window.screen?.visibleFrame else {
			print("skipped: the window is on no screen here")
			return
		}

		// What a smaller visible area leaves behind: the window's lower edge hangs out of it.
		let fittedBefore = window.frame
		window.setFrameOrigin(NSPoint(x: fittedBefore.minX, y: visible.minY - 120))
		await settleWindow(window)
		let hanging = window.frame
		try #require(hanging.minY < visible.minY, "\(hanging)")
		try #require(window.screen?.visibleFrame == visible)

		NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
		await settleWindow(window)
		#expect(window.frame == fitted(hanging, controller), "\(window.frame)")
		#expect(window.frame.minY >= visible.minY && window.frame.maxY <= visible.maxY)
		#expect(window.frame.size == fittedBefore.size)
	}

	/// Tab goes to the controls of the screen that is shown now, also after the screens were switched: the drop zone,
	/// then (with a file selected and "이름 바꾸기") the name field, then the drop zone again.
	@Test func tabReachesTheControlsOfTheScreenThatIsShown() async throws {
		let controller = await makeWindow()
		let window = controller.window
		let content = try #require(window.contentView)
		#expect(window.autorecalculatesKeyViewLoop)
		// AppKit works the Tab order out when the window is first put on the screen.
		window.recalculateKeyViewLoop()
		/// Tab, pressed while no control has the keyboard focus.
		func pressTab() -> NSResponder? {
			window.makeFirstResponder(nil)
			window.selectKeyView(following: content)
			return window.firstResponder
		}

		#expect(pressTab() is DropTargetView, "first screen")

		controller.model.setFile(try folders.writeSource(decomposed("한글 보고서.txt")))
		await controller.model.previewSettled()
		controller.model.changeNameMode(.rename)
		await settleWindow(window)
		let field = try #require(findView(NameTextField.self, in: window.contentView))
		#expect(pressTab() is NameFieldEditor, "selected file: the name field")
		#expect(field.currentEditor() != nil)

		controller.model.clearFile()
		await settleWindow(window)
		#expect(pressTab() is DropTargetView, "first screen again")
	}

	/// What the old app's status line did as a live region: every message that appears is said to VoiceOver, once.
	@Test func everyStatusMessageIsAnnounced() async throws {
		guard getuid() != 0 else {
			print("skipped: root may write to a folder without write permission")
			return
		}

		let shell = FakeShell()
		let model = AppModel(conversions: ConversionTracker())
		let controller = await makeWindow(model)
		#expect(model.shell === controller, "the window answers the model's requests")
		model.shell = shell
		var announced: [String] = []
		controller.announce = { announced.append($0) }

		let first = try folders.writeSource(decomposed("한글 보고서.txt"))
		model.handleDrop(paths: [first, try folders.writeSource("second.txt")])
		#expect(announced == [Wording.onlyOneFile])
		await model.previewSettled()

		// A copy that fails, then one that succeeds.
		let locked = folders.work + "/잠긴 폴더"
		mkdir(locked, 0o555)
		shell.directoryAnswer = locked
		model.selectOutputDirectory()
		await model.previewSettled()
		model.convertFile()
		#expect(announced == [Wording.onlyOneFile, Wording.converting])
		await model.conversionSettled()
		#expect(announced == [Wording.onlyOneFile, Wording.converting, Wording.notWritable])

		shell.directoryAnswer = folders.output
		model.selectOutputDirectory()
		await model.previewSettled()
		#expect(announced.count == 3, "a status that goes away is not announced")
		model.convertFile()
		await model.conversionSettled()
		#expect(announced == [Wording.onlyOneFile, Wording.converting, Wording.notWritable, Wording.converting, Wording.done])

		// Going back says nothing.
		model.clearFile()
		#expect(announced.count == 5)
	}

	@Test func thePanelsAskForOneFileAndForAFolder() {
		_ = NSApplication.shared

		let file = MainWindowController.filePanel()
		#expect(file.message == "정리할 파일을 선택하세요")
		#expect(file.canChooseFiles)
		#expect(!file.canChooseDirectories)
		#expect(!file.allowsMultipleSelection)
		#expect(!file.canCreateDirectories)
		#expect(file.treatsFilePackagesAsDirectories, "a file inside an app or another package can be chosen")

		let folder = MainWindowController.folderPanel(startingAt: folders.output)
		#expect(folder.message == "사본을 저장할 폴더를 선택하세요")
		#expect(!folder.canChooseFiles)
		#expect(folder.canChooseDirectories)
		#expect(!folder.allowsMultipleSelection)
		#expect(folder.canCreateDirectories, "a new folder can be made for the copy")
		#expect(folder.directoryURL?.path == folders.output, "the panel starts at the current folder")

		// Without a folder to start at, the panel is still the folder panel.
		let anywhere = MainWindowController.folderPanel(startingAt: nil)
		#expect(anywhere.canChooseDirectories && !anywhere.canChooseFiles)
		#expect(anywhere.directoryURL?.path != folders.output)
	}
}

/// The app delegate's answers, asked directly. No window is shown and the test process is not told to quit.
@MainActor
@Suite struct AppDelegateTests {
	private final class Recorder {
		var shown: [MainWindowController] = []
		var replies: [Bool] = []
	}

	private func makeDelegate(_ recorder: Recorder, conversions: ConversionTracker = ConversionTracker()) -> AppDelegate {
		AppDelegate(conversions: conversions, showWindow: { recorder.shown.append($0) }, replyToTerminate: { recorder.replies.append($0) })
	}

	@Test func closingTheLastWindowDoesNotQuit() {
		let delegate = makeDelegate(Recorder())
		#expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
		#expect(delegate.applicationSupportsSecureRestorableState(NSApplication.shared))
	}

	@Test func quittingWaitsForACopyThatIsBeingWritten() {
		let recorder = Recorder()
		let conversions = ConversionTracker()
		let delegate = makeDelegate(recorder, conversions: conversions)
		let application = NSApplication.shared

		// Nothing is being copied: quit at once.
		#expect(delegate.applicationShouldTerminate(application) == .terminateNow)
		#expect(conversions.onIdle == nil)

		// Two copies are running: later, when the last one has finished, and only then.
		conversions.begin()
		conversions.begin()
		#expect(delegate.applicationShouldTerminate(application) == .terminateLater)
		#expect(recorder.replies.isEmpty)
		conversions.end()
		#expect(recorder.replies.isEmpty)
		conversions.end()
		#expect(recorder.replies == [true])

		#expect(delegate.applicationShouldTerminate(application) == .terminateNow)
		#expect(recorder.replies == [true])
	}

	@Test func openingTheAppAgainOpensAWindowOnlyWhenThereIsNone() throws {
		let recorder = Recorder()
		let delegate = makeDelegate(recorder)
		let application = NSApplication.shared
		#expect(delegate.windowController == nil)

		// No window (it was closed, or none was opened yet): a new one, and AppKit has nothing more to do.
		#expect(!delegate.applicationShouldHandleReopen(application, hasVisibleWindows: false))
		#expect(recorder.shown.count == 1)
		let first = try #require(recorder.shown.first)
		#expect(delegate.windowController === first)

		// The window exists, on the screen or in the Dock: AppKit brings it back, no second window.
		#expect(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: true))
		#expect(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: false))
		#expect(recorder.shown.count == 1)
		#expect(delegate.windowController === first)

		// Closed: the app lets go of it, and the next window starts from the first screen with a model of its own.
		first.window.close()
		#expect(delegate.windowController == nil)
		#expect(!delegate.applicationShouldHandleReopen(application, hasVisibleWindows: false))
		#expect(recorder.shown.count == 2)
		#expect(delegate.windowController === recorder.shown[1])
		#expect(recorder.shown[1] !== first && recorder.shown[1].model !== first.model)
		#expect(recorder.shown[1].model.sourcePath == nil)
		recorder.shown[1].window.close()
	}
}
