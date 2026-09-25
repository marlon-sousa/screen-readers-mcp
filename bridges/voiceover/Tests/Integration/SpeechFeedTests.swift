// Headless integration: the capture feed end to end, a real file through the real tailer, source, buffer and handlers.

import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("the capture feed")
struct SpeechFeedTests {
	private final class Peer {
		let client: LoopbackTransport
		let transcript = FakeTranscript()
		private let directory: URL
		let feedPath: String
		private let thread: Thread

		init() {
			directory = URL(fileURLWithPath: NSTemporaryDirectory())
				.appendingPathComponent("capture-feed-\(UUID().uuidString)")
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			feedPath = directory.appendingPathComponent("voiceover-capture.jsonl").path

			let (bridgeEnd, clientEnd) = LoopbackTransport.pair()
			client = clientEnd
			let session = Wiring.session(
				over: bridgeEnd,
				clock: RealClock(),
				transcript: transcript,
				signals: FakeSessionSignals(),
				config: SessionConfig(readerVersion: "macOS 15.0.0"),
				handlers: Registry.build(
					factory: testAdapterFactory(capturePath: feedPath),
					readerVersion: "macOS 15.0.0",
					bridgeVersion: "1.2.3"
				)
			)
			thread = Thread { session.run() }
			thread.start()
		}

		func emit(_ line: String) {
			if let handle = FileHandle(forWritingAtPath: feedPath) {
				defer { try? handle.close() }
				try? handle.seekToEnd()
				try? handle.write(contentsOf: Data((line + "\n").utf8))
			} else {
				try? Data((line + "\n").utf8).write(to: URL(fileURLWithPath: feedPath))
			}
		}

		func speak(_ text: String, at instant: Double) {
			emit(
				"""
				{"at":\(instant),"event":"synthesize","seq":1,"silent":false,\
				"ssml":"<speak><prosody rate=\\"1.4\\">\(text)</prosody></speak>",\
				"text":"\(text)","voice":"ours"}
				"""
			)
		}

		func send(id: Int, cmd: String, params: [String: JSONValue] = [:]) throws {
			let request = Request(id: id, cmd: cmd, params: params)
			try client.sendAll(try JSONEncoder().encode(request) + Data("\n".utf8))
		}

		func value(_ id: Int, _ cmd: String, _ params: [String: JSONValue] = [:]) throws -> JSONValue {
			try send(id: id, cmd: cmd, params: params)
			guard let line = client.readLine() else {
				throw ValidationError(path: cmd, reason: "no reply arrived")
			}
			let response = try JSONDecoder().decode(Response.self, from: Data(line.utf8))
			guard case .success(let value) = try response.outcome() else {
				throw ValidationError(path: cmd, reason: "failed: \(response)")
			}
			return value
		}

		func handshake() throws {
			_ = try value(1, "hello", ["mode": .string("live"), "protocolVersion": .int(1)])
		}

		func finish() {
			client.close()
			try? FileManager.default.removeItem(at: directory)
		}
	}

	/// Index 1 of every session's buffer is the handshake's capture probe, so a session's own speech starts at 2.
	private let handshakeSpeech = [captureProbeUtterance]

	@Test("a line appended after the handshake is readable as speech, with its own stamp")
	func aLineBecomesSpeech() throws {
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		peer.speak("Documents, folder", at: 1_700_000_000.5)
		let waited = try peer.value(
			2, "waitForSpeech", ["text": .string("Documents"), "timeout": .double(5)]
		).decoded(as: WaitForSpeechResult.self)
		#expect(waited.found)
		#expect(waited.text == "Documents, folder")
		#expect(waited.index == 2)
		#expect(waited.emittedAt == Wallclock.format(1_700_000_000.5))

		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.map(\.text) == handshakeSpeech + ["Documents, folder"])
		#expect(read.toIndex == 3)
	}

	@Test("the bookmark, the action and the read tile the way an agent uses them")
	func theBookmarkPattern() throws {
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		peer.speak("background chatter", at: 1_700_000_000)
		_ = try peer.value(2, "waitForSpeech", ["text": .string("background"), "timeout": .double(5)])

		let mark = try peer.value(3, "getNextSpeechIndex").decoded(as: NextIndexResult.self).index
		peer.speak("the answer", at: 1_700_000_001)
		_ = try peer.value(4, "waitForSpeech", ["text": .string("answer"), "timeout": .double(5)])

		let read = try peer.value(5, "getSpeech", ["sinceIndex": .int(mark)]).decoded(
			as: SpeechResult.self)
		#expect(read.entries.map(\.text) == ["the answer"])
		#expect(read.fromIndex == mark)
	}

	@Test("the whole session's speech is still there at the end -- the ring is unbounded")
	func nothingAgesOut() throws {
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		for index in 1...25 {
			peer.speak("utterance \(index)", at: 1_700_000_000 + Double(index))
		}
		_ = try peer.value(2, "waitForSpeech", ["text": .string("utterance 25"), "timeout": .double(5)])

		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.count == 26)
		#expect(read.entries.map(\.index) == Array(1...26))
		#expect(read.entries.map(\.text).first == captureProbeUtterance)
		let last = try peer.value(4, "getLastSpeech").decoded(as: LastSpeechResult.self)
		#expect(last.text == "utterance 25")
		#expect(last.index == 26)
	}

	@Test("what the reader said reaches the transcript without the agent asking for it")
	func theTranscriptRecordsUnasked() throws {
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		peer.speak("recorded bridge-side", at: 1_700_000_000)
		_ = try peer.value(2, "waitForSpeech", ["text": .string("recorded"), "timeout": .double(5)])
		#expect(peer.transcript.speeches == handshakeSpeech + ["recorded bridge-side"])
	}

	@Test("cancels and the provider's own observations never reach the buffer")
	func onlySpeechIsSpeech() throws {
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		peer.emit(#"{"at":1700000000.0,"event":"audio-unit-created","background_cleared":true}"#)
		peer.emit(#"{"at":1700000000.1,"cb_count":4,"event":"cancel","underruns":0}"#)
		peer.speak("the only utterance", at: 1_700_000_001)
		peer.emit(#"{"at":1700000001.5,"cb_count":9,"event":"cancel","underruns":0}"#)

		_ = try peer.value(2, "waitForSpeech", ["text": .string("only"), "timeout": .double(5)])
		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.map(\.text) == handshakeSpeech + ["the only utterance"])
		#expect(read.toIndex == 3)
	}

	@Test("speech settles once the feed goes quiet")
	func itSettles() throws {
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		peer.speak("said", at: 1_700_000_000)
		_ = try peer.value(2, "waitForSpeech", ["text": .string("said"), "timeout": .double(5)])
		let finished = try peer.value(3, "waitForSpeechToFinish", ["timeout": .double(5)]).decoded(
			as: WaitToFinishResult.self)
		#expect(finished.finished)
	}

	@Test("history already in the file is NOT replayed into a new session")
	func theFeedIsTailedFromTheEnd() throws {
		let peer = Peer()
		defer { peer.finish() }
		peer.speak("said before this session existed", at: 1_699_000_000)
		try peer.handshake()

		peer.speak("said during it", at: 1_700_000_000)
		_ = try peer.value(2, "waitForSpeech", ["text": .string("during"), "timeout": .double(5)])
		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.map(\.text) == handshakeSpeech + ["said during it"])
	}
}
