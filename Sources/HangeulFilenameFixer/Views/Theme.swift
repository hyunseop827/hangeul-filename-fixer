// Colors and sizes of the screen. The app is light in dark mode too, so every color is a fixed sRGB value.
import AppKit
import SwiftUI

enum Theme {
	// MARK: Colors

	/// The window behind the card.
	static let background = Color(hex: 0xF8FAFC)
	static let card = Color(hex: 0xFFFFFF)
	static let primary = Color(hex: 0x4F46E5)
	static let success = Color(hex: 0x15803D)
	static let warning = Color(hex: 0xF59E0B)
	static let error = Color(hex: 0xB91C1C)
	static let text = Color(hex: 0x111827)
	static let muted = Color(hex: 0x6B7280)
	static let line = Color(hex: 0xE5E7EB)
	static let soft = Color(hex: 0xF1F5F9)
	static let primarySoft = Color(hex: 0xEEF2FF)

	static let dropZoneFill = Color(hex: 0xFBFDFF)
	static let dropZoneBorder = Color(hex: 0xCBD5E1)
	/// The border of the name field and of the result box.
	static let fieldBorder = Color(hex: 0xD1D5DB)
	/// The glow around the name field while it is being edited.
	static let focusGlow = Color(hex: 0x4F46E5).opacity(0.14)
	/// The name field's fill while it cannot be edited.
	static let disabledFieldFill = Color(.sRGB, red: 239 / 255, green: 239 / 255, blue: 239 / 255, opacity: 0.3)
	static let placeholder = NSColor(srgbRed: 0x75 / 255, green: 0x75 / 255, blue: 0x75 / 255, alpha: 1)
	static let fieldText = NSColor(srgbRed: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255, alpha: 1)
	static let windowBackground = NSColor(srgbRed: 0xF8 / 255, green: 0xFA / 255, blue: 0xFC / 255, alpha: 1)

	/// What a control that cannot be used looks like: faded, not recolored.
	static let disabledOpacity = 0.48

	/// The color of the status line.
	static func statusColor(_ tone: AppModel.Status.Tone?) -> Color {
		switch tone {
		case .success: return success
		case .error: return error
		case .info, .none: return muted
		}
	}

	/// The tile behind a file icon, and the color of its label when the image is missing.
	static func tileColors(_ kind: FileIconType.Kind) -> (fill: Color, label: Color) {
		switch kind {
		case .word: return (Color(hex: 0xEFF6FF), Color(hex: 0x2563EB))
		case .hwp: return (Color(hex: 0xECFDF5), Color(hex: 0x059669))
		case .pdf: return (Color(hex: 0xFEF2F2), Color(hex: 0xDC2626))
		case .powerPoint: return (Color(hex: 0xFFF7ED), Color(hex: 0xEA580C))
		case .sheet: return (Color(hex: 0xF0FDF4), Color(hex: 0x16A34A))
		case .text: return (soft, text)
		case .image: return (primarySoft, primary)
		case .archive: return (Color(hex: 0xFFFBEB), warning)
		case .generic: return (primarySoft, primary)
		}
	}

	// MARK: Sizes

	/// The space between the window's edge and the card: top, sides, bottom.
	static let windowPaddingTop: CGFloat = 14
	static let windowPaddingSide: CGFloat = 12
	static let windowPaddingBottom: CGFloat = 10
	/// The row under the card that holds the "업데이트 확인" link (RootView): the gap to the card and one line of the
	/// small text, which stands at the row's bottom.
	static let footerHeight: CGFloat = 22
	static let cardMaxWidth: CGFloat = 900
	static let cardMinHeight: CGFloat = 300
	static let cardRadius: CGFloat = 18
	/// The card's border, which belongs to its height.
	static let cardBorder: CGFloat = 1

	/// The height of one line of text, by font size. Fixed, so the rows keep their place whatever the font's own
	/// line height is for Latin or Korean letters.
	static let smallLine: CGFloat = 15      // 12 pt
	static let nameLine: CGFloat = 20.5     // 16 pt
}

extension Color {
	/// An opaque sRGB color from 0xRRGGBB.
	init(hex: UInt32) {
		self.init(
			.sRGB,
			red: Double((hex >> 16) & 0xFF) / 255,
			green: Double((hex >> 8) & 0xFF) / 255,
			blue: Double(hex & 0xFF) / 255,
			opacity: 1
		)
	}
}

extension Theme {
	// MARK: Fonts

	/// The system font. For the two heaviest weights the Korean letters are taken from Apple SD Gothic Neo ExtraBold,
	/// as the old app drew them: left to itself, macOS draws Korean in "Heavy" for every weight above bold, which is
	/// about a third more ink. Latin letters and digits stay the system's.
	static func nsFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
		let font = NSFont.systemFont(ofSize: size, weight: weight)
		guard weight.rawValue > NSFont.Weight.bold.rawValue else {
			return font
		}

		// Looked at first for every letter the system font itself does not have. Without that font installed, the
		// system's usual choice follows.
		let korean = NSFontDescriptor(fontAttributes: [.name: "AppleSDGothicNeo-ExtraBold"])
		return NSFont(descriptor: font.fontDescriptor.addingAttributes([.cascadeList: [korean]]), size: size) ?? font
	}

	static func font(size: CGFloat, weight: Font.Weight) -> Font {
		switch weight {
		case .heavy: return Font(nsFont(size: size, weight: .heavy) as CTFont)
		case .black: return Font(nsFont(size: size, weight: .black) as CTFont)
		default: return .system(size: size, weight: weight)
		}
	}
}

extension View {
	/// A single line of text in a row of fixed height.
	func textLine(size: CGFloat, weight: Font.Weight, color: Color, height: CGFloat) -> some View {
		font(Theme.font(size: size, weight: weight))
			.foregroundColor(color)
			.lineLimit(1)
			.frame(height: height)
	}
}
