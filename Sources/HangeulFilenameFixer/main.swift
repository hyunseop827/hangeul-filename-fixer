// STUB — replaced by the Core/app implementation
//
// Just enough AppKit to prove that the bundle made by scripts/build-app.sh launches: one 470×800 window titled
// "한글 파일명 정리기" with a label, and an app menu with a Quit item.
import AppKit
import HangeulFilenameFixerCore

enum StubApp {
	static let windowTitle = "한글 파일명 정리기"
	static let windowSize = NSSize(width: 470, height: 800)
}

@MainActor
final class StubAppDelegate: NSObject, NSApplicationDelegate {
	private var window: NSWindow?

	func applicationDidFinishLaunching(_ notification: Notification) {
		let mainMenu = NSMenu()
		let appMenuItem = NSMenuItem()
		let appMenu = NSMenu()
		appMenu.addItem(withTitle: "\(StubApp.windowTitle) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
		appMenuItem.submenu = appMenu
		mainMenu.addItem(appMenuItem)
		NSApp.mainMenu = mainMenu

		let window = NSWindow(
			contentRect: NSRect(origin: .zero, size: StubApp.windowSize),
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		window.title = StubApp.windowTitle
		window.isReleasedWhenClosed = false
		let label = NSTextField(labelWithString: "빌드 확인용 임시 화면입니다. (\(corePlaceholderName))")
		label.translatesAutoresizingMaskIntoConstraints = false
		let content = NSView()
		content.addSubview(label)
		NSLayoutConstraint.activate([
			label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
			label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
		])
		window.contentView = content
		// The frame (title bar included) is 470×800, as the Electron window was.
		window.setFrame(NSRect(origin: .zero, size: StubApp.windowSize), display: false)
		window.center()
		window.makeKeyAndOrderFront(nil)
		self.window = window
		NSApp.activate(ignoringOtherApps: true)
	}
}

let delegate = StubAppDelegate()
let application = NSApplication.shared
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
