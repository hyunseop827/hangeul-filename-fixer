// The state and the decisions of the one screen this app has. No AppKit, no SwiftUI: the views only show what this
// model says, and the unit tests drive it without a window.
//
// A file name's spelling (NFC or NFD) is what the app is about, and Swift's `==` cannot see it: "한" as one syllable and
// as three jamo are equal Strings. Every comparison of names below is therefore made with the Core's
// `hasSameScalars`, and paths are cut by hand, never through URL or NSString (which respell them).
import Combine
import Foundation
import HangeulFilenameFixerCore

/// What the model needs from the window around it: the two panels and Finder. The unit tests put a recorder here.
@MainActor
protocol AppShell: AnyObject {
	/// Asks for the file to tidy. Calls back with its path, or nil when the panel was cancelled.
	func chooseFile(completion: @escaping @MainActor (String?) -> Void)
	/// Asks for the folder the copy goes to, starting at `directory`. Calls back with nil when cancelled.
	func chooseOutputDirectory(startingAt directory: String?, completion: @escaping @MainActor (String?) -> Void)
	/// Shows the file in Finder.
	func revealInFinder(path: String)
}

/// Counts the copies that are still being written, over all windows. Quitting waits for them (AppDelegate), so no
/// half-written copy is left behind under its final name.
@MainActor
final class ConversionTracker {
	static let shared = ConversionTracker()

	private(set) var running = 0
	/// Called once, when the last running copy has finished.
	var onIdle: (() -> Void)?

	func begin() {
		running += 1
	}

	func end() {
		running -= 1
		if running == 0, let onIdle {
			self.onIdle = nil
			onIdle()
		}
	}
}

/// The two operations on files, both made by the Core. A value so the unit tests can hold one back and let another
/// overtake it; the app always uses `.real`.
struct FileWork: Sendable {
	/// nil: the source is not a regular file (a folder, an app, or no longer there).
	var makePlan: @Sendable (PlanInput) -> FileCopyPlan?
	var copy: @Sendable (PlanInput) -> Result<FileCopyPlan, UserFacingError>

	static let real = FileWork(
		makePlan: { HangeulFilenameFixerCore.makePlan($0) },
		copy: { input in
			do {
				return .success(try copyNormalizedFile(input))
			} catch let error as UserFacingError {
				return .failure(error)
			} catch {
				// copyNormalizedFile throws nothing else (typed throws); a closure just does not carry the type through.
				return .failure(UserFacingError(message: error.localizedDescription))
			}
		}
	)
}

@MainActor
final class AppModel: ObservableObject {
	enum NameMode: Sendable {
		case keep
		case rename
	}

	struct Status {
		enum Tone {
			case success
			case error
			case info
		}

		var tone: Tone
		var message: String
	}

	/// What is known about the copy that would be made.
	enum Preview {
		/// The preview for a newly selected file has not arrived yet.
		case loading
		/// The source is not a regular file (a folder, an app, or no longer there).
		case notRegularFile
		case plan(FileCopyPlan)

		var plan: FileCopyPlan? {
			if case .plan(let plan) = self {
				return plan
			}

			return nil
		}
	}

	// MARK: State

	/// The selected file, spelled as the panel or the drag delivered it. nil shows the first screen.
	@Published private(set) var sourcePath: String?
	/// What was typed into "새 파일명". Kept while the mode is "기존 이름 유지", so it is there again after switching back.
	@Published private(set) var baseName = ""
	@Published private(set) var nameMode: NameMode = .keep
	@Published private(set) var outputDirectory: String?
	@Published private(set) var preview: Preview = .loading
	/// The copy that was made. Set until the next change of the file, the name, the mode or the folder.
	@Published private(set) var createdPlan: FileCopyPlan?
	@Published private(set) var isConverting = false
	@Published private(set) var status: Status?
	/// True while a drag is over the drop zone.
	@Published private(set) var isDragging = false

	/// The preview and the copy that are still running, for the unit tests to wait on.
	private(set) var pendingPreview: Task<Void, Never>?
	private(set) var pendingConversion: Task<Void, Never>?

	weak var shell: AppShell?
	private let work: FileWork
	private let conversions: ConversionTracker

	// The preview is asked for again whenever the input or this counter changes.
	private var previewVersion = 0
	private var previewedInput: PlanInput?
	private var previewedVersion = 0
	/// Raised with every new request; an answer that carries an older number is dropped.
	private var previewGeneration = 0

	init(work: FileWork = .real, conversions: ConversionTracker = .shared) {
		self.work = work
		self.conversions = conversions
	}

	// MARK: What the screen shows

	/// The source's name. Prefer the name stored on disk: the path of a dropped or chosen file may be spelled
	/// decomposed (NFD) even when the file is not.
	var sourceName: String {
		if let plan = createdPlan ?? preview.plan {
			return plan.sourceName
		}

		return sourcePath.map(baseNameFromPath) ?? ""
	}

