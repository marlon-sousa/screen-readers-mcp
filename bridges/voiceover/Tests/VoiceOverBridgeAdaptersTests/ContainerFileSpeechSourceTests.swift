// Mirrors Sources/VoiceOverBridgeAdapters/ContainerFileSpeechSource.swift.
//
// THE CAPTURE FEED'S LOGIC, PROVEN WITH NO EXTENSION AND NO VOICEOVER. Every
// line below is one the capture voice really writes -- the shapes are
// `CaptureEventLine`'s, rendered from `CaptureEvent.Kind` and the fields
// `CaptureController` attaches -- so this is the contract between two processes
// that meet only at a file, asserted from the reading side.
//
// The fake tailer delivers on the caller's thread, so nothing here waits. What
// it cannot prove is that a real file behaves like it; that is
// FileLineTailerTests, which uses one.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("ContainerFileSpeechSource")
struct ContainerFileSpeechSourceTests {
	private let tailer = FakeLineTailer()
	private let clock = FakeClock()

	/// A source started against a buffer, which is the only way it is ever used.
	private func started() -> (source: ContainerFileSpeechSource, buffer: SpeechBuffer) {
		let buffer = SpeechBuffer(clock: clock)
		let source = ContainerFileSpeechSource(tailer: tailer)
		source.start(buffer)
		return (source, buffer)
	}

	/// One `synthesize` line, in the shape the capture voice writes: sorted keys,
	/// an epoch stamp, and both renderings of the utterance.
	private func synthesizeLine(
		text: String = "Documents, folder",
		ssml: String? = nil,
		seq: Int = 1,
		at: Double = 1_700_000_000.5,
		voice: String = "org.screen-readers-mcp.spike.capture.voice.org.screen-readers-mcp.spike.capture"
	) -> String {
		let markup = ssml ?? "<speak><prosody rate=\"1.4\">\(text)</prosody></speak>"
		return """
			{"at":\(at),"event":"synthesize","seq":\(seq),"silent":false,\
			"ssml":"\(markup.replacingOccurrences(of: "\"", with: "\\\""))",\
			"text":"\(text)","utterance_language":"<unknown>","voice":"\(voice)"}
			"""
	}

	// -- what is an utterance ------------------------------------------------

	@Test("a synthesize line becomes one captured utterance")
	func aSynthesizeLineIsSpeech() {
		let (_, buffer) = started()
		tailer.deliver(synthesizeLine())
		#expect(buffer.last().utterance.text == "Documents, folder")
		#expect(buffer.last().index == 1)
	}

