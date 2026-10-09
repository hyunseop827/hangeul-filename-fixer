// The AppKit pieces of the screen, driven directly: the drop zone as a button and as a drag destination, and the
// views laid out without a window on the screen.
import AppKit
import SwiftUI
import Testing
import HangeulFilenameFixerCore
@testable import HangeulFilenameFixer

@MainActor
@Suite struct DropTargetTests {
	let folders = TestFolders()

	/// What AppKit hands a drag destination, reduced to the pasteboard (the only part the drop zone reads).
	private final class FakeDrag: NSObject, NSDraggingInfo {
		let pasteboard: NSPasteboard

		init(pasteboard: NSPasteboard) {
			self.pasteboard = pasteboard
		}

		var draggingPasteboard: NSPasteboard { pasteboard }
		var draggingDestinationWindow: NSWindow? { nil }
		var draggingSourceOperationMask: NSDragOperation { [.copy, .generic] }
		var draggingLocation: NSPoint { .zero }
		var draggedImageLocation: NSPoint { .zero }
		var draggedImage: NSImage? { nil }
		var draggingSource: Any? { nil }
		var draggingSequenceNumber: Int { 1 }
		var draggingFormation: NSDraggingFormation = .default
		var animatesToDestination = false
		var numberOfValidItemsForDrop = 0
		var springLoadingHighlight: NSSpringLoadingHighlight { .none }

		func slideDraggedImage(to screenPoint: NSPoint) {}
		func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
		func resetSpringLoading() {}
	}

	private func keyDown(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
		try #require(NSEvent.keyEvent(
			with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
			characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
		))
	}

	@Test func theDropZoneIsAButtonForAssistiveAppsAndTheKeyboard() throws {
		let view = DropTargetView(frame: NSRect(x: 0, y: 0, width: 400, height: 210))
		view.label = "파일을 여기에 놓기"
		view.help = "또는 클릭해서 선택하세요. 한 번에 파일 하나만 처리합니다."
		var presses = 0
		view.onPress = { presses += 1 }

		#expect(view.isAccessibilityElement())
		#expect(view.accessibilityRole() == .button)
		#expect(view.accessibilityLabel() == "파일을 여기에 놓기")
		#expect(view.accessibilityHelp() == "또는 클릭해서 선택하세요. 한 번에 파일 하나만 처리합니다.")
		#expect(view.accessibilityIdentifier() == "dropZone")
		#expect(view.isAccessibilityEnabled())
		#expect(view.accessibilityPerformPress())
		#expect(presses == 1)

		// Reachable with Tab; Space, Return and Enter press it; other keys and key equivalents do not.
		#expect(view.acceptsFirstResponder)
		for keyCode in [49, 36, 76] as [UInt16] {
			view.keyDown(with: try keyDown(keyCode))
		}
		#expect(presses == 4)
		view.keyDown(with: try keyDown(0))                          // "a"
		view.keyDown(with: try keyDown(49, modifiers: .command))    // ⌘Space is not ours
		#expect(presses == 4)
	}

	@Test func aDragHighlightsAndADropDeliversThePathsInOrder() async throws {
		let first = try folders.writeSource(decomposed("첫째.txt"))
		let second = try folders.writeSource("second.txt")
		let pasteboard = NSPasteboard.withUniqueName()
		defer { pasteboard.releaseGlobally() }
		pasteboard.clearContents()
		#expect(pasteboard.writeObjects([URL(fileURLWithPath: first) as NSURL, URL(fileURLWithPath: second) as NSURL]))
		let drag = FakeDrag(pasteboard: pasteboard)

		let model = AppModel(conversions: ConversionTracker())
		let view = DropTargetView(frame: NSRect(x: 0, y: 0, width: 400, height: 210))
		view.onDraggingChange = { model.setDragging($0) }
		view.onDrop = { model.handleDrop(paths: $0) }

		// Only files are accepted, and they are copied (the pointer shows the green plus).
		#expect(view.registeredDraggedTypes == [.fileURL])

		#expect(view.draggingEntered(drag) == .copy)
		#expect(model.isDragging)
		#expect(view.draggingUpdated(drag) == .copy)
		view.draggingExited(drag)
		#expect(!model.isDragging)

		#expect(view.draggingEntered(drag) == .copy)
		#expect(view.performDragOperation(drag))
		// The selection happens right after the drag has ended.
		for _ in 0..<200 where model.sourcePath == nil {
			await Task.yield()
			try await Task.sleep(nanoseconds: 1_000_000)
		}
		#expect(!model.isDragging)
		#expect(model.sourcePath == first)
		#expect(model.status?.message == Wording.onlyOneFile)
		await model.previewSettled()
		#expect(Exact(model.sourceName) == Exact(decomposed("첫째.txt")))

		// A drag without files is refused.
		pasteboard.clearContents()
		pasteboard.setString("그냥 글자", forType: .string)
		#expect(!view.performDragOperation(FakeDrag(pasteboard: pasteboard)))
	}
}