	/// The first card. Finder shows a ":" in the stored name as "/".
	var finderDisplayName: String {
		var shown = String.UnicodeScalarView()
		for scalar in sourceName.unicodeScalars {
			shown.append(scalar == ":" ? "/" : scalar)
		}

		return String(shown)
	}

	/// The second card: the name as Windows often shows a decomposed name, one letter per jamo.
	var decomposedName: String {
		decomposedDisplayName(sourceName)
	}

	/// The third card: the NFC, Windows-safe form of the source's name.
	var windowsCompatibleName: String {
		let name = sourceName
		if name.unicodeScalars.isEmpty {
			return ""
		}

		let parts = splitFileName(name)
		return windowsSafeFileName(stem: parts.stem, extension: parts.extension)
	}

	var fileIcon: FileIconType {
		FileIconType.forFileName(sourceName)
	}

	/// "이름 바꾸기" is chosen and nothing but white space is typed.
	var customNameMissing: Bool {
		nameMode == .rename && isBlankInJavaScript(baseName)
	}

	/// What the name field shows: empty while the original name is kept.
	var nameFieldText: String {
		nameMode == .rename ? baseName : ""
	}

	var isNameFieldEnabled: Bool {
		nameMode == .rename && !isConverting
	}

	/// What the preview and the copy are made from. nil on the first screen.
	var input: PlanInput? {
		guard let sourcePath, let outputDirectory else {
			return nil
		}

		return PlanInput(sourcePath: sourcePath, outputDirectory: outputDirectory, baseName: nameMode == .keep ? "" : baseName)
	}

	var canConvert: Bool {
		input != nil && preview.plan != nil && !customNameMissing && !isConverting && createdPlan == nil
	}

	var canReveal: Bool {
		createdPlan != nil
	}

	// While the copy is being made nothing about the request can be changed: not the file, not the name, not the
	// folder.

	/// "← 다른 파일 선택".
	var canGoBack: Bool {
		!isConverting
	}

	/// "기존 이름 유지" and "이름 바꾸기".
	var canChangeNameMode: Bool {
		!isConverting
	}

	/// "저장 위치 변경".
	var canChangeOutputDirectory: Bool {
		!isConverting
	}

	var resultLabel: String {
		createdPlan != nil ? String(localized: "생성된 사본") : String(localized: "생성될 사본 이름")
	}

	/// The big line of the result box: the copy's name, or what to do instead.
	var resultName: String {
		if let createdPlan {
			return createdPlan.destinationName
		}
		if customNameMissing {
			return String(localized: "새 파일명을 입력하세요.")
		}

		switch preview {
		case .loading:
			return String(localized: "저장 위치를 확인하는 중입니다.")
		case .notRegularFile:
			return notRegularFileMessage
		case .plan(let plan):
			return plan.destinationName
		}
	}

	/// True when `resultName` is a file name (cut off with "…" when too long) and not a message (which wraps).
	var isShowingFileName: Bool {
		createdPlan != nil || (preview.plan != nil && !customNameMissing)
	}

	var resultHint: String? {
		guard createdPlan == nil, !customNameMissing, let plan = preview.plan else {
			return nil
		}

		// By scalars: with `==` every NFD name would count as "already fine", because Swift calls it equal to its
		// NFC form.
		if nameMode == .keep, hasSameScalars(windowsCompatibleName, sourceName) {
			return String(localized: "이미 Windows 호환 이름이라 사본을 만들지 않아도 됩니다.")
		}
		if plan.hasNumberSuffix {
			return String(localized: "같은 이름의 파일(원본 포함)이 있어 번호가 붙습니다. 원래 이름 그대로 받으려면 저장 위치를 변경하세요.")
		}

		return nil
	}

	// MARK: Events

	/// "파일을 여기에 놓기" was clicked (or Space/Return pressed on it).
	func selectFile() {
		shell?.chooseFile { [weak self] path in
			self?.setFile(path)
		}
	}

	/// "저장 위치 변경".
	func selectOutputDirectory() {
		shell?.chooseOutputDirectory(startingAt: outputDirectory) { [weak self] directory in
			guard let self, let directory, !directory.utf8.isEmpty else {
				return
			}

			self.outputDirectory = directory
			self.resetResult()
			self.refreshPreviewIfNeeded()
		}
	}

	/// Selects a file: the copy goes next to it and keeps its name until the user says otherwise.
	func setFile(_ nextPath: String?) {
		guard let nextPath, !nextPath.utf8.isEmpty else {
			return
		}

		sourcePath = nextPath
		outputDirectory = directoryFromPath(nextPath)
		baseName = ""
		nameMode = .keep
		preview = .loading
		previewVersion += 1
		resetResult()
		refreshPreviewIfNeeded()
	}

