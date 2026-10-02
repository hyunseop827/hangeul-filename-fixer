// The nine kinds of file the three name cards have an icon for, chosen by the file's extension.
import Foundation
import HangeulFilenameFixerCore

struct FileIconType: Sendable {
	/// Decides the colors of the tile (Theme.swift).
	enum Kind: Sendable {
		case word
		case hwp
		case pdf
		case powerPoint
		case sheet
		case text
		case image
		case archive
		case generic
	}

	let kind: Kind
	/// Lowercase, without the dot.
	let extensions: [String]
	/// Shown on the colored tile when the icon's image is missing.
	let label: String
	/// The tile's tooltip.
	let title: String
	/// Resources/FileIcons/<imageName>.pdf in the app bundle.
	let imageName: String

	static let known: [FileIconType] = [
		FileIconType(kind: .word, extensions: ["doc", "docx"], label: "DOC", title: String(localized: "Word 문서"), imageName: "word"),
		FileIconType(kind: .hwp, extensions: ["hwp", "hwpx"], label: "HWP", title: String(localized: "한글 문서"), imageName: "hwp"),
		FileIconType(kind: .pdf, extensions: ["pdf"], label: "PDF", title: String(localized: "PDF 문서"), imageName: "pdf"),
		FileIconType(kind: .powerPoint, extensions: ["ppt", "pptx"], label: "PPT", title: String(localized: "PowerPoint 문서"), imageName: "powerpoint"),
		FileIconType(kind: .sheet, extensions: ["xls", "xlsx", "csv"], label: "XLS", title: String(localized: "스프레드시트"), imageName: "excel"),
		FileIconType(kind: .text, extensions: ["txt", "md", "rtf"], label: "TXT", title: String(localized: "텍스트 문서"), imageName: "text"),
		FileIconType(
			kind: .image,
			extensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"],
			label: "IMG",
			title: String(localized: "이미지 파일"),
			imageName: "image"
		),
		FileIconType(kind: .archive, extensions: ["zip", "rar", "7z", "tar", "gz"], label: "ZIP", title: String(localized: "압축 파일"), imageName: "archive")
	]

	static let generic = FileIconType(kind: .generic, extensions: [], label: "FILE", title: String(localized: "일반 파일"), imageName: "generic")

	/// The icon for a file name: by what follows its last dot, whatever its case.
	static func forFileName(_ fileName: String) -> FileIconType {
		// Drop the dot the extension starts with. Scalars, as everywhere a name is taken apart.
		let fileExtension = String(splitFileName(fileName).extension.unicodeScalars.dropFirst()).lowercased()
		// Compared by scalars, like every name in this app (`==` on Strings also accepts a canonically equivalent spelling).
		return known.first { type in type.extensions.contains { hasSameScalars($0, fileExtension) } } ?? generic
	}
}
