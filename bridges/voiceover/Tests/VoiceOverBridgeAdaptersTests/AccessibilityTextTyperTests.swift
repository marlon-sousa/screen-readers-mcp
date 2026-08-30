// Mirrors Sources/VoiceOverBridgeAdapters/AccessibilityTextTyper.swift.
//
// EVERY DECISION ABOUT TYPING IS IN THIS FILE'S SUBJECT, which is the point of
// the seam beneath it: how a string is cut into payloads, where it may be cut,
// and that every chunk goes out as a key-down and then a key-up. Below the seam
// there is one Core Graphics call and nothing to test.
//
// NOTHING HERE POSTS A REAL EVENT. The real poster types into whatever window
// the developer has in front of them, so FakeEventPoster is the only
// implementation any test may hold -- the same rule
// `Tests/Fakes/Support/ReaderEdge.swift` states for the provider lifecycle and
// the permission broker.
//
// AND NOTHING HERE COMPARES TYPED INPUT WITH OBSERVED OUTPUT. Spec 0041 measured
// two lines sent to TextEdit coming back autocapitalized: the target application
// rewrites what was typed, so "these keystrokes went out" is the only claim this
// class makes and the only one its tests assert.

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
		// An application that inserts on key-down and one that inserts on key-up
		// would otherwise disagree about whether anything was typed, and a
		// key-down with no key-up leaves anything watching the event stream
		// believing a key is still held.
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
		// Half a surrogate pair is not text at all, and a base letter separated
		// from its combining accent arrives as two characters where the agent sent
		// one -- which would then be blamed on the target application's own
		// substitutions, because that is exactly what they look like.
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
		// One character to everyone who can see it -- a base letter under a stack
		// of combining marks -- and longer on its own than a whole payload may be.
		// An over-long payload that might be truncated is a better failure than a
		// payload that is certainly nonsense.
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
		// protocol.md §5: `typeText` does not interpret control characters or
		// newlines and does not submit anything. A newline is a newline here, not
		// Return.
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
