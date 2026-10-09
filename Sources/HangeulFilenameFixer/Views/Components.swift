// The small parts the detail screen is built from.
import AppKit
import SwiftUI

/// The gray heading above a group ("선택된 파일", "출력 이름", "결과").
struct SectionLabel: View {
	private let title: String

	init(_ title: String) {
		self.title = title
	}

	var body: some View {
		Text(verbatim: title)
			.textLine(size: 12, weight: .black, color: Theme.muted, height: Theme.smallLine)
			.padding(.bottom, 8)
	}
}

/// One of the three boxes that show the file's name: icon, what the name is, the name, and a note.
struct FilenameCard: View {
	let icon: FileIconType
	let label: String
	let name: String
	let description: String?
	let identifier: String

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 11, style: .circular)

		HStack(alignment: .center, spacing: 12) {
			FileIconTile(icon: icon)

			VStack(alignment: .leading, spacing: 0) {
				Text(verbatim: label)
					.textLine(size: 12, weight: .bold, color: Theme.muted, height: Theme.smallLine)
					.padding(.bottom, 1)

				Text(verbatim: name)
					.textLine(size: 16, weight: .bold, color: Theme.text, height: Theme.nameLine)
					.truncationMode(.tail)
					.help(name)
					.accessibilityIdentifier(identifier)

				if let description {
					Text(verbatim: description)
						.textLine(size: 11, weight: .regular, color: Theme.muted, height: 13.75)
						.padding(.top, 2)
				}
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		// 9 and 10 pt inside the 1 pt border.
		.padding(.vertical, 10)
		.padding(.horizontal, 11)
		.background(shape.fill(Theme.card))
		.overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
	}
}

/// The colored tile with the file type's icon. Without the image (no app bundle around the program) it shows the
/// type's short label instead.
struct FileIconTile: View {
	let icon: FileIconType

	var body: some View {
		let colors = Theme.tileColors(icon.kind)

		ZStack {
			RoundedRectangle(cornerRadius: 9, style: .circular)
				.fill(colors.fill)

			if let image = FileIconImages.image(named: icon.imageName) {
				Image(nsImage: image)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.frame(width: 34, height: 34)
			} else {
				Text(verbatim: icon.label)
					.font(Theme.font(size: 10, weight: .black))
					.foregroundColor(colors.label)
			}
		}
		.frame(width: 36, height: 36)
		.help(icon.title)
		.accessibilityHidden(true)
	}
}

/// The icons of Resources/FileIcons (vector PDFs), read from the app bundle once each.
@MainActor
enum FileIconImages {
	private static var loaded: [String: NSImage?] = [:]

	static func image(named name: String) -> NSImage? {
		if let known = loaded[name] {
			return known
		}

		let image = Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "FileIcons").flatMap(NSImage.init(contentsOf:))
		loaded[name] = image
		return image
	}
}

struct FlowArrow: View {
	var body: some View {
		Text(verbatim: "↓")
			.textLine(size: 18, weight: .regular, color: Theme.muted, height: 18)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 3)
			.accessibilityHidden(true)
	}
}

/// A button that is drawn entirely by its label and does not change while it is pressed. One that cannot be pressed is
/// faded as a whole, and the pointer says which of the two it is over.
struct FlatButtonStyle: ButtonStyle {
	func makeBody(configuration: Configuration) -> some View {
		FlatButtonBody(label: configuration.label)
	}

	private struct FlatButtonBody: View {
		let label: Configuration.Label
		@Environment(\.isEnabled) private var isEnabled

		var body: some View {
			// As one picture: faded part by part, the text would be faded against its own faded background.
			label
				.compositingGroup()
				.opacity(isEnabled ? 1 : Theme.disabledOpacity)
				.pointer(isEnabled ? .pointingHand : .operationNotAllowed)
		}
	}
}

/// One half of the "기존 이름 유지 / 이름 바꾸기" switch.
struct NameModeButton: View {
	let title: String
	let isSelected: Bool
	let identifier: String
	let action: () -> Void

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 8, style: .circular)

		Button(action: action) {
			Text(verbatim: title)
				.font(Theme.font(size: 16, weight: .heavy))
				.foregroundColor(isSelected ? Theme.primary : Theme.muted)
				.lineLimit(1)
				.frame(maxWidth: .infinity, minHeight: 35)
				.background(
					shape
						.fill(isSelected ? Theme.selectedSegment : Color.clear)
						.shadow(color: isSelected ? Theme.segmentShadow : Color.clear, radius: 2, x: 0, y: 1)
				)
				.contentShape(shape)
		}
		.buttonStyle(FlatButtonStyle())
		.accessibilityIdentifier(identifier)
		.accessibilityAddTraits(isSelected ? .isSelected : [])
		.accessibilityValue(isSelected ? String(localized: "선택됨") : String(localized: "선택 안 됨"))
	}
}

/// "저장 위치 변경", "NFC 사본 만들기", "Finder에서 보기".
struct ActionButton: View {
	enum Kind {
		/// Filled with the app's color.
		case primary
		/// The card's color with a thin border.
		case secondary
	}

	static let height: CGFloat = 37

	let title: String
	let kind: Kind
	let identifier: String
	let action: () -> Void

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 10, style: .circular)

		Button(action: action) {
			Text(verbatim: title)
				.font(Theme.font(size: 12, weight: .heavy))
				.foregroundColor(kind == .primary ? Theme.onPrimary : Theme.text)
				.lineLimit(1)
				.truncationMode(.tail)
				.padding(.horizontal, kind == .primary ? 10 : 11)
				.frame(maxWidth: .infinity, minHeight: Self.height)
				.background(shape.fill(kind == .primary ? Theme.primary : Theme.card))
				.overlay(shape.strokeBorder(kind == .primary ? Color.clear : Theme.line, lineWidth: 1))
				.contentShape(shape)
		}
		.buttonStyle(FlatButtonStyle())
		.accessibilityIdentifier(identifier)
	}
}
