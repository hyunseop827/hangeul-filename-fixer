// The "새 파일명" text field. An AppKit text field, drawn without its own border (the SwiftUI side draws the rounded box
// and the glow), because a file name must reach the model exactly as it was typed: no spelling correction, no smart
// quotes or dashes, no text replacement, no completion the system offers.
import AppKit
import SwiftUI

/// Lets the SwiftUI side put the cursor into the field (a click on the field's label does that).
@MainActor
final class NameFieldHandle: ObservableObject {
	fileprivate weak var field: NSTextField?

	func focus() {
		guard let field, field.isEnabled else {
			return
		}

		field.window?.makeFirstResponder(field)
	}
}

struct NameField: NSViewRepresentable {
	/// What the field shows. Typing reports through `onChange`; the model's answer comes back here.
	let text: String
	let placeholder: String
	let isEnabled: Bool
	let handle: NameFieldHandle
	let onChange: @MainActor (String) -> Void
	let onFocusChange: @MainActor (Bool) -> Void

	static let font = Theme.nsFont(size: 12, weight: .black)

	func makeCoordinator() -> Coordinator {
		Coordinator(self)
	}

	func makeNSView(context: Context) -> NameTextField {
		let field = NameTextField.make(placeholder: placeholder)
		field.delegate = context.coordinator
		field.onTextChange = { [weak coordinator = context.coordinator] in coordinator?.parent.onChange($0) }
		field.onFocusChange = { [weak coordinator = context.coordinator] in coordinator?.parent.onFocusChange($0) }
		handle.field = field
		return field
	}

	func updateNSView(_ field: NameTextField, context: Context) {
		context.coordinator.parent = self
		handle.field = field

		// A field that is being edited gives up the cursor before it is switched off. (SwiftUI may have switched it off
		// already: see `.disabled` where the field is used.)
		if !isEnabled, field.currentEditor() != nil {
			field.window?.makeFirstResponder(nil)
		}
		if field.isEnabled != isEnabled {
			field.isEnabled = isEnabled
		}

		// Never while a syllable is being composed (Korean input): replacing the text would break it off.
		let isComposing = (field.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
		if !isComposing {
			field.show(text)
		}
	}

	@MainActor
	final class Coordinator: NSObject, NSTextFieldDelegate {
		var parent: NameField

		init(_ parent: NameField) {
			self.parent = parent
		}

		func controlTextDidChange(_ notification: Notification) {
			if let field = notification.object as? NameTextField {
				field.reportIfChanged(field.stringValue)
			}
		}

		func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
			// Return and Escape do nothing in this field: by default Return would select the whole text and Escape
			// could put the old text back.
			commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.cancelOperation(_:))
		}
	}
}

/// Reports every change of its text and when the cursor enters and leaves, and gives its editor the short Korean
/// context menu. Editing always starts through `becomeFirstResponder`, also for a right click and for the menu
/// VoiceOver asks for: that is where the field starts to look focused and to watch its editor.
final class NameTextField: NSTextField {
	/// Called with the field's text whenever it has changed, also while a Korean syllable is still being composed:
	/// the copy must get the name that is on the screen, whether or not the last syllable was "finished".
	var onTextChange: (@MainActor (String) -> Void)?
	var onFocusChange: (@MainActor (Bool) -> Void)?

	/// The text last reported or last put into the field from outside. Only a real change is reported.
	private var knownText = ""
	/// Watches the editor's text while the field is being edited. Gone with the field at the latest: a window that is
	/// closed while the cursor is in the field does not end the editing.
	private(set) var editorObservation: NotificationObservation?
	/// True from when the field takes the cursor until it gives it up.
	private var hasFocus = false

	/// Puts a text into the field from outside (the model's, not typed): nothing is reported back.
	func show(_ text: String) {
		knownText = text
		// By scalars: `!=` would call an NFD and an NFC spelling of the same name equal and leave the old one.
		if !stringValue.unicodeScalars.elementsEqual(text.unicodeScalars) {
			stringValue = text
		}
	}

