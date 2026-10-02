// The screen for the selected file: its name three ways, the name of the copy, where it goes, and the two actions.
import SwiftUI

struct DetailScreen: View {
	@ObservedObject var model: AppModel
	@StateObject private var nameField = NameFieldHandle()
	@State private var nameFieldHasFocus = false

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			backButton

			SectionLabel(String(localized: "선택된 파일"))

			FilenameCard(
				icon: model.fileIcon,
				label: String(localized: "macOS Finder에서 보이는 이름"),
				name: model.finderDisplayName,
				description: String(localized: "macOS 현재 원본"),
				identifier: "finderName"
			)
			FlowArrow()
			FilenameCard(
				icon: model.fileIcon,
				label: String(localized: "Windows에서 보일 수 있는 이름"),
				name: model.decomposedName,
				description: nil,
				identifier: "decomposedName"
			)
			FlowArrow()
			FilenameCard(
				icon: model.fileIcon,
				label: String(localized: "변환 후 Windows 호환 이름"),
				name: model.windowsCompatibleName,
				description: String(localized: "변환 후 Windows 예상"),
				identifier: "windowsCompatibleName"
			)

			SectionLabel(String(localized: "출력 이름"))
				.padding(.top, 14)
			nameModeControl
				.padding(.bottom, 10)

			renameField
				.padding(.bottom, 10)

			SectionLabel(String(localized: "결과"))
			resultBox
				.padding(.bottom, 10)

			actions
				.padding(.bottom, 10)

