// The app's texts: Resources/ko.lproj/Localizable.strings, keyed by the Korean text itself.
//
// (a) Every text the app shows is looked up in that table and has an entry there. "Every text" is what the Swift
//     compiler extracts from the app's sources (`-emit-localized-strings`, the extraction Xcode runs for a string
//     catalog): each `String(localized:)`. And every string literal with Hangul in it is one of those extracted
//     texts, so no Korean text can reach the screen without going through the table. A literal without Hangul that
//     is handed straight to something that shows text (`Text(verbatim:)`, a title, a label, a tooltip, …) must be
//     one of the listed symbols and file-type abbreviations ("⇧", "↓", "DOC", …), so no English text gets on the
//     screen that way. What this cannot see: a text that reaches the screen through a variable or is put together
//     while the app runs.
// (b) Nothing in the table is unused: every entry is an extracted text or one of the Core's messages, and every
//     message of the Core has its entry. Every Korean literal in the Core's sources is one of those messages.
// (c) The file parses, no key is written twice, every value repeats its key, and everything is saved precomposed
//     (NFC) — the table, and the sources whose literals are the keys.
// (d) The wording is the old app's, word for word: every text is written out here once more, by the source file it
//     stands in and in its order there (`wording`).
import Foundation
import Testing
@testable import HangeulFilenameFixer
@testable import HangeulFilenameFixerCore

@Suite struct LocalizationTests {
	private static let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
	private static let resources = repository.appendingPathComponent("Resources")
	private static let appSources = repository.appendingPathComponent("Sources/HangeulFilenameFixer")
	private static let coreSources = repository.appendingPathComponent("Sources/HangeulFilenameFixerCore")
	private static let tableFile = resources.appendingPathComponent("ko.lproj/Localizable.strings")

	// MARK: The table

	static func table() throws -> [String: String] {
		let data = try Data(contentsOf: tableFile)
		return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
	}

	static func hasHangul(_ text: String) -> Bool {
		text.unicodeScalars.contains { (0x1100...0x11FF).contains($0.value) || (0x3130...0x318F).contains($0.value) || (0xAC00...0xD7A3).contains($0.value) }
	}

	private static func scalarsEqual(_ first: String, _ second: String) -> Bool {
		first.unicodeScalars.elementsEqual(second.unicodeScalars)
	}

	@Test func tableParsesAndEveryValueRepeatsItsKey() throws {
		let table = try Self.table()
		#expect(table.count > 60)

		for (key, value) in table {
			// By scalars: with `==` a value saved decomposed would pass as equal to its precomposed key.
			#expect(Self.scalarsEqual(key, value), "\(key) = \(value)")
			#expect(!key.isEmpty)
			#expect(Self.hasHangul(key), "not a Korean text: \(key)")
			#expect(!key.contains("%"), "a format specifier in \(key): this table holds plain texts only")
		}

		// The parser keeps one of two entries with the same key without a word; count the lines as well.
		let text = try String(contentsOf: Self.tableFile, encoding: .utf8)
		let entryLines = text.split(separator: "\n", omittingEmptySubsequences: true).filter { $0.hasPrefix("\"") }
		#expect(entryLines.count == table.count, "an entry is written twice, or an entry spans several lines")
		for line in entryLines {
			#expect(line.hasSuffix("\";"), "\(line)")
		}
	}

	@Test func tableAndSourcesAreSavedPrecomposed() throws {
		// The key is the literal in the source and the lookup compares bytes: a table saved decomposed (some editors and
		// file syncs do that) would silently stop matching. `isNFCName` is the Core's scalar-wise test.
		let text = try String(contentsOf: Self.tableFile, encoding: .utf8)
		#expect(isNFCName(text), "Resources/ko.lproj/Localizable.strings is not saved in NFC")
		for (key, value) in try Self.table() {
			#expect(isNFCName(key) && isNFCName(value), "\(key)")
		}

		let infoStrings = try String(contentsOf: Self.resources.appendingPathComponent("ko.lproj/InfoPlist.strings"), encoding: .utf8)
		#expect(isNFCName(infoStrings), "Resources/ko.lproj/InfoPlist.strings is not saved in NFC")

		let sources = try Self.swiftFiles(in: Self.appSources)
		#expect(sources.count >= 8)
		for file in sources {
			let source = try String(contentsOf: file, encoding: .utf8)
			#expect(isNFCName(source), "\(file.lastPathComponent) is not saved in NFC")
		}
	}