/// Stands in for Sparkle's controller: the target of "업데이트 확인…", which also answers whether the item is enabled
/// (Sparkle says no while a check is running).
@MainActor
private final class FakeUpdaterController: NSObject, NSMenuItemValidation {
	var canCheck = true
	var checks = 0

	@objc func checkForUpdates(_ sender: Any?) {
		checks += 1
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		canCheck
	}
}

/// The menu bar as it is built in code: Korean titles, the standard key equivalents and actions.
@MainActor
@Suite struct MainMenuTests {
	private func rows(_ menu: NSMenu?) -> [String] {
		(menu?.items ?? []).map { item in
			if item.isSeparatorItem {
				return "-"
			}

			let flags = item.keyEquivalentModifierMask
			let keys = item.keyEquivalent.isEmpty ? "" : (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
				+ (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + item.keyEquivalent
			// (An item with a submenu has AppKit's own action for opening it.)
			return [item.title, keys, item.submenu != nil ? "▸" : item.action.map { NSStringFromSelector($0) } ?? ""].joined(separator: " | ")
		}
	}

	@Test func theMenuBarIsKoreanWithTheStandardKeyEquivalents() throws {
		_ = NSApplication.shared
		let updater = FakeUpdaterController()
		let menuBar = MainMenu.make(updateCheck: UpdateCheck(target: updater, action: #selector(FakeUpdaterController.checkForUpdates(_:))))
		let menus = menuBar.items.map(\.submenu)

		// No "보기" menu: the window has no full screen, and nothing else belongs there.
		#expect(menus.map { $0?.title } == ["한글 파일명 정리기", "파일", "편집", "윈도우"])
		#expect(rows(menus[0]) == [
			"한글 파일명 정리기에 관하여 |  | orderFrontStandardAboutPanel:",
			"업데이트 확인… |  | checkForUpdates:",
			"-",
			"서비스 |  | ▸",
			"-",
			"한글 파일명 정리기 가리기 | ⌘h | hide:",
			"기타 가리기 | ⌥⌘h | hideOtherApplications:",
			"모두 보기 |  | unhideAllApplications:",
			"-",
			"한글 파일명 정리기 종료 | ⌘q | terminate:"
		])
		#expect(rows(menus[1]) == ["창 닫기 | ⌘w | performClose:"])
		// ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z reach the name field through these items.
		#expect(rows(menus[2]) == [
			"실행 취소 | ⌘z | undo:",
			"실행 복귀 | ⇧⌘z | redo:",
			"-",
			"잘라내기 | ⌘x | cut:",
			"복사하기 | ⌘c | copy:",
			"붙여넣기 | ⌘v | paste:",
			"모두 선택 | ⌘a | selectAll:"
		])
		// AppKit may add its own items (the window list, tiling) to the menu it is told is the Window menu.
		let windowRows = rows(menus[3]).filter { row in
			["performMiniaturize:", "performZoom:", "arrangeInFront:"].contains { row.hasSuffix("| " + $0) }
		}
		#expect(windowRows == ["최소화 | ⌘m | performMiniaturize:", "확대/축소 |  | performZoom:", "앞으로 모두 가져오기 |  | arrangeInFront:"])

		// No target: every item goes to the first responder (the name field's editor, the window, the app). All but
		// "업데이트 확인…", which goes to the updater.
		let update = try #require(menus[0]?.items[1])
		#expect(update.target === updater)
		for menu in menus {
			for item in menu?.items ?? [] where !item.isSeparatorItem && item.submenu == nil && item !== update {
				#expect(item.target == nil, "\(item.title)")
			}
		}
		#expect(NSApp.servicesMenu === menus[0]?.items[3].submenu)
		#expect(NSApp.windowsMenu === menus[3])

		// Nothing the app builds asks for full screen.
		for menu in menus {
			#expect(menu?.items.contains { $0.action == #selector(NSWindow.toggleFullScreen(_:)) } == false)
		}
	}
}

/// 앱 메뉴 > "업데이트 확인…": always there, right under the About item.
@MainActor
@Suite struct UpdateMenuItemTests {
	private func updateItem(in menuBar: NSMenu) throws -> (menu: NSMenu, item: NSMenuItem) {
		let menu = try #require(menuBar.items.first?.submenu)
		#expect(menu.items.first?.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
		let item = try #require(menu.items.dropFirst().first)
		#expect(Exact(item.title) == Exact("업데이트 확인…"))
		#expect(item.keyEquivalent.isEmpty)
		#expect(menu.items.dropFirst(2).first?.isSeparatorItem == true)
		return (menu, item)
	}

