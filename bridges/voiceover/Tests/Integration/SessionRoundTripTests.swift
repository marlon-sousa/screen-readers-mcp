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
			poster: FakeEventPoster = FakeEventPoster(),
			layout: FakeKeyboardLayout = FakeKeyboardLayout(),
			tree: FakeAccessibilityTree = FakeAccessibilityTree(),
			frontmost: FakeFrontmostApplication = FakeFrontmostApplication(),
			trust: FakeAccessibilityTrust = FakeAccessibilityTrust(),
			announcer: FakeAnnouncer = FakeAnnouncer(),
			prompter: FakeUserPrompter = FakeUserPrompter()
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
							lifecycle: lifecycle, scripts: scripts, permissions: permissions, poster: poster,
							layout: layout, tree: tree, frontmost: frontmost, trust: trust,
							announcer: announcer, prompter: prompter
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
		#expect(hello.capabilities == [.speech, .gestures, .typing, .focus, .interact, .guidance])
		#expect(hello.attended == true)
		#expect(hello.bridgeVersion == "1.2.3")
		// THE GUIDANCE DOCUMENT RIDES BACK IN THE HANDSHAKE (protocol.md §3), so a
		// session gets this reader's own account of its stance without a second
		// round trip. Asserted HERE rather than only in the handler's unit test
		// because the property that matters is that it survived encoding, framing
		// and decoding as part of a real reply -- the document is the largest field
		// this bridge ever sends.
		let guidance = try #require(hello.guidance)
		#expect(guidance.text.contains("Driving VoiceOver on macOS"))
		// This handshake declared no persona, which an older server will not, and
		// §4 requires that to DEGRADE rather than fail.
		#expect(guidance.persona == "")
		#expect(!guidance.recognised)
		peer.hangUp()
	}

	@Test("the handshake's guidance is the persona's, and getGuidance answers with the same text")
	func guidanceTravelsBothWays() throws {
		// protocol.md §3: both routes describe ONE document, and a server that
		// receives the handshake's copy MUST NOT call the command as well. That
		// rule is only safe if the two cannot disagree -- so this drives both over
		// a real wire and compares them.
		let peer = Peer()
		try peer.send(
			id: 1, cmd: "hello",
			params: [
				"mode": .string("live"), "protocolVersion": .int(1), "persona": .string("validator"),
			])
		guard case .success(let handshake) = try peer.reply().outcome() else {
			Issue.record("the handshake failed")
			return
		}
		let fromHandshake = try #require(
			try handshake.decoded(as: HelloResult.self).guidance)
		#expect(fromHandshake.persona == "validator")
		#expect(fromHandshake.recognised)

		try peer.send(id: 2, cmd: "getGuidance")
		guard case .success(let answer) = try peer.reply().outcome() else {
			Issue.record("getGuidance failed")
			return
		}
		#expect(try answer.decoded(as: GetGuidanceResult.self) == fromHandshake)
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

	@Test("A SESSION THAT ONLY PRESSES COMMAND NAMES NEVER ASKS FOR THE ACCESSIBILITY GRANT")
	func gesturesNeverTriggerAPermissionRequest() throws {
		// 13.8'S WHOLE CLAIM, ASSERTED END TO END RATHER THAN INTENDED. The two
		// halves of input cost different permissions on macOS (spec 0041) and
		// Windows has no equivalent gate, so this is the one design lever lane 3
		// has that lane 1 cannot have -- and it is worth only as much as its
		// checkability. A handshake, a gesture and a speech read go past here
		// without the broker being asked anything at all; the first `typeText`
		// asks, and nothing else in the bridge does except a KEYSTROKE, below.
		//
		// AND THIS SCENARIO DID NOT HAVE TO CHANGE AT 13.10, which is the point of
		// it: that entry adds three commands -- telling the human something, asking
		// them something, and collecting the answer -- and none of them touches the
		// broker, so they are simply driven past it here as well.
		//
		// 13.17 DID CHANGE IT, BY ONE WORD, AND THAT IS THE HONEST RECORD OF WHAT
		// THAT ENTRY SPENT. `pressGesture` now takes keystrokes as well as command
		// names, and a keystroke is a system event costing the same grant -- so the
		// claim narrowed from "only presses commands" to "presses only the reader's
		// COMMAND NAMES", which is the property that was ever worth having. The
		// gesture driven past the broker below is a command name, and the keystroke
		// leg at the end asserts the other half rather than leaving it implied.
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
		// And the three commands 13.10 added, which talk to a PERSON and not to the
		// system: telling them something, asking them something, and collecting the
		// answer all cost no permission at all.
		try peer.send(id: 10, cmd: "announce", params: ["text": .string("still here")])
		_ = try peer.reply()
		try peer.send(id: 11, cmd: "askUser", params: ["prompt": .string("ready?")])
		_ = try peer.reply()
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)

		// And now the two commands that may ask. The grant is not held, so each
		// reply says what to do about it rather than reporting a success that
		// changed nothing anywhere.
		try peer.send(id: 4, cmd: "typeText", params: ["text": .string("hello")])
		let refused = try peer.reply()
		#expect(try #require(refused.error).message.contains("System Settings"))
		#expect(permissions.requests == [.accessibility])

		// THE SECOND CALLER, WHICH IS 13.17's. Same command as the gesture at id 2,
		// a different NOTATION -- and that is the whole difference the grant turns
		// on: `go to desktop` went to the reader and cost nothing, `command+l` is a
		// system event and costs this.
		try peer.send(
			id: 5, cmd: "pressGesture",
			params: ["gestures": .array([.string("command+l")]), "graceMs": .int(0)])
		let refusedChord = try peer.reply()
		#expect(try #require(refusedChord.error).message.contains("nothing was pressed"))
		#expect(permissions.requests == [.accessibility, .accessibility])
		peer.hangUp()
	}

	@Test("A CHORD OFF THE WIRE REACHES THE EVENT PATH AND NOT THE APPLESCRIPT RUNNER")
	func aChordOffTheWireReachesTheEventPath() throws {
		// THE TEST THE UNITS CANNOT WRITE. Every unit above runs against a
		// hand-built `AdapterSet`; this one goes in at the socket, through the real
		// Registry, the real handler, the real `VoiceOverAdapterFactory` and the
		// real `CGKeystrokePresser`, and comes out at the two seams that touch the
		// machine. It is what proves the wiring, and it is the assertion that would
		// have caught the bridge dispatching `command+l` to VoiceOver as though it
		// were one of the reader's own command names -- which is what it did until
		// this entry, right up to `Command does not exist (6)`.
		let poster = FakeEventPoster()
		let scripts = FakeAppleScriptRunner()
		let peer = Peer(scripts: scripts, poster: poster)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		try peer.send(
			id: 2, cmd: "pressGesture",
			params: ["gestures": .array([.string("command+l")]), "graceMs": .int(0)])
		let reply = try peer.reply()
		#expect(reply.error == nil)

		// Down then up, on the key the FAKE LAYOUT named -- 201, which is not the
		// ANSI keycode for `l` and could not have come from a table.
		#expect(poster.keyed.map(\.keyCode) == [201, 201])
		#expect(poster.keyed.allSatisfy { $0.flags == .maskCommand })
		#expect(poster.keyed.map(\.keyDown) == [true, false])
		// AND NOT ONE APPLESCRIPT WAS RUN. The chord never went near the reader.
		#expect(scripts.scripts.isEmpty)
		// Nor did it arrive as typed text, which would have inserted an `l` where
		// a location bar should have opened.
		#expect(poster.posted.isEmpty)
		peer.hangUp()
	}

	@Test("`kb:h` OFF THE WIRE IS THE LETTER KEY, AND `h` IS STILL A COMMAND NAME")
	func aSourcePrefixedKeyOffTheWireReachesTheEventPath() throws {
		// 13.19, end to end. With single-key Quick Nav on, an ordinary VoiceOver
		// user presses `h` to move by heading; until this entry the bridge had no
		// notation for it, because the `+` was the whole discriminator and a lone
		// token was looked up as one of the reader's commands. Both halves are
		// asserted here on one connection, because the property is the DIFFERENCE
		// between them: the same letter, two vocabularies, two destinations.
		let poster = FakeEventPoster()
		let scripts = FakeAppleScriptRunner()
		let peer = Peer(scripts: scripts, poster: poster)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(
			id: 2, cmd: "pressGesture",
			params: ["gestures": .array([.string("kb:h")]), "graceMs": .int(0)])
		let reply = try peer.reply()
		#expect(reply.error == nil)
		guard case .success(let value) = try reply.outcome() else {
			Issue.record("pressGesture failed: \(reply)")
			return
		}
		// Down then up on the key the FAKE LAYOUT named, and NOT ONE MODIFIER
		// TRANSITION: an unmodified press holds nothing down, so there is nothing
		// to put back and no way for it to leave a key stuck.
		#expect(poster.keyed.map(\.keyCode) == [205, 205])
		#expect(poster.keyed.allSatisfy { $0.flags == [] })
		#expect(poster.keyed.map(\.keyDown) == [true, false])
		#expect(poster.flagTransitions.isEmpty)
		// Not to the reader, and not as typed text -- which is the route that made
		// this reachable by accident and meant something else entirely.
		#expect(scripts.scripts.isEmpty)
		#expect(poster.posted.isEmpty)
		// What the session is TOLD it pressed keeps the prefix, so the line can be
		// replayed: `h` fed back in is a command name.
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["kb:h"])
		#expect(peer.transcript.gestures == ["kb:h"])

		// And the unprefixed letter still goes to the reader, where it is refused
		// by VoiceOver itself as a command that does not exist -- which is the
		// cheap, correct failure, and proves the prefix is doing the deciding.
		try peer.send(
			id: 3, cmd: "pressGesture",
			params: ["gestures": .array([.string("h")]), "graceMs": .int(0)])
		_ = try peer.reply()
		#expect(scripts.scripts == ["tell application \"VoiceOver\" to tell commander to perform command \"h\""])
		#expect(poster.keyed.count == 2)
		peer.hangUp()
	}

	@Test("a getFocusInfo off the wire reads the TREE when the grant is held")
	func focusReachesTheAccessibilityTree() throws {
		// THE TEST THE UNITS CANNOT WRITE, a third time. Every unit above runs
		// against a graph its own test assembled, so a handler wired to the wrong
		// command name, an inspector the factory never builds, or a result that
		// does not encode would pass all of them. What is asserted here is the
		// whole path -- a JSON frame in, the real Registry's handler, the real
		// VoiceOverAdapterFactory's inspector, and the element query that would
		// have gone to the accessibility API.
		let tree = FakeAccessibilityTree(element: [
			"AXRole": .text("AXButton"),
			"AXTitle": .text("Save"),
			"AXValue": .text("on"),
			"AXFocused": .flag(true),
			"AXEnabled": .flag(false),
		])
		let peer = Peer(tree: tree, trust: FakeAccessibilityTrust(trusted: true))
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(id: 2, cmd: "getFocusInfo")
		let response = try peer.reply()
		guard case .success(let value) = try response.outcome() else {
			Issue.record("getFocusInfo failed: \(response)")
			return
		}
		let result = try value.decoded(as: FocusInfoResult.self)
		#expect(result.name == "Save")
		// A FRAMEWORK CONSTANT, never `AXRoleDescription`: `role` means the same
		// string on a machine that speaks Portuguese.
		#expect(result.role == "AXButton")
		#expect(result.states == ["focused", "disabled"])
		#expect(result.value == "on")
		// The bundle identifier, which is what survives translation.
		#expect(result.appModule == "com.apple.TextEdit")

		// The query the real inspector made, off the real wire request: addressed
		// to the frontmost application's pid, because there is no system-wide
		// element that works (see AXAccessibilityTree's header).
		let query = try #require(tree.queries.first)
		#expect(query.pid == 4242)
		#expect(query.attributes.contains("AXRole"))
		#expect(!query.attributes.contains("AXRoleDescription"))
		peer.hangUp()
	}

	@Test("a getFocusInfo off the wire reads the VOICEOVER CURSOR when the grant is not held")
	func focusFallsBackToTheVoiceOverCursor() throws {
		// The other route, end to end, and the same kind of assertion: the script
		// text that would have gone to `osascript`. A bridge with no Accessibility
		// grant still answers `getFocusInfo` -- thinner, and never by asking for
		// the grant.
		let scripts = FakeAppleScriptRunner()
		scripts.defaultAnswer = "Ok button"
		let peer = Peer(scripts: scripts, trust: FakeAccessibilityTrust(trusted: false))
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(id: 2, cmd: "getFocusInfo")
		let response = try peer.reply()
		guard case .success(let value) = try response.outcome() else {
			Issue.record("getFocusInfo failed: \(response)")
			return
		}
		let result = try value.decoded(as: FocusInfoResult.self)
		#expect(result.name == "Ok button")
		// The cursor answers a rendering, not structure, so the rest is empty --
		// and `value` is NULL rather than "", which is the distinction
		// FocusInfoResult writes its own Codable to keep.
		#expect(result.role.isEmpty)
		#expect(result.states.isEmpty)
		#expect(result.value == nil)
		#expect(result.appModule == "com.apple.TextEdit")

		#expect(
			scripts.scripts == [
				"tell application \"VoiceOver\" to return text under cursor of vo cursor"
			])
		peer.hangUp()
	}

	@Test("A SESSION THAT ALSO READS FOCUS STILL NEVER ASKS FOR THE ACCESSIBILITY GRANT")
	func focusNeverTriggersAPermissionRequest() throws {
		// 13.9 IS THE ENTRY THAT COULD HAVE QUIETLY SPENT 13.8's LEVER, because
		// focus WANTS the same grant: it answers from the accessibility tree when
		// the grant is held. It reads that fact through an adapter seam that shows
		// no dialog, and never through the broker -- so a session that presses,
		// reads speech and asks where it is goes past a counting broker without
		// asking it anything at all, on BOTH routes.
		let permissions = FakePermissionBroker(state: .notGranted)
		let trust = FakeAccessibilityTrust(trusted: false)
		let peer = Peer(permissions: permissions, trust: trust)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		try peer.send(id: 2, cmd: "getFocusInfo")
		_ = try peer.reply()
		// And again with the grant held, which is the route that USES it.
		trust.trusted = true
		try peer.send(id: 3, cmd: "getFocusInfo")
		_ = try peer.reply()

		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
		// It did ask the cheap question -- once per command, on both routes.
		#expect(trust.reads == 2)
		peer.hangUp()
	}

	// -- the human channel, end to end (13.10) ---------------------------------

	@Test("AN `announce` IN A SILENT SESSION SUCCEEDS, AND THE WORDS LEAVE THE BRIDGE")
	func announceReachesTheHumanInASilentSession() throws {
		// THE PROMISE 13.10 EXISTS TO MAKE KEEPABLE, asserted end to end rather than
		// intended. Before this entry the same words on a `pressGesture` were
		// REFUSED in silent mode, because there was no channel to say them on; the
		// Announcer speaks with the bridge's own synthesizer, outside VoiceOver,
		// which is why the mode that mutes the reader does not reach it.
		//
		// What a headless test can assert is that the words reached the synthesizer
		// seam off a real wire frame. That they are AUDIBLE on a real machine is a
		// claim no test can make, and `scripts/voiceover_announce.sh` is the
		// re-runnable instrument that does.
		let announcer = FakeAnnouncer()
		let peer = Peer(announcer: announcer)
		try peer.send(
			id: 1, cmd: "hello", params: ["mode": .string("silent"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(id: 2, cmd: "announce", params: ["text": .string("the agent is about to type")])
		let response = try peer.reply()
		guard case .success(let value) = try response.outcome() else {
			Issue.record("announce failed in a silent session: \(response)")
			return
		}
		#expect(try value.decoded(as: AckResult.self).ok)
		#expect(announcer.spoken == ["the agent is about to type"])
		// AND THE SESSION IS STILL SILENT. `announce` bypasses the suppression; it
		// does not lift it, which is the difference between a hint and a lift.
		try peer.send(id: 3, cmd: "ping")
		guard case .success(let pong) = try peer.reply().outcome() else {
			Issue.record("ping failed")
			return
		}
		#expect(try pong.decoded(as: PingResult.self).suppressing == true)

		// And the same words reach the human through a MUTATING command's
		// `announce`, which is the field that had nothing to travel on until now.
		try peer.send(
			id: 4, cmd: "pressGesture",
			params: [
				"gestures": .array([.string("go to desktop")]), "graceMs": .int(0),
				"announce": .string("moving to the desktop"),
			])
		guard case .success = try peer.reply().outcome() else {
			Issue.record("a gesture with an announce failed in a silent session")
			return
		}
		#expect(announcer.spoken == ["the agent is about to type", "moving to the desktop"])
		peer.hangUp()
	}

	@Test("`askUser` AND `waitForUserReply` ARE TWO COMMANDS, and the answer survives between them")
	func aQuestionAndItsAnswerCrossTwoCommands() throws {
		// protocol.md §5's whole shape: the agent asks, is handed a ticket, and
		// collects the answer later -- possibly much later. Nothing blocks, which is
		// why the ticket has to outlive the command that minted it and why the
		// answer has to be waiting when a poll finally arrives.
		let prompter = FakeUserPrompter()
		let peer = Peer(prompter: prompter)
		try peer.send(
			id: 1, cmd: "hello", params: ["mode": .string("silent"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(id: 2, cmd: "askUser", params: ["prompt": .string("did the menu open?")])
		guard case .success(let asked) = try peer.reply().outcome() else {
			Issue.record("askUser failed")
			return
		}
		let ticket = try asked.decoded(as: AskUserResult.self).ticket
		#expect(prompter.presented == ["did the menu open?"])

		// A POLL BEFORE ANYBODY HAS ANSWERED IS `answered: false`, not an error, and
		// it leaves the window open -- `waitForSpeech`'s manners.
		try peer.send(
			id: 3, cmd: "waitForUserReply",
			params: ["ticket": .string(ticket), "timeout": .double(0)])
		guard case .success(let miss) = try peer.reply().outcome() else {
			Issue.record("the first poll failed")
			return
		}
		#expect(try miss.decoded(as: WaitForUserReplyResult.self).answered == false)

		// Now the person answers, at a moment nothing in the bridge controls.
		prompter.answer("yes, and it read the first item")
		try peer.send(
			id: 4, cmd: "waitForUserReply",
			params: ["ticket": .string(ticket), "timeout": .double(0)])
		guard case .success(let answered) = try peer.reply().outcome() else {
			Issue.record("the second poll failed")
			return
		}
		let reply = try answered.decoded(as: WaitForUserReplyResult.self)
		#expect(reply.answered)
		#expect(reply.text == "yes, and it read the first item")

		// AND THE SESSION IS SILENT AGAIN. Asking gave the reader back so the human
		// could hear the field they were typing into; answering takes it away
		// again, which is what `suppressing` reports.
		try peer.send(id: 5, cmd: "ping")
		guard case .success(let pong) = try peer.reply().outcome() else {
			Issue.record("ping failed")
			return
		}
		#expect(try pong.decoded(as: PingResult.self).suppressing == true)
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
