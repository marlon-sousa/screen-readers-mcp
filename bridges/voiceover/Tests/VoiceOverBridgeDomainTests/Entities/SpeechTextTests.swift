// Mirrors Sources/VoiceOverBridgeDomain/Entities/SpeechText.swift.
//
// THE CASES ARE THE ONES VOICEOVER ACTUALLY SENDS. Spec 0041 measured its SSML:
// a `<speak>` wrapper, a `<prosody>` carrying the user's rate, inner `<prosody>`
// for emphasis, `<break>` between phrases, escaped entities, and no `xml:lang`
// anywhere. Everything asserted here is one of those.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("SpeechText")
struct SpeechTextTests {
	@Test("the words come out and the tags do not")
	func tagsAreRemoved() {
		let ssml = "<speak><prosody rate=\"1.4\">Documents, folder</prosody></speak>"
		#expect(SpeechText.plain(ofSsml: ssml) == "Documents, folder")
	}

	@Test("a break between phrases leaves the phrases, and no marker")
	func breaksLeaveNothingBehind() {
		let ssml = "<speak>Finder<break time=\"200ms\"/>window</speak>"
		#expect(SpeechText.plain(ofSsml: ssml) == "Finderwindow")
	}

	@Test("nested prosody -- the reader lowering its voice -- is still one line of words")
	func nestedProsody() {
		let ssml = "<speak><prosody rate=\"1.4\">Name <prosody pitch=\"-10%\">column header</prosody></prosody></speak>"
		#expect(SpeechText.plain(ofSsml: ssml) == "Name column header")
	}

	@Test("the five predefined entities are decoded, and nothing else is")
	func entities() {
		#expect(SpeechText.plain(ofSsml: "<speak>Fish &amp; Chips</speak>") == "Fish & Chips")
		#expect(SpeechText.plain(ofSsml: "<speak>a &lt; b</speak>") == "a < b")
		#expect(SpeechText.plain(ofSsml: "<speak>b &gt; a</speak>") == "b > a")
		#expect(SpeechText.plain(ofSsml: "<speak>&quot;quoted&quot;</speak>") == "\"quoted\"")
		#expect(SpeechText.plain(ofSsml: "<speak>it&apos;s</speak>") == "it's")
		// Left alone rather than guessed at: read back as "nbsp" it would be a
		// defect, and mangled into some character it would be a worse one.
		#expect(SpeechText.plain(ofSsml: "<speak>a&nbsp;b</speak>") == "a&nbsp;b")
	}

	@Test("`&amp;lt;` yields the literal `&lt;`, which is what decoding amp LAST buys")
	func doubleEscaping() {
		#expect(SpeechText.plain(ofSsml: "<speak>&amp;lt;</speak>") == "&lt;")
	}

	@Test("the ends are trimmed, because a wrapper's whitespace is not something the reader said")
	func trimming() {
		#expect(SpeechText.plain(ofSsml: "<speak>\n  Documents\n</speak>") == "Documents")
	}

	@Test("text with no markup at all is itself")
	func plainTextSurvives() {
		#expect(SpeechText.plain(ofSsml: "Documents") == "Documents")
	}

	@Test("an empty document is empty words, not a crash")
	func emptyDocument() {
		#expect(SpeechText.plain(ofSsml: "") == "")
		#expect(SpeechText.plain(ofSsml: "<speak></speak>") == "")
	}

	@Test("an unterminated tag swallows the rest, and does not run off the end")
	func malformedIsSurvivable() {
		// Whatever the reader said has to be readable back, so this renders
		// something rather than throwing. What it renders is not a promise.
		#expect(SpeechText.plain(ofSsml: "<speak>said<prosody") == "said")
	}
}
