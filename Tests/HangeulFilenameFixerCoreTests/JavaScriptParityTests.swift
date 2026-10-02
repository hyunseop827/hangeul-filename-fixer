// The JavaScript details the TypeScript original depended on, with the results Node 22 gave for the same inputs
// (the real electron/naming.ts and electron/filename.ts of v1.1.0 were run to get them).
import Testing
@testable import HangeulFilenameFixerCore

@Suite("JavaScript parity")
struct JavaScriptParityTests {
	@Test("white space is exactly JavaScript's set of 25 code points")
	func whitespaceSet() {
		// What String.prototype.trim() and the regular expression \s remove, from Node.
		let javaScript: Set<UInt32> = Set(
			[0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF] + Array(0x2000...0x200A)
		)
		#expect(javaScript.count == 25)

		var wrong: [String] = []
		for value in UInt32(0)...0x10FFFF {
			guard let scalar = Unicode.Scalar(value) else {
				continue
			}
			if isJavaScriptWhitespace(scalar) != javaScript.contains(value) {
				wrong.append(String(value, radix: 16))
			}
		}
		#expect(wrong.isEmpty, "\(wrong.prefix(5))")
	}

	@Test("trim and trimEnd work on code points")
	func trimming() {
		#expect(Exact("  앞뒤 공백  ".javaScriptTrimmed()) == Exact("앞뒤 공백"))
		#expect(Exact("\u{A0}\u{3000}\u{FEFF}x\u{2028}\u{2029}\t\n".javaScriptTrimmed()) == Exact("x"))
		#expect(Exact("\u{85}x\u{85}".javaScriptTrimmed()) == Exact("\u{85}x\u{85}"), "U+0085 is not white space in JavaScript")
		#expect(Exact("\u{200B}x\u{200B}".javaScriptTrimmed()) == Exact("\u{200B}x\u{200B}"))
		#expect(Exact("\u{180E}x".javaScriptTrimmed()) == Exact("\u{180E}x"))
		#expect(Exact("\u{1C}x\u{1C}".javaScriptTrimmed()) == Exact("\u{1C}x\u{1C}"))
		#expect(Exact(" \u{301}x ".javaScriptTrimmed()) == Exact("\u{301}x"), "the space goes, its combining mark stays")
		#expect(Exact("   ".javaScriptTrimmed()) == Exact(""))
		#expect(Exact("".javaScriptTrimmed()) == Exact(""))
		#expect(Exact("  x  ".javaScriptTrimmedEnd()) == Exact("  x"))
		#expect(Exact("\u{FEFF}".javaScriptTrimmedEnd()) == Exact(""))
	}

	@Test("splitFileName follows lastIndexOf(\".\")")
	func splitting() {
		let cases: [(String, String, String)] = [
			("a.\u{301}txt", "a", ".\u{301}txt"),
			("...", "..", "."),
			(".", ".", ""),
			("..a", ".", ".a"),
			(".a.b", ".a", ".b"),
			("a.", "a", "."),
			("", "", ""),
			(decomposed("한글.txt"), decomposed("한글"), ".txt")
		]

		for (name, stem, fileExtension) in cases {
			let parts = splitFileName(name)
			#expect(Exact(parts.stem) == Exact(stem), "\(hexScalars(name))")
			#expect(Exact(parts.extension) == Exact(fileExtension), "\(hexScalars(name))")
		}
	}