	/// A drag entered or left the drop zone.
	func setDragging(_ isDragging: Bool) {
		self.isDragging = isDragging
	}

	/// Files were dropped on the drop zone, in the order the drag carried them. Only the first one is used.
	func handleDrop(paths: [String]) {
		isDragging = false

		guard let firstPath = paths.first else {
			return
		}

		setFile(firstPath)

		if paths.count > 1 {
			status = Status(tone: .info, message: String(localized: "파일 하나만 처리합니다. 첫 번째 파일만 선택했습니다."))
		}
	}

	func changeNameMode(_ mode: NameMode) {
		nameMode = mode
		resetResult()
		refreshPreviewIfNeeded()
	}

	/// The name field was edited.
	func setBaseName(_ text: String) {
		baseName = text
		resetResult()
		refreshPreviewIfNeeded()
	}

	/// "NFC 사본 만들기".
	func convertFile() {
		guard let input, canConvert else {
			return
		}

		isConverting = true
		status = Status(tone: .info, message: String(localized: "사본을 만드는 중입니다…"))
		conversions.begin()

		let copy = work.copy
		// Strong `self`: the copy is finished and counted also when the window was closed meanwhile.
		pendingConversion = Task.detached(priority: .userInitiated) {
			let result = copy(input)
			await self.finishConversion(result)
		}
	}

	/// "← 다른 파일 선택": back to the first screen.
	func clearFile() {
		sourcePath = nil
		outputDirectory = nil
		resetResult()
		refreshPreviewIfNeeded()
	}

	/// "Finder에서 보기".
	func revealCreatedCopy() {
		if let createdPlan {
			shell?.revealInFinder(path: createdPlan.destinationPath)
		}
	}

	// MARK: Internals

	private func resetResult() {
		createdPlan = nil
		status = nil
	}

	private func finishConversion(_ result: Result<FileCopyPlan, UserFacingError>) {
		switch result {
		case .success(let plan):
			createdPlan = plan
			status = Status(tone: .success, message: String(localized: "완료되었습니다. 저장된 파일명이 NFC인지 확인했습니다."))
		case .failure(let error):
			// The Core's messages are Korean and written for the user; shown as they are.
			status = Status(tone: .error, message: error.message)
		}

		isConverting = false
		// The new copy now takes its name, so the next preview needs a fresh " (n)".
		previewVersion += 1
		refreshPreviewIfNeeded()
		conversions.end()
	}

	/// Asks for a new preview when the input changed since the last request, or when a new one was demanded
	/// (`previewVersion`). Called at the end of every event. The plan shown so far stays until the answer arrives;
	/// only a newly selected file starts from "loading".
	private func refreshPreviewIfNeeded() {
		let input = self.input
		// PlanInput's `==` compares bytes, so a path respelled from NFC to NFD is a new input.
		guard input != previewedInput || previewVersion != previewedVersion else {
			return
		}

		previewedInput = input
		previewedVersion = previewVersion
		// Whatever is still on its way was asked for something else.
		previewGeneration += 1

		guard let input else {
			pendingPreview = nil
			return
		}

		let generation = previewGeneration
		let makePlan = work.makePlan
		pendingPreview = Task.detached(priority: .userInitiated) { [weak self] in
			let plan = makePlan(input)
			await self?.receivePreview(plan, generation: generation)
		}
	}

	private func receivePreview(_ plan: FileCopyPlan?, generation: Int) {
		guard generation == previewGeneration else {
			return
		}

		preview = plan.map(Preview.plan) ?? .notRegularFile
	}
}

// MARK: - Text helpers

/// The part after the last "/". A plain cut: URL and NSString path methods would respell or reinterpret the path.
func baseNameFromPath(_ filePath: String) -> String {
	let scalars = filePath.unicodeScalars
	guard let slash = scalars.lastIndex(of: "/") else {
		return filePath
	}

	return String(scalars[scalars.index(after: slash)...])
}

/// The part before the last "/"; "/" for a file in the root folder.
func directoryFromPath(_ filePath: String) -> String {
	let scalars = filePath.unicodeScalars
	guard let slash = scalars.lastIndex(of: "/"), slash != scalars.startIndex else {
		// "/name" lies in the root folder. (A path without any "/" does not occur: panels and drags give absolute
		// paths.)
		return "/"
	}

	return String(scalars[..<slash])
}

/// True when the text is empty or consists only of the characters JavaScript's `trim()` removes — the same test the
/// Core applies to decide that the original name is kept. Not `Character.isWhitespace` or
/// `CharacterSet.whitespacesAndNewlines`: those also contain U+0085 and lack U+FEFF. The unit tests check this set
/// against the Core's for every code point.
func isBlankInJavaScript(_ text: String) -> Bool {
	text.unicodeScalars.allSatisfy { scalar in
		switch scalar.value {
		case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
			return true
		default:
			return false
		}
	}
}
