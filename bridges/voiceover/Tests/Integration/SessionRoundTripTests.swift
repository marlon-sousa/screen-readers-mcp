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

		init(
			handlers: [String: any CommandHandler]? = nil,
			attended: Bool = true,
			lifecycle: FakeProviderLifecycle = FakeProviderLifecycle(),
			scripts: FakeAppleScriptRunner = FakeAppleScriptRunner(),
			permissions: FakePermissionBroker = FakePermissionBroker(),
			poster: FakeEventPoster = FakeEventPoster()
		) {
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
						factory: testAdapterFactory(
							lifecycle: lifecycle, scripts: scripts, permissions: permissions, poster: poster
						),
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
		// What this build actually serves, announced end to end -- the server gates
		// its speech tools on exactly this string arriving here.
		#expect(hello.capabilities == [.speech, .gestures, .typing])
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

	@Test("A SILENT HANDSHAKE IS ESTABLISHED NOW, and the reply says silent")
	func silentIsEstablishedEndToEnd() throws {
		// The end-to-end half of 13.6: this test asserted a REFUSAL until the
		// marker file made the promise keepable. What must be true now is that the
		// mode the client asked for is the mode it gets -- a session that reported
		// `mode: silent` while the machine talked normally is the exact failure the
		// refusal existed to prevent, and the way to keep preventing it is to check
		// that silence is actually in force.
		let peer = Peer()
		try peer.send(
			id: 1, cmd: "hello", params: ["mode": .string("silent"), "protocolVersion": .int(1)])
		guard case .success(let value) = try peer.reply().outcome() else {
			Issue.record("expected silent mode to be established")
			return
		}
		#expect(try value.decoded(as: HelloResult.self).mode == .silent)

		// And `ping` says words are being withheld right now, which is the one
		// channel protocol.md §6.1 gives an agent for asking.
		try peer.send(id: 2, cmd: "ping")
		guard case .success(let pong) = try peer.reply().outcome() else {
			Issue.record("ping failed")
			return
		}
		#expect(try pong.decoded(as: PingResult.self).suppressing == true)
		peer.hangUp()
	}

	@Test("a silent handshake on a machine that cannot deliver silence is REFUSED, by name")
	func silentIsRefusedWhenTheEdgeCannotDeliver() throws {
		// The refusal did not disappear; it moved to the one place that can ask
		// whether this machine can keep the promise. A voice that is not published
		// cannot be selected, so nothing can be silenced -- and the agent is told
		// which condition it is and what repairs it, rather than being handed a
		// session that quietly means something else.
		let peer = Peer(lifecycle: FakeProviderLifecycle(machineState: .notRegistered))
		try peer.send(
			id: 1, cmd: "hello", params: ["mode": .string("silent"), "protocolVersion": .int(1)])
		guard case .failure(let error) = try peer.reply().outcome() else {
			Issue.record("expected silent mode to be refused on an unusable reader edge")
			return
		}
		#expect(error.message.contains(ReaderCondition.providerNotRunning.rawValue))
		#expect(error.message.contains("pluginkit"))
	}

	@Test("a LIVE handshake on the same machine is NOT refused, because selecting applies live")
	func liveSurvivesAnUnhealthyEdge() throws {
		// Not squeamishness, and not an inconsistency: writing the voice takes
		// effect live, in both directions (spec 0047, finding 17), so a live
		// session that starts unhealthy can become healthy while it runs. Silence
		// promised at the handshake has to hold from the handshake.
		let peer = Peer(lifecycle: FakeProviderLifecycle(machineState: .notRegistered))
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		guard case .success(let value) = try peer.reply().outcome() else {
			Issue.record("expected a live session to be established anyway")
			return
		}
		#expect(try value.decoded(as: HelloResult.self).mode == .live)
		// And the transcript says why, by name, for the human reading it later.
		#expect(peer.transcript.notes.contains { $0.contains(ReaderCondition.providerNotRunning.rawValue) })
		peer.hangUp()
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

	@Test("a pressGesture off the wire reaches the reader as a COMMANDER-addressed script")
	func aGestureReachesTheReaderEdge() throws {
		// THE TEST THE UNITS CANNOT WRITE, and 13.6's lesson applied: every unit
		// above runs against a graph its own test assembled, so a handler wired to
		// the wrong command name, a result that does not encode, or an adapter the
		// factory never actually builds would pass all of them. What is asserted
		// here is the whole path -- a JSON frame in, the real Registry's handler,
		// the real VoiceOverAdapterFactory's sender, and the script text that would
		// have gone to `osascript`.
		let scripts = FakeAppleScriptRunner()
		let peer = Peer(scripts: scripts)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(
			id: 2, cmd: "pressGesture",
			params: ["gestures": .array([.string("go to desktop")]), "graceMs": .int(0)])
		let response = try peer.reply()
		guard case .success(let value) = try response.outcome() else {
			Issue.record("pressGesture failed: \(response)")
			return
		}
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["go to desktop"])
		// Nothing spoke, so the window is empty -- which is a fact about an
		// instant and never a claim that the command said nothing (protocol.md
		// §7.3). And `state` stays nil: no `state` capability on this reader.
		#expect(result.speech.isEmpty)
		#expect(result.state == nil)

		// The script the real sender built, off the real wire request. This is the
		// end-to-end form of the finding that unblocked this entry.
		let script = try #require(scripts.scripts.first)
		#expect(script == "tell application \"VoiceOver\" to tell commander to perform command \"go to desktop\"")
		#expect(peer.transcript.gestures == ["go to desktop"])
		peer.hangUp()
	}

	@Test("a typeText off the wire reaches the event poster as the keystrokes it asked for")
	func typedTextReachesTheEventPoster() throws {
		// THE TEST THE UNITS CANNOT WRITE, and 13.6's lesson applied a second time:
		// every unit above runs against a graph its own test assembled, so a
		// handler wired to the wrong command name, a typer the factory never builds,
		// or a result that does not encode would pass all of them. What is asserted
		// here is the whole path -- a JSON frame in, the real Registry's handler,
		// the real VoiceOverAdapterFactory's typer, and what would have gone to the
		// window server.
		let poster = FakeEventPoster()
		let peer = Peer(poster: poster)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(id: 2, cmd: "typeText", params: ["text": .string("caf\u{00E9} \u{2014} 50%")])
		let response = try peer.reply()
		guard case .success(let value) = try response.outcome() else {
			Issue.record("typeText failed: \(response)")
			return
		}
		let result = try value.decoded(as: TypeResult.self)
		// The LENGTH of what was sent, never the text (protocol.md §5).
		#expect(result.typed == 10)
		// Nothing spoke, so the window is empty -- a fact about an instant and
		// never a claim that nothing will be said (§7.3). `state` stays nil.
		#expect(result.speech.isEmpty)
		#expect(result.state == nil)

		// What the real typer handed the seam, off the real wire request: every
		// character, in order, each chunk as a down and then an up.
		#expect(poster.typedText == "caf\u{00E9} \u{2014} 50%")
		#expect(poster.posted.count == 2)
		#expect(poster.posted.map(\.keyDown) == [true, false])
		// And the record says how much was typed and cannot say what.
		#expect(peer.transcript.typedLengths == [10])
		peer.hangUp()
	}

	@Test("A SESSION THAT ONLY PRESSES COMMANDS NEVER ASKS FOR THE ACCESSIBILITY GRANT")
	func gesturesNeverTriggerAPermissionRequest() throws {
		// 13.8'S WHOLE CLAIM, ASSERTED END TO END RATHER THAN INTENDED. The two
		// halves of input cost different permissions on macOS (spec 0041) and
		// Windows has no equivalent gate, so this is the one design lever lane 3
		// has that lane 1 cannot have -- and it is worth only as much as its
		// checkability. A handshake, a gesture and a speech read go past here
		// without the broker being asked anything at all; the first `typeText`
		// asks, and nothing else in the bridge ever does.
		let permissions = FakePermissionBroker(state: .notGranted)
		let peer = Peer(permissions: permissions)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		try peer.send(
			id: 2, cmd: "pressGesture",
			params: ["gestures": .array([.string("go to desktop")]), "graceMs": .int(0)])
		_ = try peer.reply()
		try peer.send(id: 3, cmd: "getNextSpeechIndex")
		_ = try peer.reply()
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)

		// And now the one command that may ask. The grant is not held, so the
		// reply says what to do about it rather than reporting a success that
		// typed nothing anywhere.
		try peer.send(id: 4, cmd: "typeText", params: ["text": .string("hello")])
		let refused = try peer.reply()
		#expect(try #require(refused.error).message.contains("System Settings"))
		#expect(permissions.requests == [.accessibility])
		peer.hangUp()
	}

	@Test("an unknown command comes back as an error frame, and the session survives it")
	func anUnknownGestureIsAnErrorFrameNotADeadSession() throws {
		// `Command does not exist (6)` is the clean failure this whole route was
		// chosen for, and the session tolerating it is what makes a test run
		// survive a command the agent got wrong.
		let scripts = FakeAppleScriptRunner()
		scripts.failNext(number: 6, message: "Command does not exist.")
		let peer = Peer(scripts: scripts)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(
			id: 2, cmd: "pressGesture", params: ["gestures": .array([.string("no such command")])])
		let failed = try peer.reply()
		#expect(failed.id == 2)
		#expect(try #require(failed.error).message.contains("no such command"))

		// Still alive, which is the half that matters.
		try peer.send(id: 3, cmd: "ping")
		#expect(try peer.reply().id == 3)
		peer.hangUp()
	}
}