	/// With an updater the item is the updater's: its target answers whether a check can start now, so the item is
	/// disabled while one is running, and choosing it starts a check.
	@Test func withAnUpdaterTheItemFollowsItsTarget() throws {
		_ = NSApplication.shared
		let updater = FakeUpdaterController()
		let (menu, item) = try updateItem(in: MainMenu.make(updateCheck: UpdateCheck(target: updater, action: #selector(FakeUpdaterController.checkForUpdates(_:)))))
		#expect(item.target === updater)
		#expect(item.action == #selector(FakeUpdaterController.checkForUpdates(_:)))
		#expect(menu.autoenablesItems, "AppKit asks the target each time the menu opens")

		menu.update()
		#expect(item.isEnabled)
		menu.performActionForItem(at: 1)
		#expect(updater.checks == 1)

		// A check is running: disabled, and choosing it (by a key equivalent, by automation) does nothing.
		updater.canCheck = false
		menu.update()
		#expect(!item.isEnabled)
		menu.performActionForItem(at: 1)
		#expect(updater.checks == 1)

		updater.canCheck = true
		menu.update()
		#expect(item.isEnabled)
	}

	/// Without an updater (the key for updates is not set yet, or the app is not run from its bundle) the item is
	/// there and disabled: it has no action, so nothing in the app could answer for it.
	@Test func withoutAnUpdaterTheItemIsDisabled() throws {
		_ = NSApplication.shared
		let (menu, item) = try updateItem(in: MainMenu.make(updateCheck: nil))
		#expect(item.target == nil)
		#expect(item.action == nil)

		menu.update()
		#expect(!item.isEnabled)
		// The items around it are not affected.
		#expect(menu.items.last?.action == #selector(NSApplication.terminate(_:)))
	}

	/// What the app hands to the menu is the updater's own answer: nothing under `swift test`, where there is no app
	/// bundle and so no feed and no key.
	@Test func theAppWiresTheItemToItsUpdater() throws {
		_ = NSApplication.shared
		#expect(AppUpdater.shared.check == nil)
		let (menu, item) = try updateItem(in: MainMenu.make(updateCheck: AppUpdater.shared.check))
		menu.update()
		#expect(!item.isEnabled)

		let delegate = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/HangeulFilenameFixer/HangeulFilenameFixerApp.swift"), encoding: .utf8)
		#expect(delegate.contains("NSApp.mainMenu = MainMenu.make(updateCheck: AppUpdater.shared.check)"))
	}
}

/// The "업데이트 확인" link under the card: there on both screens, the updater's (its state and its check), and disabled
/// without one, like the menu item. Read and pressed the way an assistive app does (ScreenReader): the link is a
/// SwiftUI button and has no AppKit view of its own.
@MainActor
@Suite struct UpdateLinkTests {
	let folders = TestFolders()

	/// A feed and a key of the right shape, so the updater is "started" with the stand-in (nothing of Sparkle's).
	private let configuration = UpdaterConfiguration(feedURL: "https://127.0.0.1/appcast.xml", publicKey: Data(repeating: 7, count: 32).base64EncodedString())

	private func hostedScreen(_ model: AppModel, updater: AppUpdater) -> (hosting: NSHostingView<RootView>, window: NSWindow) {
		let hosting = NSHostingView(rootView: RootView(model: model, updater: updater))
		hosting.frame = NSRect(x: 0, y: 0, width: 470, height: 900)
		let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: true)
		window.isReleasedWhenClosed = false
		window.contentView = hosting
		settleScreen(hosting)
		return (hosting, window)
	}

	@Test(.enabled("SwiftUI describes its views to assistive apps only; that is not possible here") { await ScreenReader.isAvailable })
	func theLinkIsTheUpdatersOnBothScreens() async throws {
		_ = NSApplication.shared
		let target = FakeUpdaterController()
		let check = UpdateCheck(target: target, action: #selector(FakeUpdaterController.checkForUpdates(_:)))
		let updater = AppUpdater(configuration: configuration, start: { check })
		let model = AppModel(conversions: ConversionTracker())
		let (hosting, window) = hostedScreen(model, updater: updater)
		_ = window

		// The first screen: after the card's two elements, a button named like the menu item, without the ellipsis.
		var reader = ScreenReader(hosting)
		#expect(reader.identifiers == ["dropZone", "footer", "checkForUpdates"])
		let link = try #require(reader["checkForUpdates"])
		#expect(link.role == NSAccessibility.Role.button.rawValue)
		#expect(Exact(link.label) == Exact("업데이트 확인"))
		#expect(link.isEnabled)
		// Under the card (AppKit's y points up), ending at the card's right edge: the drop zone stands 16 pt inside the
		// card's 1 pt border.
		let footer = try #require(reader["footer"])
		let dropZone = try #require(reader["dropZone"])
		#expect(link.frame.maxY <= footer.frame.minY, "\(link.frame) under \(footer.frame)")
		#expect(link.frame.maxX == dropZone.frame.maxX + 17, "\(link.frame) at the right edge of the card around \(dropZone.frame)")
		#expect(link.frame.height == Theme.smallLine)
		#expect(findViews(PointerAreaView.self, in: hosting).map(\.cursor) == [.pointingHand], "the hand over the link")
		link.press()
		#expect(target.checks == 1)

		// The screen for a selected file: the same link, after everything in the card.
		model.setFile(try folders.writeSource(decomposed("한글 보고서.txt")))
		await model.previewSettled()
		settleScreen(hosting)
		reader = ScreenReader(hosting)
		#expect(reader.identifiers.first == "backButton" && reader.identifiers.last == "checkForUpdates")
		#expect(reader["checkForUpdates"]?.isEnabled == true)
		reader["checkForUpdates"]?.press()
		#expect(target.checks == 2)
		model.clearFile()
		settleScreen(hosting)
		#expect(ScreenReader(hosting).identifiers == ["dropZone", "footer", "checkForUpdates"])
	}

	/// Without an updater (no key for updates, or the app is not run from its bundle) the link is there and disabled,
	/// and a press that arrives all the same (by automation) sends nothing.
	@Test(.enabled("SwiftUI describes its views to assistive apps only; that is not possible here") { await ScreenReader.isAvailable })
	func withoutAnUpdaterTheLinkIsDisabled() throws {
		_ = NSApplication.shared
		let target = FakeUpdaterController()
		for updater in [
			AppUpdater(configuration: UpdaterConfiguration(feedURL: nil, publicKey: nil), start: { UpdateCheck(target: target, action: #selector(FakeUpdaterController.checkForUpdates(_:))) }),
			AppUpdater(configuration: configuration, start: { nil }),
			AppUpdater.shared
		] {
			let (hosting, window) = hostedScreen(AppModel(conversions: ConversionTracker()), updater: updater)
			_ = window
			let reader = ScreenReader(hosting)
			let link = try #require(reader["checkForUpdates"])
			#expect(Exact(link.label) == Exact("업데이트 확인"))
			#expect(!link.isEnabled)
			#expect(findViews(PointerAreaView.self, in: hosting).map(\.cursor) == [.operationNotAllowed])
			link.press()
		}
		#expect(target.checks == 0)
	}
}

/// The observer that removes itself from the notification center.
@Suite struct NotificationObservationTests {
	@Test func theHandlerIsCalledOnlyWhileTheObservationLives() {
		let center = NotificationCenter()
		let name = Notification.Name("HangeulFilenameFixerTests.observation")
		let sender = NSObject()
		let calls = Counter()

		var observation: NotificationObservation? = NotificationObservation(name, object: sender, center: center) { _ in calls.increment() }
		center.post(name: name, object: sender)
		#expect(calls.count == 1)
		// Only this sender's notifications.
		center.post(name: name, object: NSObject())
		center.post(name: Notification.Name("HangeulFilenameFixerTests.other"), object: sender)
		#expect(calls.count == 1)
		center.post(name: name, object: sender)
		#expect(calls.count == 2)

		#expect(observation != nil)
		observation = nil
		center.post(name: name, object: sender)
		#expect(calls.count == 2, "removed from the center when it went away")
	}
}

/// The name field with its editor, in a window that is never shown.
@MainActor
@Suite struct NameFieldTests {
	private final class Typed {
		var texts: [String] = []
		var focus: [Bool] = []
	}

	private func makeField(_ typed: Typed) -> (field: NameTextField, coordinator: NameField.Coordinator, window: NSWindow) {
		let representable = NameField(
			text: "", placeholder: "확장자명을 제외하고 입력해주세요", isEnabled: true, handle: NameFieldHandle(),
			onChange: { typed.texts.append($0) }, onFocusChange: { typed.focus.append($0) }
		)
		let coordinator = NameField.Coordinator(representable)
		let field = NameTextField.make(placeholder: representable.placeholder)
		field.delegate = coordinator
		field.onTextChange = { [weak coordinator] in coordinator?.parent.onChange($0) }
		field.onFocusChange = { typed.focus.append($0) }
		field.frame = NSRect(x: 10, y: 10, width: 300, height: 34)
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60), styleMask: [.titled], backing: .buffered, defer: true)
		window.isReleasedWhenClosed = false
		window.contentView?.addSubview(field)
		return (field, coordinator, window)
	}

	@Test func typingReachesTheModelExactlyAsTyped() throws {
		let typed = Typed()
		let (field, coordinator, window) = makeField(typed)
		_ = coordinator

		#expect(field.placeholderAttributedString?.string == "확장자명을 제외하고 입력해주세요")
		#expect(field.accessibilityIdentifier() == "nameField")
		#expect(field.accessibilityLabel() == "새 파일명")
		#expect(window.makeFirstResponder(field))
		#expect(typed.focus == [true])
		let editor = try #require(field.currentEditor() as? NSTextView)

		// Nothing that would change what was typed.
		#expect(!editor.isContinuousSpellCheckingEnabled)
		#expect(!editor.isGrammarCheckingEnabled)
		#expect(!editor.isAutomaticSpellingCorrectionEnabled)
		#expect(!editor.isAutomaticTextReplacementEnabled)
		#expect(!editor.isAutomaticQuoteSubstitutionEnabled)
		#expect(!editor.isAutomaticDashSubstitutionEnabled)
		#expect(!editor.isAutomaticTextCompletionEnabled)
		#expect(!editor.isAutomaticLinkDetectionEnabled)
		#expect(!editor.isAutomaticDataDetectionEnabled)
		#expect(!editor.smartInsertDeleteEnabled)
		// What newer systems offer on their own: grey inline completions, a result after "=", Writing Tools.
		if #available(macOS 14.0, *) {
			#expect(editor.inlinePredictionType == .no)
		}
		if #available(macOS 15.0, *) {
			#expect(editor.mathExpressionCompletionType == .no)
			#expect(editor.writingToolsBehavior == .none)
		}

		editor.insertText("보고서 \"최종\" -- 1", replacementRange: editor.selectedRange())
		#expect(typed.texts.last.map { Exact($0) } == Exact("보고서 \"최종\" -- 1"), "quotes and dashes stay as typed")
		#expect(Exact(field.stringValue) == Exact("보고서 \"최종\" -- 1"))

		// Korean input: the syllable that is still being composed is reported as it grows, like any other change. (A
		// press on "NFC 사본 만들기" does not end the composition; the copy must still get the whole name.)
		editor.selectAll(nil)
		editor.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
		#expect(editor.hasMarkedText())
		#expect(typed.texts.last.map { Exact($0) } == Exact("ㅎ"))
		editor.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.markedRange())
		#expect(typed.texts.last.map { Exact($0) } == Exact("하"))
		editor.insertText("한", replacementRange: editor.markedRange())
		#expect(!editor.hasMarkedText())
		#expect(typed.texts.last.map { Exact($0) } == Exact("한"))
		#expect(Exact(field.stringValue) == Exact("한"))

		// Decomposed text stays decomposed on its way to the model (the Core composes it).
		editor.selectAll(nil)
		editor.insertText(decomposed("한글"), replacementRange: editor.selectedRange())
		#expect(typed.texts.last.map { Exact($0) } == Exact(decomposed("한글")))

		// A file name is one line: no line break reaches the model. (AppKit's one-line editor turns each into a space.)
		editor.selectAll(nil)
		editor.insertText("줄\n바꿈\r\n이름", replacementRange: editor.selectedRange())
		let oneLine = try #require(typed.texts.last)
		#expect(!oneLine.unicodeScalars.contains { $0 == "\n" || $0 == "\r" }, "\(Exact(oneLine))")
		#expect(Exact(field.stringValue) == Exact(oneLine))

		// Return and Escape are swallowed: the text stays, the field keeps the cursor.
		let before = field.stringValue
		#expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
		#expect(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
		#expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertTab(_:))))
		#expect(!coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
		#expect(Exact(field.stringValue) == Exact(before))

		// Every change was reported once, and only real changes.
		let reported = typed.texts.count
		field.reportIfChanged(field.stringValue)
		#expect(typed.texts.count == reported)

		#expect(window.makeFirstResponder(nil))
		#expect(typed.focus == [true, false])
		#expect(typed.texts.count == reported, "leaving the field reports nothing new")

		// A text put into the field from outside (the model's) is not reported back.
		field.show("모델이 넣은 이름")
		#expect(Exact(field.stringValue) == Exact("모델이 넣은 이름"))
		#expect(typed.texts.count == reported)
		field.show(decomposed("모델이 넣은 이름"))
		#expect(Exact(field.stringValue) == Exact(decomposed("모델이 넣은 이름")), "respelled, although `==` calls the two equal")
		#expect(typed.texts.count == reported)
	}

	private func rightClick(in window: NSWindow) throws -> NSEvent {
		try #require(NSEvent.mouseEvent(
			with: .rightMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
			context: nil, eventNumber: 0, clickCount: 1, pressure: 1
		))
	}

	@Test func theContextMenuIsTheShortKoreanOne() throws {
		let typed = Typed()
		let (field, coordinator, window) = makeField(typed)
		_ = coordinator
		#expect(window.makeFirstResponder(field))
		let editor = try #require(field.currentEditor() as? NSTextView)
		let click = try rightClick(in: window)

		// While editing, the editor asks its delegate (the field) for the menu.
		#expect(editor.delegate === field)
		for menu in [editor.menu(for: click), field.menu(for: click)] {
			let items = try #require(menu).items
			#expect(items.map(\.title) == ["잘라내기", "복사하기", "붙여넣기", "", "모두 선택"])
			#expect(items.map(\.isSeparatorItem) == [false, false, false, true, false])
			#expect(items.compactMap(\.action) == [#selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:))])
		}

		field.isEnabled = false
		#expect(field.menu(for: click) == nil)
	}

	/// The menu asked of a field that is not being edited (VoiceOver's "show menu"): the field takes the cursor first,
	/// as for any click, and the items act on its editor. Without an editor all four would be switched off.
	@Test func theMenuOfAFieldThatIsNotBeingEditedStartsTheEditing() throws {
		let typed = Typed()
		let (field, coordinator, window) = makeField(typed)
		_ = coordinator
		field.show("보고서")
		#expect(field.currentEditor() == nil)
		#expect(typed.focus.isEmpty)

		let menu = try #require(field.menu(for: try rightClick(in: window)))

		let editor = try #require(field.currentEditor() as? NSTextView, "the field is being edited now")
		#expect(window.firstResponder === editor)
		#expect(typed.focus == [true], "and looks focused")
		let items = menu.items.filter { !$0.isSeparatorItem }
		#expect(items.map(\.title) == ["잘라내기", "복사하기", "붙여넣기", "모두 선택"])
		for item in items {
			#expect(item.target === editor, "\(item.title)")
		}
		// The editor says which items apply: with the whole name selected, all that need a selection do.
		#expect(editor.selectedRange() == NSRange(location: 0, length: 3))
		#expect(editor.validateUserInterfaceItem(items[0]) && editor.validateUserInterfaceItem(items[1]) && editor.validateUserInterfaceItem(items[3]))
		editor.setSelectedRange(NSRange(location: 3, length: 0))
		#expect(!editor.validateUserInterfaceItem(items[0]) && !editor.validateUserInterfaceItem(items[1]), "nothing to cut or copy")
		#expect(editor.validateUserInterfaceItem(items[3]))

		// Asked again while editing: the same editor, and the cursor stays where it is.
		let again = try #require(field.menu(for: try rightClick(in: window)))
		#expect(again.items.first?.target === editor)
		#expect(editor.selectedRange() == NSRange(location: 3, length: 0))
		#expect(typed.focus == [true])
		#expect(typed.texts.isEmpty, "asking for the menu changes no text")
	}

	/// SwiftUI switches the field off itself when the mode goes back to "기존 이름 유지" or a copy starts, also in the
	/// middle of editing. The field then loses the cursor, and says so (once), so it does not keep looking focused.
	@Test func aFieldSwitchedOffWhileEditingGivesUpTheFocus() throws {
		let typed = Typed()
		let (field, coordinator, window) = makeField(typed)
		_ = coordinator
		#expect(window.makeFirstResponder(field))
		let editor = try #require(field.currentEditor() as? NSTextView)
		editor.insertText("이름", replacementRange: editor.selectedRange())
		#expect(typed.focus == [true])

		field.isEnabled = false

		#expect(typed.focus == [true, false])
		#expect(field.currentEditor() == nil)
		#expect(window.firstResponder !== editor)
		#expect(typed.texts.map { Exact($0) } == [Exact("이름")], "nothing new is reported")

		// Switched on again it is not focused; the next click starts over.
		field.isEnabled = true
		#expect(typed.focus == [true, false])
		#expect(window.makeFirstResponder(field))
		#expect(typed.focus == [true, false, true])
		#expect(window.makeFirstResponder(nil))
		#expect(typed.focus == [true, false, true, false])

		// Switching off a field that is not being edited reports nothing.
		field.isEnabled = false
		#expect(typed.focus == [true, false, true, false])
	}

	/// AppKit does not end the editing when a window is closed, so the field is never told to stop watching its
	/// editor. What watches goes away with the field, and with it the observer in the notification center.
	@Test func aWindowClosedWhileEditingLeavesNoObserverBehind() {
		final class Weak<Object: AnyObject> {
			weak var object: Object?
		}
		let field = Weak<NameTextField>()
		let observation = Weak<NotificationObservation>()

		autoreleasepool {
			let typed = Typed()
			let made = makeField(typed)
			#expect(made.field.editorObservation == nil, "nothing is watched before the field is edited")
			#expect(made.window.makeFirstResponder(made.field))
			field.object = made.field
			observation.object = made.field.editorObservation
			#expect(observation.object != nil, "the editor is watched while the field is edited")

			made.window.close()
			#expect(made.field.currentEditor() != nil, "closing the window does not end the editing")
			#expect(observation.object != nil, "and so the editor is still watched")
			#expect(typed.focus == [true])
		}
		// AppKit lets go of a closed window a little later (a few turns of the run loop; waited for up to 5 seconds).
		for _ in 0..<50 where field.object != nil {
			autoreleasepool { settleScreen(nil) }
		}

		#expect(field.object == nil, "the field is gone")
		#expect(observation.object == nil, "and what watched its editor with it")
	}

	/// Leaving the field the usual way stops the watching at once.
	@Test func leavingTheFieldStopsWatchingItsEditor() throws {
		let typed = Typed()
		let (field, coordinator, window) = makeField(typed)
		_ = coordinator
		#expect(window.makeFirstResponder(field))
		#expect(field.editorObservation != nil)
		#expect(window.makeFirstResponder(nil))
		#expect(field.editorObservation == nil)

		// Switched off while it is being edited.
		#expect(window.makeFirstResponder(field))
		#expect(field.editorObservation != nil)
		field.isEnabled = false
		#expect(field.editorObservation == nil)
	}

	/// Only the drop zone of the first screen takes files. The name field's editor takes dragged text, and nothing
	/// else: the window's shared editor would type a dropped file's whole path into the field.
	@Test func theNameFieldTakesNoDroppedFiles() throws {
		let typed = Typed()
		let (field, coordinator, window) = makeField(typed)
		_ = coordinator
		#expect(window.makeFirstResponder(field))
		let editor = try #require(field.currentEditor() as? NSTextView)

		#expect(editor is NameFieldEditor)
		#expect(editor.isFieldEditor)
		#expect(editor !== window.fieldEditor(false, for: nil), "not the window's shared editor")
		#expect(editor.acceptableDragTypes == [.string])
		let fileTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, NSPasteboard.PasteboardType("NSFilenamesPboardType")]
		#expect(editor.registeredDraggedTypes.filter { fileTypes.contains($0) }.isEmpty, "\(editor.registeredDraggedTypes.map(\.rawValue))")
		// The field itself takes no drags either.
		#expect(field.registeredDraggedTypes.isEmpty)

		// The same editor every time the field is edited, with the undo that ⌘Z needs.
		#expect(window.makeFirstResponder(nil))
		#expect(window.makeFirstResponder(field))
		#expect(field.currentEditor() === editor)
		#expect(editor.allowsUndo)
	}
}

