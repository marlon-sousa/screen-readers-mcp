// Mirrors Sources/CaptureVoice/Domain/Entities/SsmlDocument.swift.
//
// The first suite here is the one that matters most, and it is a NEGATIVE: no
// xml:lang is the normal case on this reader. Every measured utterance from a
// live VoiceOver on macOS 15.0 lacked one, and reading that absence as licence to
// pick a default is how this route read Portuguese aloud in Arabic.

import Testing

@testable import CaptureVoice

@Suite("SsmlDocument")
struct SsmlDocumentTests {
	/// Verbatim from spec 0041's A2 findings -- a real VoiceOver utterance, with
	/// the user's speech rate outside and the column-header pitch drop inside.
	static let realUtterance =
		"<speak><prosody rate=\"160.00002%\"><prosody pitch=\"-40.0%\">Data de Modificação</prosody></prosody></speak>"

	@Test("VoiceOver's own SSML states no language, and that is the normal answer")
	func realVoiceOverUtteranceHasNoLanguage() {
		let document = SsmlDocument(SsmlDocumentTests.realUtterance)
		#expect(document.language == nil)
		#expect(document.text == "Data de Modificação")
	}

	@Test("the source is kept verbatim, because it carries prosody the words do not")
	func sourceIsUntouched() {
		let document = SsmlDocument(SsmlDocumentTests.realUtterance)
		#expect(document.source == SsmlDocumentTests.realUtterance)
	}

	@Test("xml:lang is read when a document does state one")
	func languageIsReadWhenPresent() {
		#expect(SsmlDocument("<speak xml:lang=\"pt-BR\">um dois</speak>").language == "pt-BR")
	}

	@Test("an empty xml:lang is no language at all, not an empty one")
	func emptyLanguageIsNil() {
		#expect(SsmlDocument("<speak xml:lang=\"\">um</speak>").language == nil)
	}

	@Test("breaks and other self-closing tags leave no trace in the text")
	func breaksAreRemoved() {
		let document = SsmlDocument("<speak>um<break time=\"250ms\"/>dois</speak>")
		#expect(document.text == "umdois")
	}

	@Test("the five predefined entities are decoded")
	func entitiesAreDecoded() {
		let document = SsmlDocument("<speak>Fish &amp; Chips &lt;1&gt; &quot;x&quot; &apos;y&apos;</speak>")
		#expect(document.text == "Fish & Chips <1> \"x\" 'y'")
	}

	@Test("an escaped entity stays escaped -- &amp; is decoded last")
	func doubleEscapingSurvives() {
		#expect(SsmlDocument("<speak>&amp;lt;</speak>").text == "&lt;")
	}

	@Test("an unknown entity is left alone rather than guessed at")
	func unknownEntityIsUntouched() {
		#expect(SsmlDocument("<speak>&nbsp;x</speak>").text == "&nbsp;x")
	}

	@Test("surrounding whitespace is trimmed, inner spacing is not")
	func whitespaceIsTrimmedAtTheEdgesOnly() {
		#expect(SsmlDocument("<speak>  um dois  </speak>").text == "um dois")
	}

	@Test("text with no markup at all is still text")
	func plainInputSurvives() {
		#expect(SsmlDocument("um dois").text == "um dois")
		#expect(SsmlDocument("um dois").language == nil)
	}
}