	/// `text` is what the field holds now. A file name is one line: AppKit's one-line editor already turns the line
	/// breaks of pasted text into spaces; should one get through all the same, it is not passed on.
	func reportIfChanged(_ text: String) {
		let oneLine = String(String.UnicodeScalarView(text.unicodeScalars.filter { $0 != "\n" && $0 != "\r" }))
		guard !oneLine.unicodeScalars.elementsEqual(knownText.unicodeScalars) else {
			return
		}

		knownText = oneLine
		onTextChange?(oneLine)
	}

	/// Watches the editor's text itself while the field is being edited. The usual notification
	/// (controlTextDidChange) is not sent for every step of a composition.
	private func observeEditor() {
		stopObservingEditor()
		guard let storage = (currentEditor() as? NSTextView)?.textStorage else {
			return
		}

		editorObservation = NotificationObservation(NSTextStorage.didProcessEditingNotification, object: storage) { [weak self] notification in
			let text = (notification.object as? NSTextStorage)?.string ?? ""
			// Text is edited on the main thread, and that is where this notification is posted.
			MainActor.assumeIsolated {
				self?.reportIfChanged(text)
			}
		}
	}

	private func stopObservingEditor() {
		editorObservation = nil
	}

	static func make(placeholder: String) -> NameTextField {
		let field = NameTextField()
		field.cell = NameFieldCell(textCell: "")
		field.isEditable = true
		field.isSelectable = true
		field.isBordered = false
		field.isBezeled = false
		field.drawsBackground = false
		field.focusRingType = .none
		field.font = NameField.font
		field.textColor = Theme.fieldText
		field.lineBreakMode = .byClipping
		field.usesSingleLineMode = true
		field.cell?.isScrollable = true
		field.cell?.wraps = false
		field.allowsEditingTextAttributes = false
		field.importsGraphics = false
		field.placeholderAttributedString = NSAttributedString(
			string: placeholder,
			attributes: [.font: NameField.font, .foregroundColor: Theme.placeholder]
		)
		field.setAccessibilityIdentifier("nameField")
		field.setAccessibilityLabel(String(localized: "새 파일명"))
		// The field takes the whole box SwiftUI gives it, so a click anywhere in the box lands in the field.
		field.setContentHuggingPriority(.defaultLow, for: .horizontal)
		field.setContentHuggingPriority(.defaultLow, for: .vertical)
		field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		return field
	}

	override func becomeFirstResponder() -> Bool {
		let became = super.becomeFirstResponder()
		if became {
			observeEditor()
			setFocus(true)
		}
		return became
	}

	override func textDidEndEditing(_ notification: Notification) {
		stopObservingEditor()
		super.textDidEndEditing(notification)
		reportIfChanged(stringValue)
		setFocus(false)
	}

	/// Switched off while it is being edited, the field loses the cursor without being told that the editing ended.
	override var isEnabled: Bool {
		didSet {
			if !isEnabled, hasFocus {
				stopObservingEditor()
				setFocus(false)
			}
		}
	}

	private func setFocus(_ focused: Bool) {
		if focused != hasFocus {
			hasFocus = focused
			onFocusChange?(focused)
		}
	}

	/// Puts the cursor into the field unless it is there already or the field is switched off.
	private func beginEditingIfNeeded() {
		if isEnabled, currentEditor() == nil {
			window?.makeFirstResponder(self)
		}
	}

	/// A right click takes the focus, as it did in the old app's input. AppKit would start the editing by itself, but
	/// without `becomeFirstResponder`: the field would not look focused and would not watch its editor.
	override func rightMouseDown(with event: NSEvent) {
		beginEditingIfNeeded()
		super.rightMouseDown(with: event)
	}

