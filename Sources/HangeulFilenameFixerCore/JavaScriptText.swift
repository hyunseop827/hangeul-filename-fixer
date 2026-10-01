// JavaScript string behavior the filename rules were written against, rebuilt on Unicode scalars and UTF-16 code units.
//
// Swift's String API cannot be used for this: it works on Characters and treats canonically equivalent text as equal.
// "한" written as one syllable (NFC) and as three jamo (NFD) are `==`, hash alike and are one key in a Set, and a "."
// followed by a combining mark is one Character that `lastIndex(of: ".")` does not find. A file name's spelling is the
// whole point of this app, so everything here looks at scalars (JavaScript code points) or UTF-16 units (JavaScript
// `length` and `slice`), never at Characters.
import Foundation

private let anyNFC = StringTransform(rawValue: "Any-NFC")

/// JavaScript `string.normalize("NFC")`.
///
/// Not `precomposedStringWithCanonicalMapping`: Foundation's own normalizer disagrees with JavaScript exactly where
/// this app works. It leaves a precomposed syllable followed by a final consonant uncomposed (U+AC00 U+11A8 stays as
/// it is; JavaScript gives U+AC01) and composes some old-Hangul jamo into wrong syllables. ICU's "Any-NFC" transform
/// gives the same result as JavaScript; the unit tests pin the cases.
func nfc(_ string: String) -> String {
	// ASCII is the same in every normalization form; most non-Korean names stop here.
	if string.utf8.allSatisfy({ $0 < 0x80 }) {
		return string
	}

	return string.applyingTransform(anyNFC, reverse: false) ?? string.precomposedStringWithCanonicalMapping
}

/// True when both strings are the same sequence of code points, the way JavaScript `===` compares strings.
/// (`==` on Swift Strings is also true for an NFC and an NFD spelling of the same text.)
///
/// Public for the app: whether a name is "already fine" is a question about its spelling, and must be asked with
/// this function, never with `==`.
public func hasSameScalars(_ first: String, _ second: String) -> Bool {
	first.unicodeScalars.elementsEqual(second.unicodeScalars)
}

/// The characters JavaScript `trim()`, `trimEnd()` and the regular expression `\s` treat as white space.
///
/// Swift has no equal set: `Character.isWhitespace` and `CharacterSet.whitespacesAndNewlines` also contain U+0085 (and
/// the latter U+200B), and neither contains U+FEFF.
func isJavaScriptWhitespace(_ scalar: Unicode.Scalar) -> Bool {
	switch scalar.value {
	case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
		return true
	default:
		return false
	}
}

extension String {
	/// Removes scalars from the front while `shouldRemove` holds. Scalar by scalar: a space followed by a combining
	/// mark is one Character, and JavaScript still removes the space and keeps the mark.
	func removingLeadingScalars(while shouldRemove: (Unicode.Scalar) -> Bool) -> String {
		let scalars = unicodeScalars
		guard let start = scalars.firstIndex(where: { !shouldRemove($0) }) else {
			return ""
		}

		return String(scalars[start...])
	}

	/// Removes scalars from the end while `shouldRemove` holds.
	func removingTrailingScalars(while shouldRemove: (Unicode.Scalar) -> Bool) -> String {
		let scalars = unicodeScalars
		guard let last = scalars.lastIndex(where: { !shouldRemove($0) }) else {
			return ""
		}

		return String(scalars[...last])
	}

	/// JavaScript `trim()`.
	func javaScriptTrimmed() -> String {
		removingLeadingScalars(while: isJavaScriptWhitespace).removingTrailingScalars(while: isJavaScriptWhitespace)
	}

	/// JavaScript `trimEnd()`.
	func javaScriptTrimmedEnd() -> String {
		removingTrailingScalars(while: isJavaScriptWhitespace)
	}

	/// JavaScript `toLowerCase()`: the locale-independent full lowercase mapping of every code point, plus Final_Sigma.
	///
	/// Swift's `lowercased()` has the same per-scalar mapping but no Final_Sigma rule ("ΑΣ" must become "ας", not
	/// "ασ"). Foundation's variants are further away: they use another sigma rule, and `lowercased(with:)` stops at
	/// U+0000.
	func javaScriptLowercased() -> String {
		let scalars = Array(unicodeScalars)
		var result = String.UnicodeScalarView()

		for (index, scalar) in scalars.enumerated() {
			guard scalar == "\u{03A3}" else {
				result.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
				continue
			}

			// Final_Sigma: Σ ends a word when a cased letter comes before it and none comes after it. Characters that
			// case mapping ignores (apostrophes, combining marks, …) are skipped on both sides.
			var before = index - 1
			while before >= 0, isCaseIgnorable(scalars[before]) {
				before -= 1
			}
			var after = index + 1
			while after < scalars.count, isCaseIgnorable(scalars[after]) {
				after += 1
			}

			let followsCasedLetter = before >= 0 && scalars[before].properties.isCased
			let precedesCasedLetter = after < scalars.count && scalars[after].properties.isCased
			result.append(followsCasedLetter && !precedesCasedLetter ? "\u{03C2}" : "\u{03C3}")
		}

		return String(result)
	}
}

/// Unicode Case_Ignorable as JavaScript sees it. macOS also reports some of Apple's private-use code points
/// (U+F870–F87F and others) as case-ignorable; in the Unicode data no private-use code point is.
private func isCaseIgnorable(_ scalar: Unicode.Scalar) -> Bool {
	if (0xE000...0xF8FF).contains(scalar.value) {
		return false
	}

	return scalar.properties.isCaseIgnorable
}