	/// The scripts name the bundle: the app is built as `한글 파일명 정리기.app` with the spelling build-app.sh has, and
	/// make-dmg.sh, verify-dmg.sh and the workflows look for it under the spelling they have. Saved decomposed, a
	/// script would build or expect the bundle under the other spelling.
	@Test func theAppNameInScriptsAndWorkflowsIsPrecomposed() throws {
		let appName = "한글 파일명 정리기"
		#expect(isNFCName(appName))
		#expect(Array(appName.utf8).count == 26, "eight precomposed syllables and two spaces")

		let fileManager = FileManager.default
		var checked = 0
		for folder in ["scripts", ".github/workflows", ".github"] {
			let url = Self.repository.appendingPathComponent(folder)
			for name in try fileManager.contentsOfDirectory(atPath: url.path).sorted() where !name.hasPrefix(".") {
				let file = url.appendingPathComponent(name)
				var isDirectory: ObjCBool = false
				guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
					continue
				}

				let text = try String(contentsOf: file, encoding: .utf8)
				#expect(isNFCName(text), "\(folder)/\(name) is not saved in NFC")
				checked += 1
			}
		}
		#expect(checked >= 11, "\(checked)")
		for path in ["Package.swift", "Resources/Info.plist"] {
			#expect(isNFCName(try String(contentsOf: Self.repository.appendingPathComponent(path), encoding: .utf8)), "\(path) is not saved in NFC")
		}

