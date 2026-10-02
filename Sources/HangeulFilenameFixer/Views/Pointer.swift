// The pointer's shape over the buttons: a pointing hand where a press does something, the "not allowed" sign where it
// does not — as in the old app, whose buttons were drawn by a web view.
import AppKit
import SwiftUI

extension View {
	/// Shows `cursor` while the pointer is over this view; nil leaves the pointer as it is.
	func pointer(_ cursor: NSCursor?) -> some View {
		overlay(
			Group {
				if let cursor {
					PointerArea(cursor: cursor)
				}
			}
			// Only the pointer's shape: clicks go to what lies underneath, and assistive apps see nothing here.
			.allowsHitTesting(false)
			.accessibilityHidden(true)
		)
	}
}

private struct PointerArea: NSViewRepresentable {
	let cursor: NSCursor

	func makeNSView(context: Context) -> PointerAreaView {
		let view = PointerAreaView()
		view.cursor = cursor
		return view
	}

	func updateNSView(_ view: PointerAreaView, context: Context) {
		view.cursor = cursor
	}
}

/// Invisible and never clicked; sets the pointer's shape while the pointer is over it.
///
/// With a tracking area and not with a cursor rect: AppKit applies a cursor rect only for the view a click would go
/// to, and this view passes every click on to the SwiftUI button underneath.
final class PointerAreaView: NSView {
	var cursor: NSCursor = .arrow {
		didSet {
			// The button under the pointer was switched on or off.
			if cursor !== oldValue {
				showIfUnderPointer()
			}
		}
	}

	/// True while the pointer is over this view in the window that has the keyboard.
	var isUnderPointer: Bool {
		guard let window, window.isKeyWindow else {
			return false
		}

		return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
	}

	private func showIfUnderPointer() {
		if isUnderPointer {
			cursor.set()
		}
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		nil
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		for area in trackingAreas {
			removeTrackingArea(area)
		}
		addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
		// Put under a pointer that does not move (the screen changed around it): no "entered" follows.
		showIfUnderPointer()
	}

	override func mouseEntered(with event: NSEvent) {
		cursor.set()
	}

	override func mouseMoved(with event: NSEvent) {
		cursor.set()
	}

	override func mouseExited(with event: NSEvent) {
		NSCursor.arrow.set()
	}

	override func viewWillMove(toWindow newWindow: NSWindow?) {
		// Taken off the screen under the pointer (the button led to the other screen): no "exited" follows.
		if newWindow == nil, isUnderPointer {
			NSCursor.arrow.set()
		}
		super.viewWillMove(toWindow: newWindow)
	}
}

/// The view that holds the screen in the window. Whenever the views have changed, AppKit asks the view under the
/// pointer for the pointer's shape. To AppKit that is this view (the pointer areas take no clicks), and SwiftUI
/// answers with the arrow; over a pointer area the answer is that area's.
final class ScreenHostingView: NSHostingView<RootView> {
	override func cursorUpdate(with event: NSEvent) {
		if let area = Self.pointerArea(underPointerIn: self) {
			area.cursor.set()
		} else {
			super.cursorUpdate(with: event)
		}
	}

	private static func pointerArea(underPointerIn view: NSView) -> PointerAreaView? {
		if let area = view as? PointerAreaView {
			return area.isUnderPointer ? area : nil
		}

		for subview in view.subviews {
			if let area = pointerArea(underPointerIn: subview) {
				return area
			}
		}
		return nil
	}
}
