// The app's one window, with its own model, and what the model asks the outside world for: the file panel, the
// folder panel and Finder.
//
// The window is always as tall as the card of the current screen needs (WindowFit): compact on the first screen,
// taller once a file is selected. The user can change its width, not its height, and there is no full screen.
import AppKit
import Combine
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate, AppShell {
	static let title = String(localized: "한글 파일명 정리기")

	let window: NSWindow
	let model: AppModel
	/// Called when the window has been closed, so the app can let go of it.
	var onClose: (() -> Void)?
	/// Says a status message to people who use VoiceOver. The unit tests listen here instead.
	var announce: (String) -> Void = { _ in }

	/// The height of what the card holds, as the screen measured it last; 0 before the first layout.
	private(set) var cardContentHeight: CGFloat = 0
	/// The screen (first or selected file) the window was fitted to last. Changing the screen is animated.
	private var fittedToSelectedFile = false
	private var isFitting = false
	private var fitAgain = false
	private var statusObserver: AnyCancellable?
	private var screenObservation: NotificationObservation?

	init(model: AppModel = AppModel()) {
		self.model = model
		let contentSize = NSSize(width: WindowFit.initialWidth, height: WindowFit.contentHeight(forCardContent: 0))
		window = NSWindow(
			contentRect: NSRect(origin: .zero, size: contentSize),
			// Resizable for the width; the height is held at the content's (fitToContent).
			styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered,
			defer: false
		)
		super.init()

		window.title = Self.title
		// The app keeps running without its window; the window is let go by the app delegate, not by AppKit.
		window.isReleasedWhenClosed = false
		// A new window always starts from the first screen: nothing is restored from the last run.
		window.isRestorable = false
		window.tabbingMode = .disallowed
		// No full screen: it would only put the empty area back around the card. The green button zooms instead.
		window.collectionBehavior = [.fullScreenNone]
		// The two screens have different views; Tab must find the ones that are there now.
		window.autorecalculatesKeyViewLoop = true
		// The screen is light also when the system is dark: the window, its title bar and its panels.
		window.appearance = NSAppearance(named: .aqua)
		window.backgroundColor = Theme.windowBackground
		window.delegate = self

		// The SwiftUI view fills a plain content view. As the content view itself, a hosting view would also set the
		// window's smallest and largest size from its content.
		let content = NSView(frame: NSRect(origin: .zero, size: contentSize))
		let rootView = RootView(model: model, onContentHeightChange: { [weak self] height in
			// SwiftUI reports while it lays the views out, which it does on the main thread.
			MainActor.assumeIsolated {
				self?.cardContentHeightChanged(height)
			}
		})
		let hosting = ScreenHostingView(rootView: rootView)
		hosting.frame = content.bounds
		hosting.autoresizingMask = [.width, .height]
		content.addSubview(hosting)
		window.contentView = content

		fitToContent()
		window.center()
		// The Dock is shown or resized, or the resolution changes: the visible area of the screen is another one while
		// the window stays on its screen. Its height is held at the content's, so only the app can make it fit again.
		screenObservation = NotificationObservation(NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
			// AppKit posts this on the main thread.
			MainActor.assumeIsolated {
				self?.fitToContent()
			}
		}

		model.shell = self
		announce = { [weak self] message in
			self?.postAnnouncement(message)
		}
		// What the old app's status line did by being a live region (role="status"): every message that appears is
		// spoken. `$status` reports each new value as it is set.
		statusObserver = model.$status.sink { [weak self] status in
			if let message = status?.message {
				self?.announce(message)
			}
		}
	}

	func show() {
		window.makeKeyAndOrderFront(nil)
		// No control starts out with the keyboard focus.
		window.makeFirstResponder(nil)
	}

	// MARK: The window's size

	private func cardContentHeightChanged(_ height: CGFloat) {
		guard height != cardContentHeight else {
			return
		}

		cardContentHeight = height
		// After the layout that reported this height has finished: the window must not be resized from inside it.
		Task { @MainActor [weak self] in
			self?.fitToContent()
		}
	}

	/// Makes the window as tall as the card needs. The top-left corner stays, the frame stays inside the screen's
	/// visible area, and going from one screen to the other is animated.
	private func fitToContent() {
		guard !isFitting else {
			// Asked again while the window is on its (animated) way to the last size: once more when it has arrived.
			fitAgain = true
			return
		}

		isFitting = true
		defer { isFitting = false }
		repeat {
			fitAgain = false
			// The screen may have changed again since the height was reported (the preview arrived): take that in first.
			window.contentView?.layoutSubtreeIfNeeded()

			let frame = window.frame
			let titleBarHeight = frame.height - window.contentRect(forFrameRect: frame).height
			let wantedHeight = WindowFit.contentHeight(forCardContent: cardContentHeight) + titleBarHeight
			let fitted = WindowFit.frame(frame, withHeight: wantedHeight, in: window.screen?.visibleFrame)

			// The user changes the width only: the smallest and the largest height are the fitted one.
			let contentHeight = fitted.height - titleBarHeight
			window.contentMinSize = NSSize(width: WindowFit.minimumWidth, height: contentHeight)
			window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: contentHeight)

			let showsSelectedFile = model.sourcePath != nil
			let screenChanged = showsSelectedFile != fittedToSelectedFile
			fittedToSelectedFile = showsSelectedFile

			if fitted != frame {
				window.setFrame(fitted, display: true, animate: screenChanged && window.isVisible)
			}
		} while fitAgain
	}

	// MARK: NSWindowDelegate

	func windowWillClose(_ notification: Notification) {
		onClose?()
	}

	/// Another screen may be smaller than the card is tall.
	func windowDidChangeScreen(_ notification: Notification) {
		fitToContent()
	}

	/// "확대/축소" and the green button: wider, never taller than the content.
	func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
		WindowFit.zoomedFrame(window.frame, in: newFrame)
	}

	/// Zooming back, AppKit puts the window where its bottom-left corner was. At the other width the content may be a
	/// line taller or shorter, so the top edge would end up somewhere else; it is put back where it was.
	func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
		let top = window.frame.maxY
		// Right after the zoom, before the window is fitted to the content at its new width.
		Task { @MainActor [weak window] in
			if let window, window.frame.maxY != top {
				window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: top))
			}
		}
		return true
	}

	// MARK: VoiceOver

	private func postAnnouncement(_ message: String) {
		NSAccessibility.post(
			element: window,
			notification: .announcementRequested,
			userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
		)
	}

	// MARK: AppShell

	/// The panel that asks for the file to tidy.
	static func filePanel() -> NSOpenPanel {
		let panel = NSOpenPanel()
		panel.message = String(localized: "정리할 파일을 선택하세요")
		panel.canChooseFiles = true
		panel.canChooseDirectories = false
		panel.allowsMultipleSelection = false
		panel.canCreateDirectories = false
		// An app or another package is shown as the folder it is, so a file inside it can be chosen.
		panel.treatsFilePackagesAsDirectories = true
		return panel
	}

	/// The panel that asks for the folder the copy goes to. It starts at `directory`, and a folder can be made in it.
	static func folderPanel(startingAt directory: String?) -> NSOpenPanel {
		let panel = NSOpenPanel()
		panel.message = String(localized: "사본을 저장할 폴더를 선택하세요")
		panel.canChooseFiles = false
		panel.canChooseDirectories = true
		panel.allowsMultipleSelection = false
		panel.canCreateDirectories = true
		if let directory {
			panel.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
		}
		return panel
	}

	func chooseFile(completion: @escaping @MainActor (String?) -> Void) {
		present(Self.filePanel(), completion: completion)
	}

	func chooseOutputDirectory(startingAt directory: String?, completion: @escaping @MainActor (String?) -> Void) {
		present(Self.folderPanel(startingAt: directory), completion: completion)
	}

	func revealInFinder(path: String) {
		NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
	}

	/// Shows the panel as a sheet on the window and reports the chosen path; nil when it was cancelled.
	///
	/// The path's spelling (NFC or NFD) is whatever the panel's URL carries, which need not be the spelling on disk.
	/// That is fine: the Core reads the folder again to learn the stored name.
	private func present(_ panel: NSOpenPanel, completion: @escaping @MainActor (String?) -> Void) {
		panel.beginSheetModal(for: window) { response in
			completion(response == .OK ? panel.url?.path : nil)
		}
	}
}
