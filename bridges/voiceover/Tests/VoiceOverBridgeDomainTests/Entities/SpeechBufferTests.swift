// Mirrors Sources/VoiceOverBridgeDomain/Entities/SpeechBuffer.swift.
//
// THE INDEX CONVENTION IS WHAT MOST OF THIS FILE ASSERTS, because it is what
// every race-free assertion an agent makes is built on: a bookmark taken before
// an action, a half-open range read after it, and the guarantee that a stale
// bookmark answers rather than raises.
//
// The clock is a fixture, so the buffer's clock IS the one a test advances --
// hand-wiring that per test permits a buffer on one clock and a test advancing
// another, which passes while asserting nothing.

import Fakes
import Testing

@testable import VoiceOverBridgeDomain

@Suite("SpeechBuffer")
struct SpeechBufferTests {
	private let clock = FakeClock()

	private func buffer() -> SpeechBuffer {
		SpeechBuffer(clock: clock)
	}

	private func utterance(_ text: String, at emittedAt: Double = 0) -> CapturedUtterance {
		CapturedUtterance(text: text, emittedAt: emittedAt, ssml: "<speak>\(text)</speak>", voice: "ours")
	}

	// -- the index convention ------------------------------------------------

	@Test("a fresh buffer holds one empty sentinel, so index 0 is never a real utterance")
	func theSentinel() {
		let speech = buffer()
		#expect(speech.lastIndex() == 0)
		#expect(speech.nextIndex() == 1)
		#expect(speech.last().utterance.text.isEmpty)
		#expect(speech.last().index == 0)
	}

	@Test("the first capture lands at index 1, and the bookmark moves with it")
	func appendingAdvancesTheBookmark() {
		let speech = buffer()
		let mark = speech.nextIndex()
		speech.append(utterance("Documents"))
		#expect(mark == 1)
		#expect(speech.last().index == 1)
		#expect(speech.nextIndex() == 2)
	}

	@Test("the bridge's own numbering is the position in the buffer, whatever the producer said")
	func theBridgeNumbersUtterances() {
		// The feed's own sequence counter restarts when the system relaunches the
		// extension (spec 0041, A4). The port's DTO does not even carry it -- this
		// asserts the consequence: three utterances captured in order are 1, 2, 3.
		let speech = buffer()
		for text in ["one", "two", "three"] {
			speech.append(utterance(text))
		}
		let read = speech.entriesSince(0)
		#expect(read.entries.map(\.index) == [1, 2, 3])
	}

	// -- reading ranges ------------------------------------------------------

	@Test("the range that comes back is the range READ, not the span of what had words")
	func theRangeIsTheWindow() {
		let speech = buffer()
		speech.append(utterance("first"))
		speech.append(utterance(""))
		speech.append(utterance("third"))
		let read = speech.entriesSince(1)
		#expect(read.fromIndex == 1)
		#expect(read.toIndex == 4)
		// The empty one is skipped, which is exactly why an entry cannot be
		// located by counting from `fromIndex` and carries its own index.
		#expect(read.entries.map(\.utterance.text) == ["first", "third"])
		#expect(read.entries.map(\.index) == [1, 3])
	}

	@Test("reading resumes from the previous toIndex, and nothing is read twice or skipped")
	func rangesTile() {
		let speech = buffer()
		speech.append(utterance("first"))
		let first = speech.entriesSince(0)
		speech.append(utterance("second"))
		let second = speech.entriesSince(first.toIndex)
		#expect(second.entries.map(\.utterance.text) == ["second"])
		#expect(second.fromIndex == first.toIndex)
	}

	@Test("a stale or invented bookmark answers with an empty range rather than raising")
	func staleBookmarksAreClamped() {
		let speech = buffer()
		speech.append(utterance("said"))
		let ahead = speech.entriesSince(99)
		#expect(ahead.entries.isEmpty)
		#expect(ahead.fromIndex == 99)
		#expect(ahead.toIndex == 2)
		let behind = speech.entriesSince(-5)
		#expect(behind.fromIndex == 0)
		#expect(behind.entries.map(\.utterance.text) == ["said"])
	}