/// The whole screen as SwiftUI builds it, in a window that is never shown: what is pressed, dropped and typed in the
/// real views arrives in the model, and what the model says arrives in the views.
@MainActor
@Suite struct ScreenWiringTests {
	let folders = TestFolders()

	private func hostedScreen(_ model: AppModel) -> (hosting: NSHostingView<RootView>, window: NSWindow) {
		let hosting = NSHostingView(rootView: RootView(model: model))
		hosting.frame = NSRect(x: 0, y: 0, width: 470, height: 768)
		let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: true)
		window.isReleasedWhenClosed = false
		window.contentView = hosting
		settle(hosting)
		return (hosting, window)
	}

	/// Lets SwiftUI bring its AppKit views up to date with the model.
	private func settle(_ view: NSView) {
		view.layoutSubtreeIfNeeded()
		RunLoop.current.run(until: Date().addingTimeInterval(0.1))
		view.layoutSubtreeIfNeeded()
	}

	private func find<V: NSView>(_ type: V.Type, in view: NSView) -> V? {
		if let match = view as? V {
			return match
		}
		for subview in view.subviews {
			if let match = find(type, in: subview) {
				return match
			}
		}
		return nil
	}

	@Test func theFirstScreenOpensThePanelAndTakesADrop() async throws {
		let shell = FakeShell()
		let model = AppModel(conversions: ConversionTracker())
		model.shell = shell
		let (hosting, window) = hostedScreen(model)
		_ = window

		let dropZone = try #require(find(DropTargetView.self, in: hosting))
		#expect(find(NameTextField.self, in: hosting) == nil)
		#expect(dropZone.accessibilityLabel() == "파일을 여기에 놓기")
		#expect(dropZone.frame.height >= 210)

		// Pressed: the model asks for the file panel (cancelled here).
		#expect(dropZone.accessibilityPerformPress())
		#expect(shell.fileRequests == 1)
		#expect(model.sourcePath == nil)

		// A drag over it and a drop on it.
		#expect(dropZone.onDraggingChange != nil && dropZone.onDrop != nil)
		dropZone.onDraggingChange?(true)
		#expect(model.isDragging)
		let path = try folders.writeSource(decomposed("한글 보고서.txt"))
		dropZone.onDrop?([path])
		#expect(!model.isDragging)
		#expect(Exact(model.sourcePath) == Exact(path))
		await model.previewSettled()

		// The screen for the selected file takes its place.
		settle(hosting)
		#expect(find(DropTargetView.self, in: hosting) == nil)
		let field = try #require(find(NameTextField.self, in: hosting))
		#expect(!field.isEnabled, "the name is kept at first")
		#expect(field.stringValue.isEmpty)
	}

	@Test func typingInTheNameFieldOfTheScreenReachesTheCopy() async throws {
		let model = AppModel(conversions: ConversionTracker())
		model.setFile(try folders.writeSource(decomposed("한글 보고서.txt"), "본문"))
		await model.previewSettled()
		model.changeNameMode(.rename)
		let (hosting, window) = hostedScreen(model)

		let field = try #require(find(NameTextField.self, in: hosting))
		#expect(field.isEnabled)
		#expect(field.frame.height >= 30, "the field fills its box, so a click anywhere in the box lands in it")
		#expect(window.makeFirstResponder(field))
		let editor = try #require(field.currentEditor() as? NSTextView)

		editor.insertText("제출용", replacementRange: editor.selectedRange())
		#expect(Exact(model.baseName) == Exact("제출용"))
		await model.previewSettled()
		#expect(Exact(model.resultName) == Exact("제출용.txt"))

		// The last syllable is still being composed when the copy is made: it belongs to the name all the same.
		editor.setMarkedText("본", selectedRange: NSRange(location: 1, length: 0), replacementRange: editor.selectedRange())
		#expect(editor.hasMarkedText())
		#expect(Exact(model.baseName) == Exact("제출용본"))
		settle(hosting)
		#expect(editor.hasMarkedText(), "an update of the screen leaves the composition alone")
		await model.previewSettled()
		model.convertFile()
		await model.conversionSettled()
		#expect(model.status?.tone == .success)
		#expect(try storedNameBytes(in: folders.source).contains(Array("제출용본.txt".utf8)))
		#expect(try readFile(folders.source + "/제출용본.txt") == "본문")

		// The model's side: keeping the name empties and switches off the field; renaming brings the text back.
		model.changeNameMode(.keep)
		settle(hosting)
		#expect(!field.isEnabled)
		#expect(field.stringValue.isEmpty)
		#expect(Exact(model.baseName) == Exact("제출용본"))
		model.changeNameMode(.rename)
		settle(hosting)
		#expect(field.isEnabled)
		#expect(Exact(field.stringValue) == Exact("제출용본"))
		#expect(Exact(model.baseName) == Exact("제출용본"), "showing the text again is not typing")
		#expect(model.createdPlan == nil)
	}
}