		// Where the name must stand, byte for byte.
		for path in ["scripts/build-app.sh", "scripts/make-dmg.sh", "scripts/verify-dmg.sh", ".github/workflows/ci.yml", "Resources/Info.plist"] {
			let data = try Data(contentsOf: Self.repository.appendingPathComponent(path))
			#expect(data.range(of: Data(appName.utf8)) != nil, "\(path) does not name the app (precomposed)")
		}
	}

	@Test func everyMessageOfTheCoreIsInTheTable() throws {
		let table = try Self.table()
		#expect(Message.all.count == 11)
		for message in Message.all {
			#expect(table[message] != nil, "no entry: \(message)")
			#expect(table.keys.contains { Self.scalarsEqual($0, message) }, "the entry is spelled differently: \(message)")
		}
		#expect(Self.scalarsEqual(notRegularFileMessage, Message.notRegularFile), "outside the app bundle a text is its own key")
	}

	/// Korean is the app's only language: that is what makes the texts macOS supplies (panels, the menu items AppKit
	/// adds) Korean as well, whatever the system language is.
	@Test func koreanIsTheOnlyLanguage() throws {
		let data = try Data(contentsOf: Self.resources.appendingPathComponent("Info.plist"))
		let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
		#expect(plist["CFBundleDevelopmentRegion"] as? String == "ko")
		#expect(plist["CFBundleLocalizations"] as? [String] == ["ko"])

		let languages = try FileManager.default.contentsOfDirectory(atPath: Self.resources.path).filter { $0.hasSuffix(".lproj") }
		#expect(languages == ["ko.lproj"])
	}

	// MARK: (a), (b): what the compiler extracts from the sources

	struct Extracted: Sendable {
		struct Entry: Sendable {
			var key: String
			var line: Int?
			var column: Int?
		}

		/// By the source file's last path component.
		var entries: [String: [Entry]] = [:]

		var keys: [String] {
			entries.values.flatMap { $0.map(\.key) }
		}
	}

	/// The extraction compiles the app once more; the tests that need it share one run.
	private static let extraction = Result { try extract() }

	struct Failure: Error, CustomStringConvertible {
		var description: String

		init(_ description: String) {
			self.description = description
		}
	}

	/// Compiles the app's sources once more (unoptimized, like `swift test`) with `-emit-localized-strings` into a
	/// temporary folder, against the Core module this test was built with, and reads the `.stringsdata` files.
	static func extract() throws -> Extracted {
		final class Marker {}
		let products = Bundle(for: Marker.self).bundleURL.deletingLastPathComponent()
		let fileManager = FileManager.default
		guard let modules = [products, products.appendingPathComponent("Modules")].first(where: {
			fileManager.fileExists(atPath: $0.appendingPathComponent("HangeulFilenameFixerCore.swiftmodule").path)
		}) else {
			throw Failure("HangeulFilenameFixerCore.swiftmodule not found next to the test bundle (\(products.path))")
		}

		let out = URL(fileURLWithPath: TestRun.root).appendingPathComponent("l10n-\(UUID().uuidString)")
		try fileManager.createDirectory(at: out, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: out) }

		#if arch(arm64)
		let architecture = "arm64"
		#else
		let architecture = "x86_64"
		#endif
		let sdk = try run(["--show-sdk-path"], in: out).trimmingCharacters(in: .whitespacesAndNewlines)
		var arguments = [
			"swiftc", "-c", "-parse-as-library", "-swift-version", "6", "-module-name", "HangeulFilenameFixer",
			"-target", "\(architecture)-apple-macosx12.0", "-sdk", sdk,
			"-I", modules.path, "-wmo", "-Onone", "-o", out.appendingPathComponent("app.o").path,
			"-emit-localized-strings", "-emit-localized-strings-path", out.path
		]
		// Command Line Tools only (scripts/toolchain.sh): SwiftUI's macro plugin comes from Xcode.
		let developer = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? ""
		if developer.hasPrefix("/Library/Developer/CommandLineTools") {
			for plugins in [
				"/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins",
				developer + "/usr/lib/swift/host/plugins/testing"
			] where fileManager.fileExists(atPath: plugins) {
				arguments += ["-plugin-path", plugins]
			}
		}
		_ = try run(arguments + (try swiftFiles(in: appSources).map(\.path)), in: out)

		var extracted = Extracted()
		for file in try fileManager.contentsOfDirectory(at: out, includingPropertiesForKeys: nil) where file.pathExtension == "stringsdata" {
			let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
			let source = URL(fileURLWithPath: json["source"] as? String ?? file.deletingPathExtension().lastPathComponent + ".swift").lastPathComponent
			let tables = json["tables"] as? [String: [[String: Any]]] ?? [:]
			#expect(Set(tables.keys).isSubset(of: ["Localizable"]), "\(source): other tables \(tables.keys.sorted())")
			for item in tables["Localizable"] ?? [] {
				let location = item["location"] as? [String: Int]
				extracted.entries[source, default: []].append(
					Extracted.Entry(key: item["key"] as? String ?? "", line: location?["startingLine"], column: location?["startingColumn"])
				)
			}
		}
		return extracted
	}

	/// Runs `xcrun <arguments>` (the toolchain scripts/test.sh chose, through DEVELOPER_DIR) and returns its output.
	/// Output and errors go to files in `folder`, so a long list of diagnostics cannot fill a pipe and stall the tool.
	static func run(_ arguments: [String], in folder: URL) throws -> String {
		let outputFile = folder.appendingPathComponent("stdout-\(UUID().uuidString).txt")
		let errorFile = folder.appendingPathComponent("stderr-\(UUID().uuidString).txt")
		for file in [outputFile, errorFile] {
			FileManager.default.createFile(atPath: file.path, contents: nil)
		}
		defer {
			try? FileManager.default.removeItem(at: outputFile)
			try? FileManager.default.removeItem(at: errorFile)
		}

		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
		process.arguments = arguments
		process.standardOutput = try FileHandle(forWritingTo: outputFile)
		process.standardError = try FileHandle(forWritingTo: errorFile)
		try process.run()
		process.waitUntilExit()

		guard process.terminationStatus == 0 else {
			let errors = (try? String(contentsOf: errorFile, encoding: .utf8)) ?? ""
			throw Failure(
				"xcrun \(arguments.prefix(2).joined(separator: " ")) … failed (\(process.terminationStatus)): "
					+ errors.split(separator: "\n").filter { $0.contains("error") }.prefix(10).joined(separator: "\n")
			)
		}

		return try String(contentsOf: outputFile, encoding: .utf8)
	}

	static func swiftFiles(in folder: URL) throws -> [URL] {
		let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []
		return items.filter { $0.pathExtension == "swift" }.sorted { $0.path < $1.path }
	}

	@Test(.timeLimit(.minutes(10))) func everyTextOfTheAppIsInTheTableAndNothingElseIs() throws {
		let extracted = try Self.extraction.get()
		let table = try Self.table()
		let extractedKeys = extracted.keys
		#expect(extractedKeys.count > 50)

		// (a) Every extracted text has its entry, spelled the same.
		for key in extractedKeys {
			#expect(table.keys.contains { Self.scalarsEqual($0, key) }, "no entry in ko.lproj/Localizable.strings: \(key)")
			#expect(!key.contains("%"), "an interpolated text (\(key)): this table holds plain texts only")
		}

		// (b) Every entry is used: by the app, or by the Core.
		for key in table.keys.sorted() {
			let isUsed = extractedKeys.contains { Self.scalarsEqual($0, key) } || Message.all.contains { Self.scalarsEqual($0, key) }
			#expect(isUsed, "unused text in ko.lproj/Localizable.strings: \(key)")
		}

		// (a) Every Hangul literal of the app is one of the extracted (looked-up) texts, at the place the compiler
		// reports.
		var checked = 0
		for file in try Self.swiftFiles(in: Self.appSources) {
			let source = try String(contentsOf: file, encoding: .utf8)
			let entries = extracted.entries[file.lastPathComponent] ?? []
			let located = Set(entries.compactMap { entry in entry.line.flatMap { line in entry.column.map { "\(line):\($0)" } } })
			let unlocated = entries.filter { $0.line == nil }.map(\.key)
			for literal in SwiftLiterals.scan(source) where Self.hasHangul(literal.text) && !literal.exempt {
				checked += 1
				let found = located.contains("\(literal.line):\(literal.column)")
					|| (!literal.interpolated && unlocated.contains { Self.scalarsEqual($0, literal.text) })
				#expect(found, "\(file.lastPathComponent):\(literal.line):\(literal.column): Korean text that is not looked up in the table: \(literal.text)")
			}
		}
		#expect(checked > 50)
	}

	// MARK: (d): the wording

	/// Every text of the app, by the source file it stands in and in its order there. Taken from the old app
	/// (src/App.tsx and electron/main.ts of v1.1.0), plus what only a native app has: the menu bar and what VoiceOver says.
	/// A text that is reworded, moved to another control's place or swapped with its neighbor fails here; when that
	/// was the intention, this list is the place to say so.
	static let wording: [(file: String, texts: [String])] = [
		("AppModel.swift", [
			"생성된 사본", "생성될 사본 이름",
			"새 파일명을 입력하세요.",
			"저장 위치를 확인하는 중입니다.",
			"이미 Windows 호환 이름이라 사본을 만들지 않아도 됩니다.",
			"같은 이름의 파일(원본 포함)이 있어 번호가 붙습니다. 원래 이름 그대로 받으려면 저장 위치를 변경하세요.",
			"파일 하나만 처리합니다. 첫 번째 파일만 선택했습니다.",
			"사본을 만드는 중입니다…",
			"완료되었습니다. 저장된 파일명이 NFC인지 확인했습니다."
		]),
		// The tooltips of the nine file icons.
		("FileIconType.swift", ["Word 문서", "한글 문서", "PDF 문서", "PowerPoint 문서", "스프레드시트", "텍스트 문서", "이미지 파일", "압축 파일", "일반 파일"]),
		// The menu bar (not in the old app, whose menu bar was Electron's English one).
		("MainMenu.swift", [
			"한글 파일명 정리기", "한글 파일명 정리기에 관하여", "서비스", "한글 파일명 정리기 가리기", "기타 가리기", "모두 보기", "한글 파일명 정리기 종료",
			"파일", "창 닫기",
			"편집", "실행 취소", "실행 복귀", "잘라내기", "복사하기", "붙여넣기", "모두 선택",
			"윈도우", "최소화", "확대/축소", "앞으로 모두 가져오기"
		]),
		// The window's title, then the file panel's message, then the folder panel's.
		("MainWindowController.swift", ["한글 파일명 정리기", "정리할 파일을 선택하세요", "사본을 저장할 폴더를 선택하세요"]),
		// What VoiceOver says about the two halves of the name switch.
		("Components.swift", ["선택됨", "선택 안 됨"]),
		("DetailScreen.swift", [
			"선택된 파일",
			"macOS Finder에서 보이는 이름", "macOS 현재 원본",
			"Windows에서 보일 수 있는 이름",
			"변환 후 Windows 호환 이름", "변환 후 Windows 예상",
			"출력 이름",
			"결과",
			"← 다른 파일 선택",
			"기존 이름 유지", "이름 바꾸기",
			"새 파일명", "확장자명을 제외하고 입력해주세요",
			"저장 위치 변경", "NFC 사본 만들기",
			"Finder에서 보기"
		]),
		("DropZone.swift", ["파일을 여기에 놓기", "또는 클릭해서 선택하세요. 한 번에 파일 하나만 처리합니다."]),
		// The field's name for VoiceOver, then its context menu.
		("NameField.swift", ["새 파일명", "잘라내기", "복사하기", "붙여넣기", "모두 선택"]),
		("RootView.swift", ["분리된 한글 파일명을 Windows 호환 이름으로 정리합니다."])
	]

	@Test(.timeLimit(.minutes(10))) func theWordingIsWrittenOutOnceMore() throws {
		let extracted = try Self.extraction.get()

		for (file, texts) in Self.wording {
			let entries = extracted.entries[file] ?? []
			#expect(entries.allSatisfy { $0.line != nil && $0.column != nil }, "\(file): the compiler did not say where a text stands")
			let found = entries.sorted { ($0.line ?? 0, $0.column ?? 0) < ($1.line ?? 0, $1.column ?? 0) }.map(\.key)
			// By scalars, and with the differences named.
			let matches = found.count == texts.count && zip(found, texts).allSatisfy { Self.scalarsEqual($0, $1) }
			#expect(matches, "\(file) has these texts, in this order:\n\(found.joined(separator: "\n"))\nexpected:\n\(texts.joined(separator: "\n"))")
		}

		let listed = Set(Self.wording.map(\.file))
		for file in extracted.entries.keys.sorted() where !(extracted.entries[file] ?? []).isEmpty {
			#expect(listed.contains(file), "\(file) shows texts that are not written out in `wording`")
		}
		#expect(Self.wording.map(\.texts.count).reduce(0, +) == extracted.keys.count)

		// The Core's texts (the copy engine's errors, from electron/filename.ts and api.ts of v1.1.0).
		#expect(Message.all.map { Exact($0) } == [
			"일반 파일이 아니거나(폴더·앱 등) 더 이상 없습니다. 파일을 다시 선택하세요.",
			"원본 파일을 읽을 권한이 없습니다. 파일 권한을 확인하세요.",
			"다운로드 보안 표시(quarantine)를 사본에 옮기지 못했습니다. 다른 저장 위치를 선택하세요.",
			"이 저장 위치는 파일명을 NFC로 유지하지 못합니다(외장 드라이브 등). 내장 디스크의 다른 폴더를 선택하세요.",
			"이 저장 위치에 쓸 권한이 없습니다. 다른 저장 위치를 선택하세요.",
			"읽기 전용 위치에는 저장할 수 없습니다. 다른 저장 위치를 선택하세요.",
			"저장 공간이 부족합니다.",
			"원본 파일이나 저장 위치를 찾을 수 없습니다. 파일을 다시 선택하세요.",
			"파일명이 너무 깁니다. 더 짧은 이름을 입력하세요.",
			"같은 이름의 파일이 방금 생겼습니다. 다시 시도하세요.",
			"사본을 만들지 못했습니다."
		].map { Exact($0) })
	}

	// MARK: (a), (b): what the extraction cannot see

	/// Every Korean literal in the Core's sources is one of its messages (`Message.all`, each of which has its entry in
	/// the table): a new text of the copy engine cannot be shown without being listed.
	@Test func everyKoreanTextOfTheCoreIsOneOfItsMessages() throws {
		var messages = 0
		for file in try Self.swiftFiles(in: Self.coreSources) {
			let source = try String(contentsOf: file, encoding: .utf8)
			#expect(isNFCName(source), "\(file.lastPathComponent) is not saved in NFC")
			// A literal with a Korean syllable in it is a word. (The tables of single letters, from which the name "as
			// Windows may show it" is spelled out, are not.)
			for literal in SwiftLiterals.scan(source) where literal.text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
				// Not a text for the screen: the name a copy gets when nothing is left of the typed one.
				if file.lastPathComponent == "Naming.swift", Self.scalarsEqual(literal.text, "파일") {
					continue
				}

				messages += 1
				#expect(
					Message.all.contains { Self.scalarsEqual($0, literal.text) },
					"\(file.lastPathComponent):\(literal.line): a Korean text of the Core that is not in Message.all: \(literal.text)"
				)
			}
		}
		#expect(messages == Message.all.count)
	}

	/// What stands in front of a literal that is shown as it is.
	private static let textArguments = [
		"Text(verbatim:", "Text(", ".help(", "withTitle:", "title:", "label:", "placeholder:", "string:", "message:", "informativeText:",
		"accessibilityLabel(", "accessibilityValue(", "accessibilityHelp(", "setAccessibilityLabel(", "setAccessibilityHelp(", "toolTip =", ".title =",
		".message =", ".prompt =", ".stringValue =", ".placeholderString ="
	]
	/// The only literals without Hangul that are shown: the drop zone's arrow, the arrow between the name cards, and
	/// the file-type abbreviations on a tile whose icon is missing.
	private static let symbolsAndAbbreviations = ["⇧", "↓", "DOC", "HWP", "PDF", "PPT", "XLS", "TXT", "IMG", "ZIP", "FILE"]

	@Test func noTextWithoutHangulIsShown() throws {
		var shown: [String] = []
		for file in try Self.swiftFiles(in: Self.appSources) {
			let source = try String(contentsOf: file, encoding: .utf8)
			let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
			for literal in SwiftLiterals.scan(source) where !Self.hasHangul(literal.text) && !literal.exempt {
				// What stands on the literal's line in front of it (the column counts UTF-8 bytes from 1).
				let before = String(decoding: Array(lines[literal.line - 1].utf8).prefix(literal.column - 1), as: UTF8.self)
					.trimmingCharacters(in: .whitespaces)
				guard Self.textArguments.contains(where: { before.hasSuffix($0) }) else {
					continue
				}

				shown.append(literal.text)
				#expect(
					Self.symbolsAndAbbreviations.contains(literal.text),
					"\(file.lastPathComponent):\(literal.line): a text without Hangul would be shown as it is: \(literal.text)"
				)
			}
		}
		#expect(shown.sorted() == Self.symbolsAndAbbreviations.sorted())
	}

	/// The lexer below, on the forms the app uses.
	@Test func literalScanner() {
		let source = """
		// "주석" is skipped
		let a = "가나 \\(n)개 \\("내부") 끝" /* "블록" */ ; let b = "x\\"y"
		let c = "다"   // l10n-exempt
		"""
		let found = SwiftLiterals.scan(source)
		#expect(found.map(\.text) == ["가나 \u{FFFC}개 \u{FFFC} 끝", "내부", "x\"y", "다"])
		#expect(found[0].interpolated && !found[2].interpolated && found[3].exempt && !found[0].exempt)
		#expect(found[0].line == 2 && found[0].column == 9 && found[3].line == 3)
	}
}