	@Test("a cancel line is NOT speech, and cancels arrive before every utterance")
	func cancelIsNotSpeech() {
		// VoiceOver cancels before each new utterance (spec 0041, A3), so a
		// source that mistook one for speech would double every entry.
		let (_, buffer) = started()
		tailer.deliver(#"{"at":1700000000.0,"cb_count":3,"event":"cancel","underruns":0}"#)
		#expect(buffer.nextIndex() == 1)
	}

	@Test("the provider's own observations are not speech either")
	func otherEventsAreIgnored() {
		let (_, buffer) = started()
		for line in [
			#"{"at":1.0,"event":"audio-unit-created","background_cleared":true}"#,
			#"{"at":2.0,"event":"allocate-render-resources","rate":22050}"#,
			#"{"at":3.0,"event":"speech-voices-read","count":1}"#,
		] {
			tailer.deliver(line)
		}
		#expect(buffer.nextIndex() == 1)
	}

	@Test("a line that is not JSON, or not an object, is skipped rather than thrown")
	func rubbishIsSkipped() {
		// This runs on a capture thread with nobody to answer to, and the feed is
		// written by another process: one torn line must not end a session or
		// stop the lines after it.
		let (_, buffer) = started()
		tailer.deliver("")
		tailer.deliver("{not json")
		tailer.deliver("[1, 2, 3]")
		tailer.deliver(#"{"event":"synthesize"}"#)  // no words at all, but well formed
		tailer.deliver(synthesizeLine(text: "still delivered"))
		#expect(buffer.last().utterance.text == "still delivered")
	}

	// -- what an utterance says ----------------------------------------------

	@Test("the words are re-derived from the SSML by this half's own entity")
	func theWordsComeFromTheSsml() {
		let (_, buffer) = started()
		// The `text` field says one thing and the SSML another. The SSML wins:
		// what the agent reads back is decided here, not by whichever version of
		// the extension happens to be installed.
		tailer.deliver(
			#"{"at":1.0,"event":"synthesize","seq":1,"ssml":"<speak>from the markup</speak>","text":"from the field"}"#
		)
		#expect(buffer.last().utterance.text == "from the markup")
	}

	@Test("a line with no SSML falls back to the extension's own rendering")
	func theFallbackKeepsTheUtterance() {
		// Losing an utterance is worse than rendering it the other half's way.
		let (_, buffer) = started()
		tailer.deliver(#"{"at":1.0,"event":"synthesize","seq":1,"text":"only the field"}"#)
		#expect(buffer.last().utterance.text == "only the field")
	}

	@Test("the raw SSML and the voice ride along, because neither can be recovered later")
	func theEvidenceIsKept() {
		let (_, buffer) = started()
		tailer.deliver(synthesizeLine(text: "Documents", voice: "ours"))
		#expect(buffer.last().utterance.ssml.contains("<prosody rate=\"1.4\">"))
		#expect(buffer.last().utterance.voice == "ours")
	}

	@Test("the instant is the PRODUCER's stamp, taken when the line was written")
	func theStampIsTheProducers() {
		// Not the moment this side read it: reading the clock here would fold the
		// feed's tail latency into every stamp, silently.
		let (_, buffer) = started()
		tailer.deliver(synthesizeLine(at: 1_700_000_042.25))
		#expect(buffer.last().utterance.emittedAt == 1_700_000_042.25)
	}

	@Test("a line with no stamp reports no instant, rather than inventing one")
	func anUnstampedLine() {
		let (_, buffer) = started()
		tailer.deliver(#"{"event":"synthesize","seq":1,"ssml":"<speak>said</speak>"}"#)
		#expect(buffer.last().utterance.emittedAt == 0)
	}

	// -- whose numbering wins ------------------------------------------------

	@Test("THE EXTENSION'S SEQUENCE COUNTER IS DISCARDED, and the buffer's own numbering stands")
	func theCounterIsDiscarded() {
		// The system relaunches the extension freely and the counter restarts
		// when it does (spec 0041, A4). Here it restarts mid-feed: the indices an
		// agent sees must not restart with it, or a bookmark taken before an
		// action would point after it.
		let (_, buffer) = started()
		tailer.deliver(synthesizeLine(text: "before the relaunch", seq: 7))
		tailer.deliver(synthesizeLine(text: "after the relaunch", seq: 1))
		let read = buffer.entriesSince(0)
		#expect(read.entries.map(\.index) == [1, 2])
		#expect(read.entries.map(\.utterance.text) == ["before the relaunch", "after the relaunch"])
	}

	// -- lifecycle -----------------------------------------------------------

	@Test("starting the source starts the tailer, and stopping it stops the tailer")
	func theLifecycleIsPassedThrough() {
		let (source, _) = started()
		#expect(tailer.startCount == 1)
		source.stop()
		#expect(tailer.stopCount == 1)
		// Idempotent, because teardown calls it on every path.
		source.stop()
		#expect(tailer.stopCount == 2)
	}

	@Test("nothing arrives after a stop")
	func stoppedMeansStopped() {
		let (source, buffer) = started()
		source.stop()
		tailer.deliver(synthesizeLine())
		#expect(buffer.nextIndex() == 1)
	}

	// -- where the file is ---------------------------------------------------

	@Test("the feed's path is the extension's container, derived from a passed-in home")
	func thePath() {
		// Duplicated from the extension's own derivation on purpose: two
		// processes must compute one path from one rule or the feed stays empty
		// on a machine where the reader is plainly talking. Nothing here reads
		// the environment.
		#expect(
			ContainerFileSpeechSource.containerFilePath(home: "/Users/tester")
				== "/Users/tester/Library/Containers/org.screen-readers-mcp.spike.capture.voice/Data/voiceover-capture.jsonl"
		)
	}
}