	/// The menu of a right click while editing (the field editor asks its delegate, which is this field): only what
	/// applies to a file name. The selector is NSTextViewDelegate's, spelled out because the field does not declare
	/// that protocol.
	@objc(textView:menu:forEvent:atIndex:)
	func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
		Self.editMenu(for: view)
	}

	/// The same menu when it is asked of the field itself (VoiceOver's "show menu"). Its items act on the editor, so
	/// the field is edited first: with no editor all four would be switched off.
	override func menu(for event: NSEvent) -> NSMenu? {
		guard isEnabled else {
			return nil
		}

		beginEditingIfNeeded()
		return Self.editMenu(for: currentEditor())
	}

	private static func editMenu(for editor: NSText?) -> NSMenu {
		let menu = NSMenu()
		// Only these items: nothing from Services or other plug-ins is appended.
		menu.allowsContextMenuPlugIns = false
		menu.addItem(withTitle: String(localized: "잘라내기"), action: #selector(NSText.cut(_:)), keyEquivalent: "")
		menu.addItem(withTitle: String(localized: "복사하기"), action: #selector(NSText.copy(_:)), keyEquivalent: "")
		menu.addItem(withTitle: String(localized: "붙여넣기"), action: #selector(NSText.paste(_:)), keyEquivalent: "")
		menu.addItem(.separator())
		menu.addItem(withTitle: String(localized: "모두 선택"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
		// The editor carries the actions out and says which of them apply now (nothing to cut without a selection).
		for item in menu.items where !item.isSeparatorItem {
			item.target = editor
		}
		return menu
	}
}

/// Centers the single line in a field that is taller than the text, so the whole box takes the click, and switches
/// off everything that would change what was typed.
final class NameFieldCell: NSTextFieldCell {
	/// The field's own editor, made when the field is first edited.
	private var editor: NameFieldEditor?

	override func fieldEditor(for controlView: NSView) -> NSTextView? {
		if let editor {
			return editor
		}

		let editor = NameFieldEditor()
		editor.isFieldEditor = true
		self.editor = editor
		return editor
	}

	private func centered(_ rect: NSRect) -> NSRect {
		let textHeight = cellSize(forBounds: rect).height
		guard textHeight < rect.height else {
			return rect
		}

		return NSRect(x: rect.minX, y: rect.minY + ((rect.height - textHeight) / 2).rounded(.down), width: rect.width, height: textHeight)
	}

	override func drawingRect(forBounds rect: NSRect) -> NSRect {
		super.drawingRect(forBounds: centered(rect))
	}

	override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
		super.edit(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
	}

	override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
		super.select(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
	}

	override func setUpFieldEditorAttributes(_ textObj: NSText) -> NSText {
		let editor = super.setUpFieldEditorAttributes(textObj)
		if let view = editor as? NSTextView {
			view.isContinuousSpellCheckingEnabled = false
			view.isGrammarCheckingEnabled = false
			view.isAutomaticSpellingCorrectionEnabled = false
			view.isAutomaticTextReplacementEnabled = false
			view.isAutomaticQuoteSubstitutionEnabled = false
			view.isAutomaticDashSubstitutionEnabled = false
			view.isAutomaticTextCompletionEnabled = false
			view.isAutomaticLinkDetectionEnabled = false
			view.isAutomaticDataDetectionEnabled = false
			view.smartInsertDeleteEnabled = false
			// What newer systems offer in a text view on their own: grey inline completions that a key press accepts,
			// the result of a sum after "=", and Writing Tools, which rewrites the text.
			if #available(macOS 14.0, *) {
				view.inlinePredictionType = .no
			}
			if #available(macOS 15.0, *) {
				view.mathExpressionCompletionType = .no
				view.writingToolsBehavior = .none
			}
			view.insertionPointColor = Theme.fieldText
		}
		return editor
	}
}

/// The editor of the name field. The window's shared editor also takes dragged files and types their path; only the
/// drop zone of the first screen takes files, so this one takes dragged text and nothing else.
final class NameFieldEditor: NSTextView {
	override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
		[.string]
	}
}
