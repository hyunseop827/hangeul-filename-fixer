// The menu bar, in Korean, built in code. The items are the standard ones with their standard key equivalents; what
// macOS adds by itself (받아쓰기, 이모티콘 및 기호, the window list, …) is Korean as well, because Korean is the app's
// only language.
import AppKit

@MainActor
enum MainMenu {
	static func make() -> NSMenu {
		let mainMenu = NSMenu()

		// No "보기" menu: all it could hold is full screen, which this window does not have.
		for menu in [applicationMenu(), fileMenu(), editMenu(), windowMenu()] {
			let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
			item.submenu = menu
			mainMenu.addItem(item)
		}

		return mainMenu
	}

	private static func applicationMenu() -> NSMenu {
		// The menu bar shows the app's name (CFBundleName) for the first menu, whatever this title says.
		let menu = NSMenu(title: String(localized: "한글 파일명 정리기"))

		menu.addItem(withTitle: String(localized: "한글 파일명 정리기에 관하여"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
		// "업데이트 확인…" goes here, right under the About item, once the app can update itself (Sparkle).
		menu.addItem(.separator())

		let services = NSMenu(title: String(localized: "서비스"))
		let servicesItem = menu.addItem(withTitle: services.title, action: nil, keyEquivalent: "")
		servicesItem.submenu = services
		NSApp.servicesMenu = services
		menu.addItem(.separator())

		menu.addItem(withTitle: String(localized: "한글 파일명 정리기 가리기"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
		let hideOthers = menu.addItem(withTitle: String(localized: "기타 가리기"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
		hideOthers.keyEquivalentModifierMask = [.command, .option]
		menu.addItem(withTitle: String(localized: "모두 보기"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
		menu.addItem(.separator())

		menu.addItem(withTitle: String(localized: "한글 파일명 정리기 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		return menu
	}

	private static func fileMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: "파일"))
		menu.addItem(withTitle: String(localized: "창 닫기"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
		return menu
	}

	/// Needed for ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z in the name field: a key equivalent only works through a menu item.
	private static func editMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: "편집"))
		menu.addItem(withTitle: String(localized: "실행 취소"), action: Selector(("undo:")), keyEquivalent: "z")
		let redo = menu.addItem(withTitle: String(localized: "실행 복귀"), action: Selector(("redo:")), keyEquivalent: "z")
		redo.keyEquivalentModifierMask = [.command, .shift]
		menu.addItem(.separator())
		menu.addItem(withTitle: String(localized: "잘라내기"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		menu.addItem(withTitle: String(localized: "복사하기"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		menu.addItem(withTitle: String(localized: "붙여넣기"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		menu.addItem(withTitle: String(localized: "모두 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
		return menu
	}

	private static func windowMenu() -> NSMenu {
		let menu = NSMenu(title: String(localized: "윈도우"))
		menu.addItem(withTitle: String(localized: "최소화"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
		menu.addItem(withTitle: String(localized: "확대/축소"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
		menu.addItem(.separator())
		menu.addItem(withTitle: String(localized: "앞으로 모두 가져오기"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
		// AppKit lists the open windows at the end of this menu.
		NSApp.windowsMenu = menu
		return menu
	}
}
