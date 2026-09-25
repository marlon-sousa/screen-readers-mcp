// Mirrors Sources/VoiceOverBridgeAdapters/AccessibilityTextTyper.swift.
// Nothing here posts a real event: the real poster types into the developer's front window.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("AccessibilityTextTyper")
struct AccessibilityTextTyperTests {
	private func typer(_ poster: FakeEventPoster) -> AccessibilityTextTyper {
		AccessibilityTextTyper(poster: poster)
	}

	@Test("every chunk goes out as a key-DOWN and then a key-UP, both carrying the payload")
	func bothHalvesOfTheKeystrokeAreSent() throws {
		let poster = FakeEventPoster()
		try typer(poster).type("hi")
		#expect(poster.posted == [
			FakeEventPoster.Posted(unicode: "hi", keyDown: true),
			FakeEventPoster.Posted(unicode: "hi", keyDown: false),
		])
	}

	@Test("a long string is cut into payloads, and every character survives in order")
	func longTextIsChunkedWithoutLoss() throws {
		let text = String(repeating: "abcde", count: 13)  // 65 characters
		let poster = FakeEventPoster()
		try typer(poster).type(text)
		#expect(poster.typedText == text)
		#expect(poster.posted.count == 8)  // four chunks, a down and an up each
		for chunk in poster.posted where chunk.keyDown {
			#expect(chunk.unicode.utf16.count <= AccessibilityTextTyper.chunkLimit)
		}
	}

	@Test("a chunk is never cut through a grapheme cluster")
	func clustersAreNeverSplit() throws {
		let text = String(repeating: "e\u{0301}", count: 30)
		let chunks = AccessibilityTextTyper.chunks(of: text)
		#expect(chunks.joined() == text)
		for chunk in chunks {
			#expect(chunk.utf16.count <= AccessibilityTextTyper.chunkLimit)
			#expect(chunk.unicodeScalars.count.isMultiple(of: 2), "a cluster was cut in half")
		}
	}

	@Test("a single cluster longer than the limit is sent WHOLE rather than split")
	func anOverLongClusterIsNotSplit() throws {
		let stacked = "e" + String(repeating: "\u{0301}", count: 25)
		#expect(stacked.count == 1, "one grapheme cluster")
		#expect(stacked.utf16.count > AccessibilityTextTyper.chunkLimit, "the trap this test is for")
		#expect(AccessibilityTextTyper.chunks(of: stacked) == [stacked])
	}

	@Test("empty text posts NOTHING, rather than an empty keystroke")
	func emptyTextIsNoEvents() throws {
		let poster = FakeEventPoster()
		try typer(poster).type("")
		#expect(poster.posted.isEmpty)
	}

	@Test("control characters are payload like anything else -- nothing is interpreted")
	func controlCharactersAreNotInterpreted() throws {
		let poster = FakeEventPoster()
		try typer(poster).type("a\nb\tc")
		#expect(poster.typedText == "a\nb\tc")
	}

	@Test("a posting failure becomes a TypingError, so the domain never sees the seam's type")
	func aPostingFailureIsTranslated() throws {
		let poster = FakeEventPoster()
		poster.failure = EventPostingFailure("the system would not create a keyboard event")
		do {
			try typer(poster).type("hi")
			Issue.record("expected the post to fail")
		} catch let error as TypingError {
			#expect(error.description.contains("keyboard event"))
		}
	}
}
