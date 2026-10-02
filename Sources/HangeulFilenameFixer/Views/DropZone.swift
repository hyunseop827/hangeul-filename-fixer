// The first screen's drop zone: a dashed box that takes a dropped file and, as a button, opens the file panel.
//
// SwiftUI draws it; an AppKit view on top takes the clicks, the keys and the drags. AppKit, because the dragging
// pasteboard hands over all file URLs at once and in their order, and because a view of our own can take part in the
// window's Tab order and answer Space and Return like a button.
import AppKit
import SwiftUI

struct DropZone: View {
	@ObservedObject var model: AppModel

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 16, style: .circular)
		let title = String(localized: "파일을 여기에 놓기")
		let explanation = String(localized: "또는 클릭해서 선택하세요. 한 번에 파일 하나만 처리합니다.")

		VStack(spacing: 10) {
			Text(verbatim: "⇧")
				.font(Theme.font(size: 24, weight: .heavy))
				.foregroundColor(Theme.primary)
				.frame(width: 48, height: 48)
				.background(Circle().fill(Theme.primarySoft))

			Text(verbatim: title)
				.textLine(size: 16, weight: .heavy, color: Theme.text, height: Theme.nameLine)

			Text(verbatim: explanation)
				.textLine(size: 12, weight: .regular, color: Theme.muted, height: Theme.smallLine)
		}
		.frame(maxWidth: .infinity, minHeight: 210)
		.background(shape.fill(model.isDragging ? Theme.primarySoft : Theme.dropZoneFill))
		.overlay(
			shape.strokeBorder(
				model.isDragging ? Theme.primary : Theme.dropZoneBorder,
				style: StrokeStyle(lineWidth: 2, dash: [4, 2])
			)
		)
		.animation(.easeInOut(duration: 0.16), value: model.isDragging)
		// The AppKit view below is the one element assistive apps see: a button named after the title.
		.accessibilityHidden(true)
		.overlay(
			DropTarget(
				label: title,
				help: explanation,
				onPress: { model.selectFile() },
				onDraggingChange: { model.setDragging($0) },
				onDrop: { model.handleDrop(paths: $0) }
			)
		)
	}
}

private struct DropTarget: NSViewRepresentable {
	let label: String
	let help: String
	let onPress: @MainActor () -> Void
	let onDraggingChange: @MainActor (Bool) -> Void
	let onDrop: @MainActor ([String]) -> Void

	func makeNSView(context: Context) -> DropTargetView {
		let view = DropTargetView()
		update(view)
		return view
	}

	func updateNSView(_ view: DropTargetView, context: Context) {
		update(view)
	}

	private func update(_ view: DropTargetView) {
		view.label = label
		view.help = help
		view.onPress = onPress
		view.onDraggingChange = onDraggingChange
		view.onDrop = onDrop
	}
}

/// Invisible; sits over the drop zone and is its button and its drag destination.
final class DropTargetView: NSView {
	var label = ""
	var help = ""
	var onPress: (@MainActor () -> Void)?
	var onDraggingChange: (@MainActor (Bool) -> Void)?
	var onDrop: (@MainActor ([String]) -> Void)?

	/// The focus ring is for the keyboard: a click must not leave a ring behind.
	private var showsFocusRing = false

	override init(frame: NSRect) {
		super.init(frame: frame)
		registerForDraggedTypes([.fileURL])
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("not used: the view is made in code")
	}

	/// The paths of the files a drag or a copy carries, in the pasteboard's order. Folders and apps are in the list
	/// too; whether an item is a regular file is the Core's question.
	///
	/// The spelling of these paths is not to be trusted: the same file can arrive spelled NFC or NFD. The Core reads
	/// the folder again to learn the name that is really stored.
	static func filePaths(from pasteboard: NSPasteboard) -> [String] {
		let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
		return objects.compactMap { object in
			guard let url = object as? NSURL else {
				return nil
			}

			// Finder may put a file-reference URL ("file:///.file/id=…") on the pasteboard; `filePathURL` is its path form.
			return (url.filePathURL ?? url as URL).path
		}
	}

	// MARK: Button

	override var acceptsFirstResponder: Bool { true }

	override func becomeFirstResponder() -> Bool {
		// Reached with Tab: show the ring. Reached by a click: do not.
		showsFocusRing = NSApp.currentEvent?.type == .keyDown
		noteFocusRingMaskChanged()
		return true
	}

	override func resignFirstResponder() -> Bool {
		showsFocusRing = false
		noteFocusRingMaskChanged()
		return true
	}

	override var focusRingMaskBounds: NSRect {
		showsFocusRing ? bounds : .zero
	}

	override func drawFocusRingMask() {
		if showsFocusRing {
			NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).fill()
		}
	}

	override func mouseDown(with event: NSEvent) {
		// Taken, so the click is this view's; the press happens on mouseUp, like a button.
	}

	override func mouseUp(with event: NSEvent) {
		if bounds.contains(convert(event.locationInWindow, from: nil)) {
			onPress?()
		}
	}

	override func keyDown(with event: NSEvent) {
		// Space, Return, Enter on the keypad.
		if [49, 36, 76].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
			onPress?()
		} else {
			super.keyDown(with: event)
		}
	}

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: .pointingHand)
	}

	// MARK: Drag destination

	override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
		onDraggingChange?(true)
		return .copy
	}

	override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
		.copy
	}

	override func draggingExited(_ sender: NSDraggingInfo?) {
		onDraggingChange?(false)
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		let paths = Self.filePaths(from: sender.draggingPasteboard)
		// After the drag has ended: selecting the file takes this view off the screen.
		let onDrop = self.onDrop
		Task { @MainActor in
			onDrop?(paths)
		}
		return !paths.isEmpty
	}

	// MARK: Accessibility

	override func isAccessibilityElement() -> Bool { true }
	override func isAccessibilityEnabled() -> Bool { true }
	override func accessibilityRole() -> NSAccessibility.Role? { .button }
	override func accessibilityLabel() -> String? { label }
	override func accessibilityHelp() -> String? { help }
	override func accessibilityIdentifier() -> String { "dropZone" }

	override func accessibilityPerformPress() -> Bool {
		onPress?()
		return true
	}
}
