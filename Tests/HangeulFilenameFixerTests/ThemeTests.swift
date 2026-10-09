// The two palettes of the screen (Views/Theme.swift). The light one is the look the app had while it was light only
// (2.0.x), value for value; the dark one differs from it in every color and reads as well. The colors are asked for
// their value under each appearance the way AppKit asks when it draws.
import AppKit
import SwiftUI
import Testing
@testable import HangeulFilenameFixer

@MainActor
@Suite struct ThemeTests {
	/// The opaque colors of the screen, with the light value each had before dark mode (2.0.2).
	private static let opaque: [(name: String, color: Color, light: UInt32)] = [
		("background", Theme.background, 0xF8FAFC),
		("card", Theme.card, 0xFFFFFF),
		("primary", Theme.primary, 0x4F46E5),
		// The text of "NFC 사본 만들기" was the card's white.
		("onPrimary", Theme.onPrimary, 0xFFFFFF),
		("success", Theme.success, 0x15803D),
		("warning", Theme.warning, 0xF59E0B),
		("error", Theme.error, 0xB91C1C),
		("text", Theme.text, 0x111827),
		("muted", Theme.muted, 0x6B7280),
		("line", Theme.line, 0xE5E7EB),
		("soft", Theme.soft, 0xF1F5F9),
		("primarySoft", Theme.primarySoft, 0xEEF2FF),
		// The chosen half of the name switch was the card's white.
		("selectedSegment", Theme.selectedSegment, 0xFFFFFF),
		("dropZoneFill", Theme.dropZoneFill, 0xFBFDFF),
		("dropZoneBorder", Theme.dropZoneBorder, 0xCBD5E1),
		("fieldBorder", Theme.fieldBorder, 0xD1D5DB)
	]

	/// The translucent ones, with their light value and opacity. The two shadows were the text's color faded.
	private static let translucent: [(name: String, color: Color, light: UInt32, opacity: CGFloat)] = [
		("cardShadow", Theme.cardShadow, 0x111827, 0.08),
		("segmentShadow", Theme.segmentShadow, 0x111827, 0.12),
		("focusGlow", Theme.focusGlow, 0x4F46E5, 0.14),
		("disabledFieldFill", Theme.disabledFieldFill, 0xEFEFEF, 0.3)
	]

	/// The AppKit colors of the name field and the window.
	private static let appKit: [(name: String, color: NSColor, light: UInt32)] = [
		("placeholder", Theme.placeholder, 0x757575),
		("fieldText", Theme.fieldText, 0x111827),
		("windowBackground", Theme.windowBackground, 0xF8FAFC)
	]

	private static let kinds: [FileIconType.Kind] = [.word, .hwp, .pdf, .powerPoint, .sheet, .text, .image, .archive, .generic]

	/// The light tiles, as they were: fill and label of each kind.
	private static let lightTiles: [FileIconType.Kind: (fill: UInt32, label: UInt32)] = [
		.word: (0xEFF6FF, 0x2563EB), .hwp: (0xECFDF5, 0x059669), .pdf: (0xFEF2F2, 0xDC2626), .powerPoint: (0xFFF7ED, 0xEA580C),
		.sheet: (0xF0FDF4, 0x16A34A), .text: (0xF1F5F9, 0x111827), .image: (0xEEF2FF, 0x4F46E5), .archive: (0xFFFBEB, 0xF59E0B),
		.generic: (0xEEF2FF, 0x4F46E5)
	]

	@Test func theLightPaletteIsTheOneTheAppHadBeforeDarkMode() throws {
		for (name, color, light) in Self.opaque {
			#expect(hex(color, in: .aqua) == light, "\(name)")
			#expect(opacity(color, in: .aqua) == 1, "\(name)")
		}
		for (name, color, light, alpha) in Self.translucent {
			#expect(hex(color, in: .aqua) == light, "\(name)")
			#expect(abs(opacity(color, in: .aqua) - alpha) < 0.005, "\(name): \(opacity(color, in: .aqua))")
		}
		for (name, color, light) in Self.appKit {
			#expect(hex(color, in: .aqua) == light, "\(name)")
		}
		for kind in Self.kinds {
			let tile = Theme.tileColors(kind)
			let expected = try #require(Self.lightTiles[kind])
			#expect(hex(tile.fill, in: .aqua) == expected.fill && hex(tile.label, in: .aqua) == expected.label, "\(kind)")
		}
		// The high-contrast light appearance is light too.
		#expect(hex(Theme.background, in: .accessibilityHighContrastAqua) == 0xF8FAFC)
	}