			resultActions
		}
		.padding(EdgeInsets(top: 18, leading: 18, bottom: 16, trailing: 18))
	}

	// MARK: Parts

	private var backButton: some View {
		Button {
			model.clearFile()
		} label: {
			Text(verbatim: String(localized: "← 다른 파일 선택"))
				.textLine(size: 12, weight: .black, color: Theme.primary, height: Theme.smallLine)
				.contentShape(Rectangle())
		}
		.buttonStyle(FlatButtonStyle())
		.disabled(!model.canGoBack)
		.accessibilityIdentifier("backButton")
		// The button stands on a line of the larger text size, with space below it.
		.padding(.top, 3.5)
		.padding(.bottom, 14.5)
	}

	private var nameModeControl: some View {
		HStack(spacing: 2) {
			NameModeButton(
				title: String(localized: "기존 이름 유지"),
				isSelected: model.nameMode == .keep,
				identifier: "keepNameButton"
			) {
				model.changeNameMode(.keep)
			}
			NameModeButton(
				title: String(localized: "이름 바꾸기"),
				isSelected: model.nameMode == .rename,
				identifier: "renameButton"
			) {
				model.changeNameMode(.rename)
			}
		}
		.disabled(!model.canChangeNameMode)
		.padding(3)
		.background(RoundedRectangle(cornerRadius: 10, style: .circular).fill(Theme.soft))
	}

	private var renameField: some View {
		let shape = RoundedRectangle(cornerRadius: 10, style: .circular)
		let isEnabled = model.isNameFieldEnabled

		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: String(localized: "새 파일명"))
				.textLine(size: 12, weight: .black, color: Theme.muted, height: Theme.smallLine)
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(Rectangle())
				// The label belongs to the field: a click on it puts the cursor there.
				.onTapGesture { nameField.focus() }
				// The field carries this text as its own label.
				.accessibilityHidden(true)

			NameField(
				text: model.nameFieldText,
				placeholder: String(localized: "확장자명을 제외하고 입력해주세요"),
				isEnabled: isEnabled,
				handle: nameField,
				onChange: { model.setBaseName($0) },
				// Later, not now: the field may report while the views are being updated.
				onFocusChange: { hasFocus in Task { @MainActor in nameFieldHasFocus = hasFocus } }
			)
			// SwiftUI switches a hosted control on and off by itself, from what it knows as "disabled" (it does so again
			// whenever it describes the screen to VoiceOver), so it has to know.
			.disabled(!isEnabled)
			// The text starts 11 pt inside the border (the field's cell adds nothing of its own).
			.padding(.horizontal, 11)
			.frame(height: 34)
			.padding(1)
			.background(shape.fill(isEnabled ? Theme.card : Theme.disabledFieldFill))
			.overlay(shape.strokeBorder(nameFieldHasFocus && isEnabled ? Theme.primary : Theme.fieldBorder, lineWidth: 1))
			.opacity(isEnabled ? 1 : Theme.disabledOpacity)
			// Switched on, the field shows its own text cursor.
			.pointer(isEnabled ? nil : .operationNotAllowed)
			.background(
				RoundedRectangle(cornerRadius: 13, style: .circular)
					.fill(nameFieldHasFocus && isEnabled ? Theme.focusGlow : Color.clear)
					.padding(-3)
			)
		}
	}

	private var resultBox: some View {
		let shape = RoundedRectangle(cornerRadius: 11, style: .circular)
		let shownName = model.resultName

		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: model.resultLabel)
				.textLine(size: 12, weight: .regular, color: Theme.muted, height: Theme.smallLine)
				.accessibilityIdentifier("resultLabel")

			if model.isShowingFileName {
				Text(verbatim: shownName)
					.textLine(size: 16, weight: .bold, color: Theme.text, height: Theme.nameLine)
					.truncationMode(.tail)
					.help(shownName)
					.accessibilityIdentifier("resultName")
			} else {
				// Instructions in place of a file name may wrap instead of being cut off. Spaced so that one line is as
				// tall as a file name's row, and the box does not move when a name takes the message's place.
				Text(verbatim: shownName)
					.font(.system(size: 16, weight: .bold))
					.foregroundColor(Theme.text)
					.lineSpacing(1.5)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.vertical, 0.75)
					.help(shownName)
					.accessibilityIdentifier("resultName")
			}

			Text(verbatim: model.outputDirectory ?? "")
				.font(.system(size: 12))
				.foregroundColor(Theme.muted)
				.fixedSize(horizontal: false, vertical: true)
				.help(model.outputDirectory ?? "")
				.accessibilityIdentifier("outputDirectory")

			if let hint = model.resultHint {
				Text(verbatim: hint)
					.font(.system(size: 11))
					.foregroundColor(Theme.muted)
					.lineSpacing(1)
					.fixedSize(horizontal: false, vertical: true)
					.padding(.top, 2.5)
					.padding(.bottom, 0.5)
					.accessibilityIdentifier("resultHint")
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(11)
		.background(shape.fill(Theme.background))
		.overlay(shape.strokeBorder(Theme.fieldBorder, lineWidth: 1))
	}

	private var actions: some View {
		// Two columns, 0.84 : 1.36, with 8 pt between them.
		GeometryReader { row in
			let unit = max(row.size.width - 8, 0) / (0.84 + 1.36)

			HStack(spacing: 8) {
				ActionButton(title: String(localized: "저장 위치 변경"), kind: .secondary, identifier: "outputDirectoryButton") {
					model.selectOutputDirectory()
				}
				.disabled(!model.canChangeOutputDirectory)
				.frame(width: unit * 0.84)

				ActionButton(title: String(localized: "NFC 사본 만들기"), kind: .primary, identifier: "convertButton") {
					model.convertFile()
				}
				.disabled(!model.canConvert)
				.frame(width: unit * 1.36)
			}
		}
		.frame(height: ActionButton.height)
	}

	private var resultActions: some View {
		HStack(alignment: .center, spacing: 10) {
			Text(verbatim: model.status?.message ?? "")
				.font(.system(size: 12))
				.foregroundColor(Theme.statusColor(model.status?.tone))
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: .infinity, alignment: .leading)
				.accessibilityIdentifier("status")

			ActionButton(title: String(localized: "Finder에서 보기"), kind: .secondary, identifier: "revealButton") {
				model.revealCreatedCopy()
			}
			.disabled(!model.canReveal)
			.fixedSize(horizontal: true, vertical: false)
		}
		.frame(minHeight: 34)
	}
}