	@Test("an out-of-range index reads the sentinel, so no read of a bad index can raise")
	func entryAtClamps() {
		let speech = buffer()
		#expect(speech.entry(at: 99).text.isEmpty)
		#expect(speech.entry(at: -1).text.isEmpty)
	}

	@Test("the entry keeps the instant the PRODUCER stamped, not the instant it was appended")
	func theStampIsTheProducers() {
		let speech = buffer()
		clock.advance(500)
		speech.append(utterance("said", at: 1_700_000_042.5))
		#expect(speech.last().utterance.emittedAt == 1_700_000_042.5)
		// And the sentinel has none, which is what renders as "no instant".
		#expect(speech.entry(at: 0).emittedAt == 0)
	}

	@Test("the ssml is carried verbatim beside the words, because it cannot be recovered later")
	func ssmlIsKept() {
		let speech = buffer()
		speech.append(utterance("Documents"))
		#expect(speech.last().utterance.ssml == "<speak>Documents</speak>")
	}

	// -- the observer --------------------------------------------------------

	@Test("the observer sees each utterance with words, in order")
	func theObserverIsFed() {
		let speech = buffer()
		var seen: [String] = []
		speech.setObserver { seen.append($0) }
		speech.append(utterance("first"))
		speech.append(utterance("second"))
		#expect(seen == ["first", "second"])
	}

	@Test("an utterance with no words is not announced to the observer")
	func emptyUtterancesAreNotRecorded() {
		// The transcript is read by a human afterwards; a run of blank SPEECH
		// lines would be noise in the one record a silent run leaves.
		let speech = buffer()
		var seen: [String] = []
		speech.setObserver { seen.append($0) }
		speech.append(utterance(""))
		#expect(seen.isEmpty)
		// It still occupies an index, so numbering is unaffected.
		#expect(speech.nextIndex() == 2)
	}

	// -- searching -----------------------------------------------------------

	@Test("the search matches a substring, at or AFTER the index given")
	func theLeftEdgeIsInclusive() {
		// Inclusive, deliberately: lane 1 shipped the exclusive reading and it
		// silently discarded the first utterance an action caused -- the one the
		// bookmark-act-wait pattern is always waiting for (spec 0037).
		let speech = buffer()
		speech.append(utterance("Documents, folder"))
		#expect(speech.indexOf("folder", afterIndex: 1) == 1)
		#expect(speech.indexOf("folder", afterIndex: 2) == nil)
		#expect(speech.indexOf("folder") == 1)
		#expect(speech.indexOf("Downloads") == nil)
	}

	@Test("a bookmark past the end, or before the start, does not slice from the wrong end")
	func searchIndicesAreClamped() {
		let speech = buffer()
		speech.append(utterance("said"))
		#expect(speech.indexOf("said", afterIndex: 99) == nil)
		#expect(speech.indexOf("said", afterIndex: -3) == 1)
	}

	// -- waiting -------------------------------------------------------------

	@Test("a wait returns the moment the words are already there, without sleeping")
	func waitingForWhatIsAlreadySaid() {
		let speech = buffer()
		speech.append(utterance("Documents", at: 1_700_000_001))
		let outcome = speech.waitFor("Documents", afterIndex: nil, timeout: 5)
		#expect(outcome.found)
		#expect(outcome.index == 1)
		#expect(outcome.utterance.emittedAt == 1_700_000_001)
		#expect(clock.sleeps.isEmpty)
	}

	@Test("a wait that times out is a RESULT: not found, a fresh bookmark, no words")
	func aMissIsAnAnswer() {
		let speech = buffer()
		let outcome = speech.waitFor("never said", afterIndex: nil, timeout: 5)
		#expect(!outcome.found)
		// A usable "from here" mark, so a caller that timed out can carry on.
		#expect(outcome.index == speech.nextIndex())
		#expect(outcome.utterance.text.isEmpty)
		// And it waited the whole window, in instant advances rather than seconds.
		#expect(clock.sleeps.reduce(0, +) >= 5)
	}

