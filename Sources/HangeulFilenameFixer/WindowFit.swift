// The size of the window: always as tall as the card of the current screen needs, so there is no empty band below the
// card. Compact on the first screen, taller once a file is selected. The user can change the width only.
//
// Plain arithmetic on rectangles (no window needed), in AppKit's coordinates: the y axis points up, so a window that
// keeps its top edge and grows downward gets a smaller `origin.y`.
import CoreGraphics

enum WindowFit {
	/// The width of a new window, and the narrowest the user can make it.
	static let initialWidth: CGFloat = 470
	static let minimumWidth: CGFloat = 440

	/// The height of the card for what it holds (`contentHeight`, measured inside the border): never less than the
	/// card's smallest height.
	static func cardHeight(forContent contentHeight: CGFloat) -> CGFloat {
		max(contentHeight + 2 * Theme.cardBorder, Theme.cardMinHeight)
	}

	/// The height of the window's content (below the title bar) that shows the whole card with the space above it, the
	/// row with the link under it and the space below that, in whole points.
	static func contentHeight(forCardContent cardContentHeight: CGFloat) -> CGFloat {
		(Theme.windowPaddingTop + cardHeight(forContent: cardContentHeight) + Theme.footerHeight + Theme.windowPaddingBottom).rounded(.up)
	}

	/// The window's frame once it is `height` tall (title bar included). The top-left corner stays where it is and the
	/// window grows or shrinks at its bottom edge. On a screen (`visible` is the part of it that is free of the menu bar
	/// and the Dock) the window is at most as tall as that area, where the card then scrolls inside, and it is moved up
	/// as far as needed to stay inside it. The width and the horizontal position are the user's and are not touched.
	static func frame(_ frame: CGRect, withHeight height: CGFloat, in visible: CGRect?) -> CGRect {
		var fitted = frame
		fitted.size.height = min(height, visible?.height ?? height)
		fitted.origin.y = frame.maxY - fitted.height

		if let visible {
			if fitted.minY < visible.minY {
				fitted.origin.y = visible.minY
			}
			if fitted.maxY > visible.maxY {
				fitted.origin.y = visible.maxY - fitted.height
			}
		}

		return fitted
	}

	/// The frame a zoom ("확대/축소") gives the window: as wide as the card can use (it stops growing at
	/// `Theme.cardMaxWidth`), within `visible`; the height stays the content's.
	static func zoomedFrame(_ frame: CGRect, in visible: CGRect) -> CGRect {
		var zoomed = frame
		zoomed.size.width = min(Theme.cardMaxWidth + 2 * Theme.windowPaddingSide, visible.width)
		zoomed.origin.x = min(max(frame.minX, visible.minX), visible.maxX - zoomed.width)
		return zoomed
	}
}
