// HEADLESS INTEGRATION -- the real stack, end to end, with no socket and no
// VoiceOver: a real Session over the real JsonLinesChannel over a loopback
// transport, driving the real handlers the real Registry builds.
//
// WHAT THIS CATCHES THAT NO UNIT TEST CAN: every unit above runs against a graph
// its own test assembled, so a handler wired to the wrong command, a result that
// does not encode, or a frame that does not survive the round trip would pass all
// of them. This is lane 1's tests/integration/ in its macOS instance, and it runs
// in CI.

import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("session round trip")
struct SessionRoundTripTests {
	/// Drive a whole session from the outside, exactly as the server would: write
	/// request lines, read reply lines, and let the bridge run on its own thread.
	private final class Peer {
		let client: LoopbackTransport
		private let thread: Thread
		let transcript = FakeTranscript()
		let signals = FakeSessionSignals()

		init(handlers: [String: any CommandHandler]? = nil, attended: Bool = true) {
			let (bridgeEnd, clientEnd) = LoopbackTransport.pair()
			client = clientEnd
			let session = Wiring.session(
				over: bridgeEnd,
				clock: RealClock(),
				transcript: transcript,
				signals: signals,
				config: SessionConfig(readerVersion: "macOS 15.0.0", attended: attended),
				handlers: handlers
					?? Registry.build(
						factory: VoiceOverAdapterFactory(),
						readerVersion: "macOS 15.0.0",
						bridgeVersion: "1.2.3"
					)
			)
			thread = Thread { session.run() }
			thread.start()
		}

		func send(_ line: String) throws {
			try client.sendAll(Data((line + "\n").utf8))
		}

		func send(id: Int, cmd: String, params: [String: JSONValue] = [:]) throws {
			let request = Request(id: id, cmd: cmd, params: params)
			try client.sendAll(try JSONEncoder().encode(request) + Data("\n".utf8))
		}

		func reply() throws -> Response {
			guard let line = client.readLine() else {
				throw ValidationError(path: "", reason: "no reply arrived")
			}
			return try JSONDecoder().decode(Response.self, from: Data(line.utf8))
		}

		func hangUp() {
			client.close()
		}
	}

	@Test("a live handshake answers with this bridge's identity and its capability set")
	func theHandshake() throws {
		let peer = Peer()
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		let response = try peer.reply()
		guard case .success(let value) = try response.outcome() else {
			Issue.record("the handshake failed: \(response)")
			return
		}
		let hello = try value.decoded(as: HelloResult.self)
		#expect(hello.reader.name == "voiceover")
		#expect(hello.protocolVersion == 1)
		#expect(hello.mode == .live)
		#expect(hello.capabilities.isEmpty)
		#expect(hello.attended == true)
		#expect(hello.bridgeVersion == "1.2.3")
		peer.hangUp()
	}

	@Test("echo carries an arbitrary payload through every layer unchanged")
	func echoSurvivesTheWholeStack() throws {
		// The one command whose entire value is this test: encode, frame, decode,
		// validate, dispatch, re-encode, re-frame.
		let peer = Peer()
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		let payload = JSONValue.object([
			"unicode": .string("olá — ✓"),
			"nested": .array([.int(1), .null, .bool(false), .double(2.5)]),
		])
		try peer.send(id: 2, cmd: "echo", params: ["payload": payload])
		let response = try peer.reply()
		guard case .success(let value) = try response.outcome() else {
			Issue.record("echo failed: \(response)")
			return
		}
		#expect(try value.decoded(as: EchoResult.self).payload == payload)
		peer.hangUp()
	}

	@Test("a silent handshake is refused with a reason a human can act on")
	func silentIsRefusedEndToEnd() throws {
		let peer = Peer()
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("silent"), "protocolVersion": .int(1)])
		guard case .failure(let error) = try peer.reply().outcome() else {
			Issue.record("expected silent mode to be refused")
			return
		}
		#expect(error.message.contains("13.6"))
	}

	@Test("a wrong protocol version ends the handshake, and the reply says both numbers")
	func aVersionMismatchEndsIt() throws {
		let peer = Peer()
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(99)])
		guard case .failure(let error) = try peer.reply().outcome() else {
			Issue.record("expected the version mismatch to be refused")
			return
		}
		#expect(error.message.contains("99"))
		#expect(error.message.contains("1"))
	}

	@Test("a command before hello is refused and the connection ends")
	func nothingBeforeHello() throws {
		let peer = Peer()
		try peer.send(id: 1, cmd: "ping")
		guard case .failure(let error) = try peer.reply().outcome() else {
			Issue.record("expected the handshake to be enforced")
			return
		}
		#expect(error.message.contains("hello"))
	}

	@Test("garbage mid-session is noted and the session goes on answering")
	func garbageIsSurvived() throws {
		let peer = Peer()
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		try peer.send("this is not JSON")
		try peer.send(id: 3, cmd: "ping")
		let response = try peer.reply()
		#expect(response.id == 3)
		peer.hangUp()
	}

	@Test("bye is acknowledged, and then the bridge closes its end")
	func byeEndsIt() throws {
		let peer = Peer()
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		try peer.send(id: 2, cmd: "bye")
		let response = try peer.reply()
		#expect(response.id == 2)
		#expect(try #require(response.result).decoded(as: AckResult.self).ok)
		// The transcript is the record, so it is what proves the session ended for
		// the reason the client gave rather than because the socket dropped.
		let deadline = Date().addingTimeInterval(2)
		while peer.transcript.closedReasons.isEmpty, Date() < deadline {
			usleep(2000)
		}
		#expect(peer.transcript.closedReasons.last == "client-bye")
		#expect(peer.signals.endedCount == 1)
	}

	@Test("two frames arriving in ONE write are both answered")
	func twoFramesInOneWrite() throws {
		// protocol.md §1's draining rule, proven through the whole stack: a server
		// that batched two commands must not have the second one wait for whatever
		// happens to arrive next.
		let peer = Peer()
		let hello = String(
			decoding: try JSONEncoder().encode(
				Request(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
			),
			as: UTF8.self
		)
		let ping = String(decoding: try JSONEncoder().encode(Request(id: 2, cmd: "ping")), as: UTF8.self)
		try peer.client.sendAll(Data((hello + "\n" + ping + "\n").utf8))
		#expect(try peer.reply().id == 1)
		#expect(try peer.reply().id == 2)
		peer.hangUp()
	}
}
