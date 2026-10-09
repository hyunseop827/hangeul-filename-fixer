// Colors and sizes of the screen. The window follows the system appearance (since 2.1.0), so every color has two
// values: the light one, which is the color the app had when it was light only, and a dark one. `NSColor(name:
// dynamicProvider:)` picks the value by the appearance the color is drawn in (`dynamicColor`), and the SwiftUI colors
// wrap those AppKit colors (`Color(nsColor:)`), so the two palettes are written out here once, side by side.
import AppKit
import SwiftUI

enum Theme {
	// MARK: Colors

	/// The window behind the card.
	static let background = dynamic(light: 0xF8FAFC, dark: 0x0F172A)
	static let card = dynamic(light: 0xFFFFFF, dark: 0x1E293B)
	static let primary = dynamic(light: 0x4F46E5, dark: 0x818CF8)
	/// The text on a `primary` fill ("NFC 사본 만들기"): white in light, where the fill is deep; the window's dark in dark,
	/// where the fill is the lighter one.
	static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x0F172A)
	static let success = dynamic(light: 0x15803D, dark: 0x4ADE80)
	static let warning = dynamic(light: 0xF59E0B, dark: 0xFBBF24)
	static let error = dynamic(light: 0xB91C1C, dark: 0xF87171)
	static let text = dynamic(light: 0x111827, dark: 0xF1F5F9)
	static let muted = dynamic(light: 0x6B7280, dark: 0x94A3B8)
	static let line = dynamic(light: 0xE5E7EB, dark: 0x334155)
	static let soft = dynamic(light: 0xF1F5F9, dark: 0x273449)
	static let primarySoft = dynamic(light: 0xEEF2FF, dark: 0x312E81)
	/// The chosen half of the "기존 이름 유지 / 이름 바꾸기" switch: the card's white in light; in dark a step lighter than
	/// the `soft` track it stands on, so it is raised in both.
	static let selectedSegment = dynamic(light: 0xFFFFFF, dark: 0x334155)
	/// The shadows under the card and under the chosen half of the switch: a little of the text's color in light, black
	/// in dark, where a shadow has to be deeper to be seen.
	static let cardShadow = dynamic(light: 0x111827, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.45)
	static let segmentShadow = dynamic(light: 0x111827, dark: 0x000000, lightAlpha: 0.12, darkAlpha: 0.5)

	static let dropZoneFill = dynamic(light: 0xFBFDFF, dark: 0x1B2435)
	static let dropZoneBorder = dynamic(light: 0xCBD5E1, dark: 0x475569)
	/// The border of the name field and of the result box.
	static let fieldBorder = dynamic(light: 0xD1D5DB, dark: 0x475569)
	/// The glow around the name field while it is being edited.
	static let focusGlow = dynamic(light: 0x4F46E5, dark: 0x818CF8, lightAlpha: 0.14, darkAlpha: 0.22)
	/// The name field's fill while it cannot be edited.
	static let disabledFieldFill = dynamic(light: 0xEFEFEF, dark: 0x334155, lightAlpha: 0.3, darkAlpha: 0.3)
	/// The name field's own colors, for AppKit: its placeholder, and its text and text cursor (the text's color).
	static let placeholder = dynamicColor(light: 0x757575, dark: 0x94A3B8)
	static let fieldText = dynamicColor(light: 0x111827, dark: 0xF1F5F9)
	/// The window's own color, for AppKit: `background`.
	static let windowBackground = dynamicColor(light: 0xF8FAFC, dark: 0x0F172A)

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

	/// The tile behind a file icon, and the color of its label when the image is missing. In dark the tiles are deep
	/// versions of their light tints, and the labels are the light labels brightened.
	static func tileColors(_ kind: FileIconType.Kind) -> (fill: Color, label: Color) {
		switch kind {
		case .word: return wordTile
		case .hwp: return hwpTile
		case .pdf: return pdfTile
		case .powerPoint: return powerPointTile
		case .sheet: return sheetTile
		case .text: return (soft, text)
		case .image: return (primarySoft, primary)
		case .archive: return archiveTile
		case .generic: return (primarySoft, primary)
		}
	}

	private static let wordTile = (fill: dynamic(light: 0xEFF6FF, dark: 0x1E3A8A), label: dynamic(light: 0x2563EB, dark: 0x93C5FD))
	private static let hwpTile = (fill: dynamic(light: 0xECFDF5, dark: 0x064E3B), label: dynamic(light: 0x059669, dark: 0x6EE7B7))
	private static let pdfTile = (fill: dynamic(light: 0xFEF2F2, dark: 0x7F1D1D), label: dynamic(light: 0xDC2626, dark: 0xFCA5A5))
	private static let powerPointTile = (fill: dynamic(light: 0xFFF7ED, dark: 0x7C2D12), label: dynamic(light: 0xEA580C, dark: 0xFDBA74))
	private static let sheetTile = (fill: dynamic(light: 0xF0FDF4, dark: 0x14532D), label: dynamic(light: 0x16A34A, dark: 0x86EFAC))
	private static let archiveTile = (fill: dynamic(light: 0xFFFBEB, dark: 0x78350F), label: warning)

	// MARK: The two palettes

	/// A color of the screen: `light` under the light appearance, `dark` under the dark one (0xRRGGBB, sRGB), each with
	/// its own opacity.
	static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
		Color(nsColor: dynamicColor(light: light, dark: dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha))
	}

	/// The AppKit color behind `dynamic`: resolved by the appearance it is drawn in, as AppKit resolves its own colors.
	/// In the app that is the system's appearance, which the window follows; the tests pin one.
	static func dynamicColor(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
		NSColor(name: nil) { appearance in
			appearance.isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
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

extension NSAppearance {
	/// True for the dark appearance and its high-contrast variant; false for the light ones.
	var isDark: Bool {
		bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
	}
}

extension NSColor {
	/// An sRGB color from 0xRRGGBB.
	convenience init(hex: UInt32, alpha: CGFloat = 1) {
		self.init(
			srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
			green: CGFloat((hex >> 8) & 0xFF) / 255,
			blue: CGFloat(hex & 0xFF) / 255,
			alpha: alpha
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