	@Test("windowsSafeFileName gives the names the TypeScript gave")
	func safeNames() {
		// (stem, extension, result of electron/naming.ts)
		let cases: [(String, String, String)] = [
			("a<\u{338}b", ".txt", "a\u{226E}b.txt"),                 // NFC first: "<" + solidus overlay is "≮", not forbidden
			("CON.\u{301}x", ".txt", "_CON.\u{301}x.txt"),
			("CON\u{301}", ".txt", "CO\u{143}.txt"),
			("NUL \u{301}", ".txt", "NUL \u{301}.txt"),
			("con\r\n", ".txt", "con__.txt"),                         // CR and LF are replaced before anything is trimmed
			("\u{FEFF}CON\u{FEFF}", ".txt", "_CON.txt"),
			("CON\u{A0}", ".txt", "_CON.txt"),
			("CON\u{85}", ".txt", "CON\u{85}.txt"),
			("com\u{B2}", "", "_com\u{B2}"),
			("\u{FF23}\u{FF2F}\u{FF2E}", ".txt", "\u{FF23}\u{FF2F}\u{FF2E}.txt"),
			("a:\u{301}b", ".txt", "a_\u{301}b.txt"),
			("x\r\ny", ".txt", "x__y.txt"),
			("..", ".", "파일"),
			("e", "\u{301}", "e\u{301}"),                             // joined as code points, not normalized again
			("\u{A0}이름\u{A0}", ".txt", "이름.txt"),
			("\u{3000}이름\u{3000}", ".txt", "이름.txt"),
			("\u{FEFF}이름\u{FEFF}", ".txt", "이름.txt"),
			("이름\u{85}", ".txt", "이름\u{85}.txt"),
			("이름\u{200B}", ".txt", "이름\u{200B}.txt"),
			("a.\u{A0}.", ".txt", "a.\u{A0}.txt"),                    // only "." and " " are stripped after the trim
			("보고서: 최종?", ".txt", "보고서_ 최종_.txt"),
			("Q&A 2024", ".1분기?", "Q&A 2024.1분기_"),
			("\u{AC00}\u{11A8}", ".txt", "\u{AC01}.txt"),              // LV + T composes (Foundation's normalizer leaves it)
			("\u{1100}\u{1161}\u{11A8}", ".txt", "\u{AC01}.txt"),
			("Aux", ".h", "_Aux.h"),
			("prn.a.b", ".c", "_prn.a.b.c"),
			("LPT\u{B3} ", ".x", "_LPT\u{B3}.x"),
			("COM0", "", "COM0"),
			("\u{212A}", ".txt", "K.txt"),
			("COM1\u{301}", "", "COM1\u{301}"),
			("", "", "파일"),
			("", ".txt", "파일.txt")
		]

		for (stem, fileExtension, expected) in cases {
			let name = windowsSafeFileName(stem: stem, extension: fileExtension)
			#expect(Exact(name) == Exact(expected), "\(hexScalars(stem)) + \(hexScalars(fileExtension))")
		}

		#expect("파일".unicodeScalars.map(\.value) == [0xD30C, 0xC77C], "the fallback name is written in NFC")
	}

	@Test("the forbidden characters are exactly < > : \" / \\ | ? * and U+0000–U+001F")
	func forbiddenCharacters() {
		// /[<>:"/\\|?*\u0000-\u001f]/g of electron/naming.ts. Both ends of the range, and what lies just outside it.
		#expect(Exact(windowsSafeFileName(stem: "a\u{0}b\u{1F}c\u{7F}d\u{20}e", extension: ".t\u{0}\u{1F}\u{7F}")) == Exact("a_b_c\u{7F}d e.t__\u{7F}"))

		let punctuation = Array("<>:\"/\\|?*".unicodeScalars)
		for value in UInt32(0)...0x24F {
			guard let scalar = Unicode.Scalar(value) else {
				continue
			}

			// In the middle of the name, where no trimming rule applies; none of these code points changes in NFC.
			let shown = value <= 0x1F || punctuation.contains(scalar) ? "_" : String(scalar)
			#expect(Exact(windowsSafeFileName(stem: "x" + String(scalar) + "y", extension: "")) == Exact("x" + shown + "y"), "stem, U+\(String(value, radix: 16))")
			#expect(Exact(windowsSafeFileName(stem: "a", extension: "." + String(scalar) + "z")) == Exact("a." + shown + "z"), "extension, U+\(String(value, radix: 16))")
		}
	}

