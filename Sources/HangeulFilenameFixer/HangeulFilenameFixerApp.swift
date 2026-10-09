// 한글 파일명 정리기: the app's entry point and its life as an app (AppKit, no storyboard).
//
// One window. Closing it leaves the app running; a click on the Dock icon then opens a new window that starts from
// the first screen.
import AppKit

@main
enum HangeulFilenameFixerApp {
	@MainActor
	static func main() {
		// Before any window exists: no "탭 막대 보기" and no window tabs.
		NSWindow.allowsAutomaticWindowTabbing = false

		let application = NSApplication.shared
		let delegate = AppDelegate()
		application.delegate = delegate
		application.setActivationPolicy(.regular)
		// The application only holds its delegate weakly.
		withExtendedLifetime(delegate) {
			application.run()
		}
	}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	private(set) var windowController: MainWindowController?
	/// The copies that are still being written, over all windows.
	private let conversions: ConversionTracker
	/// Puts a new window on the screen, and tells AppKit that the app may quit now. Values, so the unit tests can ask
	/// this delegate its questions without a window appearing and without the test process quitting.
	private let showWindow: (MainWindowController) -> Void
	private let replyToTerminate: (Bool) -> Void

	init(
		conversions: ConversionTracker = .shared,
		showWindow: @escaping (MainWindowController) -> Void = { $0.show() },
		replyToTerminate: @escaping (Bool) -> Void = { NSApp.reply(toApplicationShouldTerminate: $0) }
	) {
		self.conversions = conversions
		self.showWindow = showWindow
		self.replyToTerminate = replyToTerminate
		super.init()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		// The updater starts with the app (AppUpdater.swift says what that does and does not send), and
		// "업데이트 확인…" in the app menu is wired to it. (The "업데이트 확인" link under the card asks it itself: RootView.)
		NSApp.mainMenu = MainMenu.make(updateCheck: AppUpdater.shared.check)
		// Not activated here: macOS brings an app to the front when the user opens it, and leaves it in the background
		// when it was asked to (`open -g`).
		openWindow()
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
		false
	}

	/// The Dock icon was clicked, or the app was opened again while it is running.
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
		if windowController == nil {
			openWindow()
			return false
		}

		// The window exists (perhaps in the Dock): AppKit brings it back.
		return true
	}

	/// Quitting while a copy is being written waits for that copy: stopped half-way it would stay behind, incomplete,
	/// under its final name. Sparkle's quit for installing an update comes through here as well (it asks the app to
	/// quit the ordinary way), so an update waits for the copy too.
	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		guard conversions.running > 0 else {
			return .terminateNow
		}

		let replyToTerminate = self.replyToTerminate
		conversions.onIdle = {
			replyToTerminate(true)
		}
		return .terminateLater
	}

	/// Nothing of a window is saved or restored (the window is not restorable); this only says so to AppKit.
	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		true
	}

	private func openWindow() {
		let controller = MainWindowController()
		controller.onClose = { [weak self, weak controller] in
			// Only for the window that is current: a new window starts with a new model.
			if let self, self.windowController === controller {
				self.windowController = nil
			}
		}
		windowController = controller
		showWindow(controller)
	}
}