	@Test("a zero timeout still evaluates the buffer once")
	func zeroTimeoutStillLooks() {
		let speech = buffer()
		speech.append(utterance("said"))
		#expect(speech.waitFor("said", afterIndex: nil, timeout: 0).found)
		#expect(clock.sleeps.isEmpty)
	}

	@Test("speech counts as finished once nothing has arrived for the settle window")
	func finishingIsQuiet() {
		let speech = buffer()
		speech.append(utterance("said"))
		// Still speaking: the append was just now.
		#expect(!speech.waitToFinish(timeout: 0))
		// The wait itself advances the clock past the window, which is what the
		// injected clock is for -- this costs microseconds, not seconds.
		#expect(speech.waitToFinish(timeout: 5))
	}

	@Test("a buffer nothing was ever captured into settles once the window has passed")
	func silenceBeforeSpeechAlsoSettles() {
		// Stated rather than hidden: silence before speech starts and silence
		// after it ends are the same observable, so this asks "has the feed gone
		// quiet", never "did the reader finish saying something".
		let speech = buffer()
		clock.advance(speechFinishedSeconds + 0.1)
		#expect(speech.waitToFinish(timeout: 0))
	}

	// -- the grace window ------------------------------------------------------

	@Test("the grace window returns what was ALREADY there without sleeping at all")
	func aFullBufferIsNotWaitedOn() {
		let speech = buffer()
		speech.append(utterance("said"))
		let read = speech.collectSince(1, grace: 5)
		#expect(read.entries.map(\.utterance.text) == ["said"])
		// The predicate is checked before the first sleep, so a window over a
		// buffer that already has words costs nothing.
		#expect(clock.sleeps.isEmpty)
	}

	@Test("an empty window returns an empty result, having waited out the grace")
	func anEmptyWindowIsAFactNotAClaim() {
		// The §7.3 sentence in one assertion: nothing arrived BY THEN, which is a
		// fact. It is not a claim that nothing will, which is why no result on
		// this route carries a `complete` flag.
		let speech = buffer()
		let read = speech.collectSince(1, grace: 0.2)
		#expect(read.entries.isEmpty)
		#expect(read.fromIndex == 1)
		#expect(read.toIndex == 1)
		#expect(!clock.sleeps.isEmpty)
	}

	@Test("a zero grace reads the buffer as it stands and never sleeps")
	func zeroGraceIsALegitimateOptOut() {
		let speech = buffer()
		#expect(speech.collectSince(1, grace: 0).entries.isEmpty)
		#expect(clock.sleeps.isEmpty)
	}

	@Test("it returns EARLY on the first words, leaving the rest for the next read")
	func itReturnsOnTheFirstWords() {
		// The cost is stated rather than hidden: an utterance still in flight when
		// the first one lands is left behind, and the caller can always take it,
		// because the range it was handed says exactly where to resume.
		let speech = buffer()
		speech.append(utterance("first"))
		let read = speech.collectSince(1, grace: 5)
		#expect(read.entries.count == 1)
		speech.append(utterance("second"))
		#expect(speech.collectSince(read.toIndex, grace: 0).entries.map(\.utterance.text) == ["second"])
	}

	@Test("an utterance with no words does not end the window early")
	func anEmptyUtteranceIsNotWords() {
		// The feed carries entries that render to nothing, and the question the
		// window asks is "has SPEECH started", not "has anything arrived".
		let speech = buffer()
		speech.append(utterance(""))
		let read = speech.collectSince(1, grace: 0.2)
		#expect(read.entries.isEmpty)
		#expect(!clock.sleeps.isEmpty)
	}

	@Test("a stale bookmark clamps rather than raising, like every other read")
	func aStaleBookmarkClamps() {
		let speech = buffer()
		speech.append(utterance("said"))
		#expect(speech.collectSince(-5, grace: 0).fromIndex == 0)
	}
}