	@Test("customStem cuts a typed extension like toLowerCase().endsWith() and slice()")
	func typedExtension() {
		// (typed name, extension of the source, result of customStem in electron/filename.ts)
		let cases: [(String, String, String)] = [
			("새 보고서.HWP", ".hwp", "새 보고서"),
			("보고서.hwp", ".HWP", "보고서"),
			("보고서", ".hwp", "보고서"),
			("hwp", ".hwp", "hwp"),
			(".hwp", ".hwp", "hwp"),                                  // the leading dot goes first, then nothing matches
			("보고서.hwp.", ".hwp", "보고서"),
			("b.tar.gz", ".gz", "b.tar"),
			("y", ".", "y"),                                          // an extension of only a dot is no extension
			("y.txt", ".txt ", "y"),
			("\u{3B1}\u{3B2}\u{3B3}.\u{3A3}", ".\u{3A3}", "\u{3B1}\u{3B2}\u{3B3}.\u{3A3}"),   // final sigma: "…ς" does not end with ".σ"
			("STRASSE.SS", ".\u{DF}", "STRASSE.SS"),                  // ß does not lowercase to ss
			// İ lowercases to i + U+0307, so the three typed units match; the cut is the two units of ".İ" as written.
			("보고서.i\u{307}", ".\u{130}", "보고서."),
			("\u{1F600}.i\u{307}", ".\u{130}", "\u{1F600}."),
			("\u{1F600}.\u{130}", ".i\u{307}", "\u{FFFD}"),            // three units cut from four: half an emoji is left
			("resume\u{301}", ".\u{E9}", "resum\u{E9}"),              // typed text is normalized first
			("cafe.e\u{301}", ".\u{E9}", "cafe"),
			("  .. 이름 .. ", ".txt", "이름"),
			("\u{FEFF}.\u{A0}이름\u{3000}.", ".txt", "이름"),
			("...", ".txt", ""),
			("\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}", ".hwp", "한글"),
			// U+0600 joins the dot after it into one Character, so hasSuffix(".hwp") is false; endsWith is true.
			("보고서\u{600}.HWP", ".hwp", "보고서\u{600}"),
			("x.txt", "", "x.txt"),
			("a.TXT.txt", ".txt", "a.TXT"),                           // only one copy of the extension is cut
			// The source's extension as it is stored on disk, decomposed: it is normalized before the comparison.
			("보고서.한글", decomposed(".한글"), "보고서"),
			(decomposed("보고서.한글"), decomposed(".한글"), "보고서"),
			("보고서.한글", ".한글", "보고서")
		]

		for (typed, fileExtension, expected) in cases {
			#expect(Exact(customStem(typed, extension: fileExtension)) == Exact(expected), "\(hexScalars(typed)) with \(hexScalars(fileExtension))")
		}
	}

	@Test("paths are joined and split like Node's path module")
	func paths() {
		let directoryNames: [(String, String)] = [
			("", "."), ("/", "/"), ("a", "."), ("/a", "/"), ("/a/b", "/a"), ("/a/b/", "/a"), ("/a//b", "/a/"), ("a/b", "a"),
			("//a", "//"), ("/한/글.txt", "/한"), ("a/", ".")
		]
		for (path, expected) in directoryNames {
			#expect(Exact(directoryName(ofPath: path)) == Exact(expected), "dirname \(path)")
		}

		let baseNames: [(String, String)] = [
			("", ""), ("/", ""), ("a", "a"), ("/a", "a"), ("/a/b/", "b"), ("/한/글.txt", "글.txt"), ("a/", "a"),
			("/tmp/" + decomposed("한글.txt"), decomposed("한글.txt"))
		]
		for (path, expected) in baseNames {
			#expect(Exact(baseName(ofPath: path)) == Exact(expected), "basename \(path)")
		}

		let joined: [(String, String, String)] = [
			("/out", "x", "/out/x"), ("/out/", "x", "/out/x"), ("", "x", "x"), ("/", "x", "/x"), ("/a/../b", "x", "/b/x"),
			(".", "x", "x"), ("a//b/./", "x", "a/b/x"), ("", "", "."), ("../a", "x", "../a/x"),
			("/out//", "한 (1).txt", "/out/한 (1).txt"), ("/a/b/../../..", "x", "/x"), ("a/../..", "x", "../x"),
			("/" + decomposed("폴더"), decomposed("한글.txt"), "/" + decomposed("폴더") + "/" + decomposed("한글.txt"))
		]
		for (directory, name, expected) in joined {
			#expect(Exact(joinPath(directory, name)) == Exact(expected), "join \(directory) + \(name)")
		}
	}
}
