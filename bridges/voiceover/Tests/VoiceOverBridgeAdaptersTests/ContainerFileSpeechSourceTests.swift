// Mirrors Sources/VoiceOverBridgeAdapters/ContainerFileSpeechSource.swift.

import Fakes
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("ContainerFileSpeechSource")
struct ContainerFileSpeechSourceTests {
	private let tailer = FakeLineTailer()
	private let clock = FakeClock()

	private func started() -> (source: ContainerFileSpeechSource, buffer: SpeechBuffer) {
		let buffer = SpeechBuffer(clock: clock)
		let source = ContainerFileSpeechSource(tailer: tailer)
		source.start(buffer)
		return (source, buffer)
	}

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

	@Test("a synthesize line becomes one captured utterance")
	func aSynthesizeLineIsSpeech() {
		let (_, buffer) = started()
		tailer.deliver(synthesizeLine())
		#expect(buffer.last().utterance.text == "Documents, folder")
		#expect(buffer.last().index == 1)
	}

	@Test("a cancel line is NOT speech, and cancels arrive before every utterance")
	func cancelIsNotSpeech() {
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
		let (_, buffer) = started()
		tailer.deliver("")
		tailer.deliver("{not json")
		tailer.deliver("[1, 2, 3]")
		tailer.deliver(#"{"event":"synthesize"}"#)  // no words at all, but well formed
		tailer.deliver(synthesizeLine(text: "still delivered"))
		#expect(buffer.last().utterance.text == "still delivered")
	}

	@Test("the words are re-derived from the SSML by this half's own entity")
	func theWordsComeFromTheSsml() {
		let (_, buffer) = started()
		tailer.deliver(
			#"{"at":1.0,"event":"synthesize","seq":1,"ssml":"<speak>from the markup</speak>","text":"from the field"}"#
		)
		#expect(buffer.last().utterance.text == "from the markup")
	}

	@Test("a line with no SSML falls back to the extension's own rendering")
	func theFallbackKeepsTheUtterance() {
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

	@Test("THE EXTENSION'S SEQUENCE COUNTER IS DISCARDED, and the buffer's own numbering stands")
	func theCounterIsDiscarded() {
		let (_, buffer) = started()
		tailer.deliver(synthesizeLine(text: "before the relaunch", seq: 7))
		tailer.deliver(synthesizeLine(text: "after the relaunch", seq: 1))
		let read = buffer.entriesSince(0)
		#expect(read.entries.map(\.index) == [1, 2])
		#expect(read.entries.map(\.utterance.text) == ["before the relaunch", "after the relaunch"])
	}

	@Test("starting the source starts the tailer, and stopping it stops the tailer")
	func theLifecycleIsPassedThrough() {
		let (source, _) = started()
		#expect(tailer.startCount == 1)
		source.stop()
		#expect(tailer.stopCount == 1)
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

	@Test("the feed's path is the extension's container, derived from a passed-in home")
	func thePath() {
		// Must match the capture extension's own derivation, or the feed stays empty while the reader talks.
		#expect(
			ContainerFileSpeechSource.containerFilePath(home: "/Users/tester")
				== "/Users/tester/Library/Containers/org.screen-readers-mcp.spike.capture.voice/Data/voiceover-capture.jsonl"
		)
	}
}