/// String literals of Swift source (outside comments), with their line and UTF-8 column (1-based, the compiler's
/// convention in `.stringsdata`). An interpolation stands as U+FFFC in `text`; literals inside it are listed as well.
enum SwiftLiterals {
	struct Literal {
		var text: String
		var interpolated: Bool
		var line: Int
		var column: Int
		/// Its line carries `l10n-exempt`: a Korean literal that is not a text for the screen.
		var exempt: Bool
	}

	static func scan(_ source: String) -> [Literal] {
		let s = Array(source.utf8)
		var result: [Literal] = []
		var i = 0, line = 1, lineStart = 0
		let quote = UInt8(ascii: "\""), hash = UInt8(ascii: "#"), backslash = UInt8(ascii: "\\"), newline = UInt8(ascii: "\n")

		func lineText(_ start: Int) -> String {
			var end = start
			while end < s.count && s[end] != newline { end += 1 }
			return String(decoding: s[start..<end], as: UTF8.self)
		}

		func startsLiteral(_ k: Int) -> Bool {
			s[k] == quote || (s[k] == hash && k + 1 < s.count && (s[k + 1] == quote || s[k + 1] == hash))
		}

		/// Parses the literal at `start` (a `"` or the `#`s of a raw string); returns the index after it.
		func literal(at start: Int) -> Int {
			let startLine = line, column = start - lineStart + 1, currentLineStart = lineStart
			var j = start, hashes = 0
			while s[j] == hash { hashes += 1; j += 1 }
			let triple = j + 2 < s.count && s[j + 1] == quote && s[j + 2] == quote
			j += triple ? 3 : 1
			var bytes: [UInt8] = []
			var interpolated = false

			func closes(_ k: Int) -> Bool {
				let quotes = triple ? 3 : 1
				guard k + quotes + hashes <= s.count else { return false }
				for q in 0..<quotes where s[k + q] != quote { return false }
				for h in 0..<hashes where s[k + quotes + h] != hash { return false }
				return true
			}

			while j < s.count {
				if closes(j) { j += (triple ? 3 : 1) + hashes; break }
				if s[j] == backslash && (0..<hashes).allSatisfy({ j + 1 + $0 < s.count && s[j + 1 + $0] == hash }) {
					var k = j + 1 + hashes
					let c = s[k]
					if c == UInt8(ascii: "(") {
						interpolated = true
						bytes += Array("\u{FFFC}".utf8)
						var depth = 1
						k += 1
						while k < s.count && depth > 0 {
							let d = s[k]
							if startsLiteral(k) {
								k = literal(at: k)
								continue
							}
							if d == UInt8(ascii: "(") { depth += 1 } else if d == UInt8(ascii: ")") { depth -= 1 }
							if d == newline { line += 1; lineStart = k + 1 }
							k += 1
						}
						j = k
						continue
					}
					switch c {
					case UInt8(ascii: "n"): bytes.append(0x0A)
					case UInt8(ascii: "t"): bytes.append(0x09)
					case UInt8(ascii: "r"): bytes.append(0x0D)
					case UInt8(ascii: "0"): bytes.append(0x00)
					case UInt8(ascii: "u"):
						var end = k + 2
						while end < s.count && s[end] != UInt8(ascii: "}") { end += 1 }
						let hex = String(decoding: s[(k + 2)..<end], as: UTF8.self)
						if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) { bytes += Array(String(scalar).utf8) }
						k = end
					default: bytes.append(c)   // \" \\ \'
					}
					j = k + 1
					continue
				}
				if s[j] == newline { line += 1; lineStart = j + 1 }
				bytes.append(s[j])
				j += 1
			}

			result.append(Literal(
				text: String(decoding: bytes, as: UTF8.self),
				interpolated: interpolated,
				line: startLine,
				column: column,
				exempt: lineText(currentLineStart).contains("l10n-exempt")
			))
			return j
		}

		while i < s.count {
			let c = s[i]
			if c == newline { line += 1; lineStart = i + 1; i += 1; continue }
			if c == UInt8(ascii: "/") && i + 1 < s.count && s[i + 1] == UInt8(ascii: "/") {
				while i < s.count && s[i] != newline { i += 1 }
				continue
			}
			if c == UInt8(ascii: "/") && i + 1 < s.count && s[i + 1] == UInt8(ascii: "*") {
				var depth = 1
				i += 2
				while i < s.count && depth > 0 {
					if s[i] == UInt8(ascii: "/") && i + 1 < s.count && s[i + 1] == UInt8(ascii: "*") { depth += 1; i += 2; continue }
					if s[i] == UInt8(ascii: "*") && i + 1 < s.count && s[i + 1] == UInt8(ascii: "/") { depth -= 1; i += 2; continue }
					if s[i] == newline { line += 1; lineStart = i + 1 }
					i += 1
				}
				continue
			}
			if startsLiteral(i) {
				i = literal(at: i)
				continue
			}
			i += 1
		}

		return result.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
	}
}