/// The screen laid out by SwiftUI without a window on the screen. With HANGEUL_FILENAME_FIXER_SNAPSHOTS set to a
/// folder, each state is also written there as a PNG to look at (never on CI).
@MainActor
@Suite struct LayoutTests {
	let folders = TestFolders()

	private func host(_ model: AppModel, width: CGFloat = 470, height: CGFloat = 768) -> NSHostingView<RootView> {
		let hosting = NSHostingView(rootView: RootView(model: model))
		hosting.appearance = NSAppearance(named: .aqua)
		hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
		hosting.layoutSubtreeIfNeeded()
		return hosting
	}

	private func snapshot(_ hosting: NSView, _ name: String) {
		guard let folder = ProcessInfo.processInfo.environment["HANGEUL_FILENAME_FIXER_SNAPSHOTS"], !folder.isEmpty else {
			return
		}

		// A window that is never shown gives the views a backing store to draw into.
		let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: true)
		window.appearance = NSAppearance(named: .aqua)
		window.contentView = hosting
		hosting.layoutSubtreeIfNeeded()
		RunLoop.current.run(until: Date().addingTimeInterval(0.3))
		guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
			return
		}

		hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
		try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
	}

	@Test func bothScreensLayOutWithoutAWindow() async throws {
		let model = AppModel(conversions: ConversionTracker())
		let first = host(model)
		#expect(first.frame.size == NSSize(width: 470, height: 768))
		snapshot(first, "first")

		model.setDragging(true)
		snapshot(host(model), "first-dragging")
		model.setDragging(false)

		model.setFile(try folders.writeSource(decomposed("홍길동_보고서_진짜최종_찐최종.docx")))
		await model.previewSettled()
		snapshot(host(model), "detail-keep")

		model.changeNameMode(.rename)
		snapshot(host(model), "detail-rename-empty")
		model.setBaseName("홍길동_보고서")
		await model.previewSettled()
		snapshot(host(model), "detail-rename")
		// A window that is narrower and lower than the card needs (a small screen): the card ends above the window's
		// edge and scrolls inside.
		snapshot(host(model, width: 440, height: 528), "detail-smallest")
		// A very wide window: the card stops growing at 900 pt and stays in the middle.
		snapshot(host(model, width: 1440, height: 868), "detail-wide")

		model.convertFile()
		await model.conversionSettled()
		#expect(model.status?.tone == .success)
		snapshot(host(model), "detail-created")

		model.handleDrop(paths: [folders.output, folders.source])
		await model.previewSettled()
		snapshot(host(model), "detail-folder")
	}
}
