// The window's content: one white card on the light background. The card is as tall as what it holds, at least
// `Theme.cardMinHeight`, and the window makes itself as tall as the card needs (MainWindowController). Only where the
// screen is too small for that is the card cut off at the window's height; what does not fit then scrolls inside it.
import SwiftUI

struct RootView: View {
	@ObservedObject var model: AppModel
	/// Called with the height of what the card holds whenever it has changed: the window fits itself to it. Called
	/// while SwiftUI lays the views out (on the main thread), so the receiver acts on it afterwards.
	var onContentHeightChange: @Sendable (CGFloat) -> Void = { _ in }
	/// The height of what the card holds, measured after layout.
	@State private var contentHeight: CGFloat = 0

	var body: some View {
		GeometryReader { window in
			let width = min(max(window.size.width - 2 * Theme.windowPaddingSide, 0), Theme.cardMaxWidth)
			let roomForCard = window.size.height - Theme.windowPaddingTop - Theme.windowPaddingBottom
			let height = min(WindowFit.cardHeight(forContent: contentHeight), max(roomForCard, Theme.cardMinHeight))

			card
				.frame(width: width, height: height)
				.padding(.top, Theme.windowPaddingTop)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		}
		.background(Theme.background)
	}

	private var card: some View {
		let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .circular)

		return ScrollView(.vertical) {
			content
				.background(
					GeometryReader { content in
						Color.clear.preference(key: ContentHeightKey.self, value: content.size.height)
					}
				)
		}
		.onPreferenceChange(ContentHeightKey.self) { height in
			contentHeight = height
			onContentHeightChange(height)
		}
		// Inside the border.
		.padding(Theme.cardBorder)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.background(Theme.card)
		.clipShape(shape)
		.overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
		// Under the clipped card, so the shadow itself is not clipped.
		.background(shape.fill(Theme.card).shadow(color: Theme.text.opacity(0.08), radius: 20, x: 0, y: 18))
	}

	@ViewBuilder private var content: some View {
		if model.sourcePath == nil {
			VStack(spacing: 0) {
				DropZone(model: model)
					.padding(16)

				Rectangle()
					.fill(Theme.line)
					.frame(height: 1)

				Text(verbatim: String(localized: "분리된 한글 파일명을 Windows 호환 이름으로 정리합니다."))
					.textLine(size: 12, weight: .regular, color: Theme.muted, height: Theme.smallLine)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 13)
					.padding(.horizontal, 16)
					.accessibilityIdentifier("footer")
			}
		} else {
			DetailScreen(model: model)
		}
	}
}

private struct ContentHeightKey: PreferenceKey {
	static let defaultValue: CGFloat = 0

	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}