	@Test func everyColorHasADarkValueOfItsOwn() {
		for (name, color, _) in Self.opaque {
			#expect(hex(color, in: .darkAqua) != hex(color, in: .aqua), "\(name)")
			#expect(opacity(color, in: .darkAqua) == 1, "\(name)")
		}
		for (name, color, _, _) in Self.translucent {
			#expect(hex(color, in: .darkAqua) != hex(color, in: .aqua), "\(name)")
			#expect(opacity(color, in: .darkAqua) < 1, "\(name)")
		}
		for (name, color, _) in Self.appKit {
			#expect(hex(color, in: .darkAqua) != hex(color, in: .aqua), "\(name)")
		}
		for kind in Self.kinds {
			let tile = Theme.tileColors(kind)
			#expect(hex(tile.fill, in: .darkAqua) != hex(tile.fill, in: .aqua), "\(kind)")
			#expect(hex(tile.label, in: .darkAqua) != hex(tile.label, in: .aqua), "\(kind)")
		}

		// The pairs that are one color: the window and the background behind the card, the field's text and the text.
		for appearance in [NSAppearance.Name.aqua, .darkAqua] {
			#expect(hex(Theme.windowBackground, in: appearance) == hex(Theme.background, in: appearance))
			#expect(hex(Theme.fieldText, in: appearance) == hex(Theme.text, in: appearance))
		}
		// Dark is dark: the window, the card and the field are deep; the text and the field's text are light.
		for color in [Theme.background, Theme.card, Theme.soft, Theme.dropZoneFill] {
			#expect(luminance(hex(color, in: .darkAqua)) < 0.05, "\(hex(color, in: .darkAqua))")
		}
		#expect(luminance(hex(Theme.text, in: .darkAqua)) > 0.85)
		#expect(luminance(hex(Theme.fieldText, in: .darkAqua)) > 0.85)
		// The same whichever dark appearance: high contrast and the vibrant one of a dark material.
		#expect(hex(Theme.background, in: .accessibilityHighContrastDarkAqua) == hex(Theme.background, in: .darkAqua))
		#expect(hex(Theme.background, in: .vibrantDark) == hex(Theme.background, in: .darkAqua))
		#expect(hex(Theme.background, in: .vibrantLight) == hex(Theme.background, in: .aqua))
	}

	/// WCAG AA under both appearances: 4.5 for the texts of 12 pt and up, 3 for the large or decorative ones.
	@Test func textReadsWellUnderBothAppearances() {
		for appearance in [NSAppearance.Name.aqua, .darkAqua] {
			func ratio(_ text: Color, on fill: Color) -> Double {
				contrastRatio(hex(text, in: appearance), hex(fill, in: appearance))
			}
			func expectBody(_ text: Color, on fill: Color, _ what: String) {
				#expect(ratio(text, on: fill) >= 4.5, "\(what) under \(appearance.rawValue): \(ratio(text, on: fill))")
			}

			// On the card: the names, the labels and the status line. On the background: the result box and the link
			// under the card.
			expectBody(Theme.text, on: Theme.card, "text on the card")
			expectBody(Theme.text, on: Theme.background, "text on the background")
			expectBody(Theme.muted, on: Theme.card, "muted text on the card")
			expectBody(Theme.muted, on: Theme.background, "muted text on the background")
			expectBody(Theme.primary, on: Theme.card, "the back button")
			expectBody(Theme.onPrimary, on: Theme.primary, "the text of NFC 사본 만들기")
			expectBody(Theme.success, on: Theme.card, "a success message")
			expectBody(Theme.error, on: Theme.card, "an error message")
			// The name field: its text and its placeholder on the card.
			expectBody(Color(nsColor: Theme.fieldText), on: Theme.card, "the typed name")
			expectBody(Color(nsColor: Theme.placeholder), on: Theme.card, "the placeholder")
			// The name switch (16 pt heavy, large text): the chosen half's text on its raised fill, the other on the track.
			#expect(ratio(Theme.primary, on: Theme.selectedSegment) >= 3, "\(appearance.rawValue): \(ratio(Theme.primary, on: Theme.selectedSegment))")
			#expect(ratio(Theme.muted, on: Theme.soft) >= 3, "\(appearance.rawValue): \(ratio(Theme.muted, on: Theme.soft))")
			// The drop zone's arrow (24 pt heavy) in its circle.
			#expect(ratio(Theme.primary, on: Theme.primarySoft) >= 3, "\(appearance.rawValue): \(ratio(Theme.primary, on: Theme.primarySoft))")
		}

		// The tiles' labels (shown when the icon's image is missing) on their tiles: the dark pairs are new and read as
		// large text. (The light pairs are the old app's; the archive's amber on cream is below 3 there and stays.)
		for kind in Self.kinds {
			let tile = Theme.tileColors(kind)
			let ratio = contrastRatio(hex(tile.label, in: .darkAqua), hex(tile.fill, in: .darkAqua))
			#expect(ratio >= 3, "\(kind): \(ratio)")
		}
	}

	@Test func theStatusLineHasTheColorOfItsTone() {
		#expect(Theme.statusColor(.success) == Theme.success)
		#expect(Theme.statusColor(.error) == Theme.error)
		#expect(Theme.statusColor(.info) == Theme.muted)
		#expect(Theme.statusColor(nil) == Theme.muted)
	}

	@Test func anAppearanceIsDarkByItsBestMatch() throws {
		for name in [NSAppearance.Name.aqua, .accessibilityHighContrastAqua, .vibrantLight, .accessibilityHighContrastVibrantLight] {
			#expect(try #require(NSAppearance(named: name)).isDark == false, "\(name.rawValue)")
		}
		for name in [NSAppearance.Name.darkAqua, .accessibilityHighContrastDarkAqua, .vibrantDark, .accessibilityHighContrastVibrantDark] {
			#expect(try #require(NSAppearance(named: name)).isDark == true, "\(name.rawValue)")
		}
	}
}
