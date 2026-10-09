// The window's content: one card on the background (light or dark with the system; Theme), and under it a row with the
// "업데이트 확인" link. The card is as tall as what it holds, at least `Theme.cardMinHeight`, and the window makes itself
// as tall as the card and the row need (MainWindowController). Only where the screen is too small for that is the card
// cut off at the window's height; what does not fit then scrolls inside it, and the row stays under the card.
import SwiftUI

struct RootView: View {
	@ObservedObject var model: AppModel
	/// What the link under the card asks and sends to: the app's updater, or in the unit tests one with a stand-in.
	@ObservedObject var updater: AppUpdater = .shared
	/// Called with the height of what the card holds whenever it has changed: the window fits itself to it. Called
	/// while SwiftUI lays the views out (on the main thread), so the receiver acts on it afterwards.
	var onContentHeightChange: @Sendable (CGFloat) -> Void = { _ in }
	/// The height of what the card holds, measured after layout.
	@State private var contentHeight: CGFloat = 0

	var body: some View {
		GeometryReader { window in
			let width = min(max(window.size.width - 2 * Theme.windowPaddingSide, 0), Theme.cardMaxWidth)
			let roomForCard = window.size.height - Theme.windowPaddingTop - Theme.footerHeight - Theme.windowPaddingBottom
			let height = min(WindowFit.cardHeight(forContent: contentHeight), max(roomForCard, Theme.cardMinHeight))

			VStack(spacing: 0) {
				card
					.frame(width: width, height: height)

				footer
					.frame(width: width, height: Theme.footerHeight, alignment: .bottomTrailing)
			}
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
		.background(shape.fill(Theme.card).shadow(color: Theme.cardShadow, radius: 20, x: 0, y: 18))
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

	/// Under the card, at its right edge, on both screens: the update check as a text link, the same check as
	/// 앱 메뉴 > "업데이트 확인…" (AppUpdater). Its tooltip names this build's version. Like the menu item it is always there
	/// and disabled without an updater, and while Sparkle's window is already checking.
	private var footer: some View {
		FooterLink(title: AppUpdater.linkName, help: AppUpdater.help(enabled: updater.canCheck), identifier: "checkForUpdates") {
			updater.checkForUpdates()
		}
		.disabled(!updater.canCheck)
	}
}

/// A text link: the small gray text, which turns dark and underlined under the pointer. Still a button for VoiceOver and
/// the keyboard. One that cannot be used is faded and gets the "not allowed" pointer like the other buttons
/// (FlatButtonStyle), and stays as it is under the pointer, so it does not look like something to click.
private struct FooterLink: View {
	let title: String
	let help: String
	let identifier: String
	let action: () -> Void
	@Environment(\.isEnabled) private var isEnabled
	@State private var hovering = false

	var body: some View {
		let highlighted = hovering && isEnabled

		Button(action: action) {
			Text(verbatim: title)
				.underline(highlighted)
				.textLine(size: 12, weight: .regular, color: highlighted ? Theme.text : Theme.muted, height: Theme.smallLine)
				.contentShape(Rectangle())
		}
		.buttonStyle(FlatButtonStyle())
		.onHover { hovering = $0 }
		.help(help)
		.accessibilityIdentifier(identifier)
	}
}

private struct ContentHeightKey: PreferenceKey {
	static let defaultValue: CGFloat = 0

	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}
