// HEADLESS INTEGRATION -- the capture feed end to end, with no extension and no
// VoiceOver: a real file, the real FileLineTailer, the real
// ContainerFileSpeechSource, the real SpeechBuffer and the real handlers, driven
// over the wire exactly as the server drives them.
//
// WHAT THIS CATCHES THAT NO UNIT TEST CAN. Every unit above runs against a graph
// its own test assembled, so a factory that built a source nobody started, a
// handshake that started capture into a buffer the context does not hold, or a
// result that does not encode would pass all of them and answer nothing here.
// This is the one tier where a line appended by another writer becomes an
// `emittedAt` an agent can read.
//
// THE FILE STANDS IN FOR THE EXTENSION, and that substitution is the whole
// premise of the route: the capture voice is a sandboxed process whose only door
// out is appending JSON lines to a file in its container (spec 0041, B1/B2), and
// a bridge that reads any file the same way is reading the real one the same
// way. What this cannot prove is that VoiceOver reaches the extension at all --
// that is the live checklist at 13.11.

import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("the capture feed")
struct SpeechFeedTests {
	/// A session driven from the outside, over a feed file this test owns.
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
				// A REAL clock, because this tier is about the real stack: the wait
				// loops sleep for real, in 30 ms polls, and the assertions below
				// still finish in a fraction of a second.
				clock: RealClock(),
				transcript: transcript,
				signals: FakeSessionSignals(),
				config: SessionConfig(readerVersion: "macOS 15.0.0"),
				handlers: Registry.build(
					factory: VoiceOverAdapterFactory(capturePath: feedPath),
					readerVersion: "macOS 15.0.0",
					bridgeVersion: "1.2.3"
				)
			)
			thread = Thread { session.run() }
			thread.start()
		}

		/// Append one line, as the capture voice's container-file sink does.
		func emit(_ line: String) {
			if let handle = FileHandle(forWritingAtPath: feedPath) {
				defer { try? handle.close() }
				try? handle.seekToEnd()
				try? handle.write(contentsOf: Data((line + "\n").utf8))
			} else {
				try? Data((line + "\n").utf8).write(to: URL(fileURLWithPath: feedPath))
			}
		}

		/// One `synthesize` line in the shape `CaptureEventLine` renders.
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
		#expect(waited.index == 1)
		// The producer's own instant, rendered in the contract's shape -- the
		// number that makes "X happened promptly after Y" answerable (spec 0028).
		#expect(waited.emittedAt == Wallclock.format(1_700_000_000.5))

		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.map(\.text) == ["Documents, folder"])
		#expect(read.toIndex == 2)
	}

	@Test("the bookmark, the action and the read tile the way an agent uses them")
	func theBookmarkPattern() throws {
		// The documented pattern, over the wire: mark, act, read from the mark.
		// Speech that arrived BEFORE the mark must not come back, or an assertion
		// about what an action caused would be answered with background chatter.
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
		// protocol.md §7: nothing ages out of the speech ring while the session
		// lives, so `sinceIndex: 0` answers with everything at the end of a run.
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		for index in 1...25 {
			peer.speak("utterance \(index)", at: 1_700_000_000 + Double(index))
		}
		_ = try peer.value(2, "waitForSpeech", ["text": .string("utterance 25"), "timeout": .double(5)])

		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.count == 25)
		#expect(read.entries.map(\.index) == Array(1...25))
		let last = try peer.value(4, "getLastSpeech").decoded(as: LastSpeechResult.self)
		#expect(last.text == "utterance 25")
		#expect(last.index == 25)
	}

	@Test("what the reader said reaches the transcript without the agent asking for it")
	func theTranscriptRecordsUnasked() throws {
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		peer.speak("recorded bridge-side", at: 1_700_000_000)
		_ = try peer.value(2, "waitForSpeech", ["text": .string("recorded"), "timeout": .double(5)])
		#expect(peer.transcript.speeches == ["recorded bridge-side"])
	}

	@Test("cancels and the provider's own observations never reach the buffer")
	func onlySpeechIsSpeech() throws {
		// A cancel arrives before EVERY utterance on this route (spec 0041, A3),
		// so this is the ordinary traffic of the feed rather than an odd case.
		let peer = Peer()
		defer { peer.finish() }
		try peer.handshake()

		peer.emit(#"{"at":1700000000.0,"event":"audio-unit-created","background_cleared":true}"#)
		peer.emit(#"{"at":1700000000.1,"cb_count":4,"event":"cancel","underruns":0}"#)
		peer.speak("the only utterance", at: 1_700_000_001)
		peer.emit(#"{"at":1700000001.5,"cb_count":9,"event":"cancel","underruns":0}"#)

		_ = try peer.value(2, "waitForSpeech", ["text": .string("only"), "timeout": .double(5)])
		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.map(\.text) == ["the only utterance"])
		#expect(read.toIndex == 2)
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
		// The capture voice appends across every launch of the reader. A session
		// that read from the top would answer its first getSpeech with speech
		// from yesterday, indistinguishable from what it had just caused.
		let peer = Peer()
		defer { peer.finish() }
		peer.speak("said before this session existed", at: 1_699_000_000)
		try peer.handshake()

		peer.speak("said during it", at: 1_700_000_000)
		_ = try peer.value(2, "waitForSpeech", ["text": .string("during"), "timeout": .double(5)])
		let read = try peer.value(3, "getSpeech", ["sinceIndex": .int(0)]).decoded(as: SpeechResult.self)
		#expect(read.entries.map(\.text) == ["said during it"])
	}
}
