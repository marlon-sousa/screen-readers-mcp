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
				permissions: FakePermissionBroker = FakePermissionBroker(),
			poster: FakeEventPoster = FakeEventPoster(),
			layout: FakeKeyboardLayout = FakeKeyboardLayout(),
			readerModifier: FakeReaderModifierSetting = FakeReaderModifierSetting(),
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
							lifecycle: lifecycle, permissions: permissions, poster: poster,
							layout: layout, readerModifier: readerModifier, tree: tree,
							frontmost: frontmost, trust: trust,
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

	/// Forget the handshake's own key press, so what is left is the command's.
	///
	/// EVERY `hello` PRESSES ONE KEY SINCE 13.31: rung 5 sends the capture probe --
	/// `vo+f7` through the real presser -- and requires the utterance to come back.
	/// Every assertion in this file is about what a COMMAND did, so the probe is
	/// taken out here, and CHECKED on the way out: a handshake that stopped
	/// pressing it fails loudly rather than quietly leaving a command's events
	/// looking like two commands' worth.
	///
	/// IT USED TO STRIP SCRIPTS, and there were two: rung 2 asked the reader its
	/// own name over an AppleEvent until 13.26, and rung 5 dispatched the probe by
	/// name until 13.31. Neither channel exists, and the probe is the one thing
	/// left to account for -- but it now lands on the seam the commands land on,
	/// which is why this became a subtraction rather than a filter.
	private func forgetTheHandshakeProbe(_ poster: FakeEventPoster) {
		// Down and up on one key, with the reader's own modifier held for it. The
		// keycode is not asserted: `f7` is a named key, so which code it is belongs
		// to `Keystroke.NamedKey` and not to this file.
		#expect(poster.keyed.count == 2)
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskControl) })
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskAlternate) })
		poster.forgetRecording()
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
		// THE RUNG THIS BRIDGE CANNOT CLIMB, modelled: the handshake registers the
		// extension itself now (13.20), and the system publishes a newly registered
		// voice only after VoiceOver RESTARTS -- which no handshake may do. So
		// registering succeeds, `published` is never reached, and the refusal is
		// what an agent gets.
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.stateAfterRegistering = .registered
		// AND IT WILL NOT PUBLISH EITHER, which is what makes this the dead end. Until
		// 13.26 those were one step; publishing is its own act now, and a machine that
		// registers and never publishes is the state the first live connect hit.
		lifecycle.stateAfterPublishing = .registered
		let peer = Peer(lifecycle: lifecycle)
		try peer.send(
			id: 1, cmd: "hello", params: ["mode": .string("silent"), "protocolVersion": .int(1)])
		guard case .failure(let error) = try peer.reply().outcome() else {
			Issue.record("expected silent mode to be refused on an unusable reader edge")
			return
		}
		#expect(error.message.contains(ReaderCondition.providerNotRunning.rawValue))
		#expect(error.message.contains("pluginkit"))
	}

	@Test("A LIVE HANDSHAKE ON THE SAME MACHINE IS REFUSED TOO, and 13.20 is where that changed")
	func liveIsRefusedOnAnUnusableEdge() throws {
		// UNTIL 13.20 THIS TEST ASSERTED THE OPPOSITE, and the reversal is the
		// entry. A live session used to be established on an unhealthy edge with a
		// note in the transcript, because writing the voice applies live in both
		// directions (spec 0047, finding 17) and such a session could heal itself.
		// What that produced in practice was a session answering `speech: []` --
		// indistinguishable from "the reader said nothing" -- for an hour of a live
		// checklist on 2026-08-31.
		//
		// The 13.6 asymmetry it came from is still right where it is made: `silent`
		// is a promise about a human's EARS and has to hold from the handshake.
		// This is a different promise -- that `getSpeech` means anything at all --
		// and a live session announces the `speech` capability just as loudly.
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.stateAfterRegistering = .registered
		// AND IT WILL NOT PUBLISH EITHER, which is what makes this the dead end. Until
		// 13.26 those were one step; publishing is its own act now, and a machine that
		// registers and never publishes is the state the first live connect hit.
		lifecycle.stateAfterPublishing = .registered
		let peer = Peer(lifecycle: lifecycle)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		guard case .failure(let error) = try peer.reply().outcome() else {
			Issue.record("expected a live session to be refused on an unusable reader edge")
			return
		}
		// THE RUNG MOVED AT 13.26, AND THE NEW ONE IS THE BETTER ANSWER. This machine
		// used to be refused at `voiceSelection` -- "cannot select a voice that is not
		// published" -- which is a true sentence about a symptom. Publishing is its own
		// act now, so it is refused at `registration`, naming the thing that actually
		// did not happen: the system was asked to offer the voice and never did.
		#expect(error.message.contains(SetupRung.registration.rawValue))
		#expect(error.message.contains(ReaderCondition.providerNotRunning.rawValue))
		// And it tried: the bridge registered the extension before it gave up, which
		// is the half of the recovery a human no longer has to perform.
		#expect(lifecycle.registerCalls == 1)
		#expect(peer.transcript.notes.contains { $0.contains("registering it") })
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

	@Test("A COMMAND NAME OFF THE WIRE IS REFUSED, AND THE REFUSAL TEACHES THE ROUTE")
	func aCommandNameOffTheWireIsRefused() throws {
		// 13.31, end to end, and the assertion is about the MESSAGE rather than the
		// mechanism -- which is unusual here and deliberate. Until this entry `go to
		// desktop` was dispatched to the reader by name over an AppleEvent; every
		// agent that has ever driven this bridge, and every document written about
		// it before now, says to send exactly that. So the one thing this refusal
		// must not do is read like "unknown gesture", which would leave an agent
		// believing the act is unreachable when it is a keystroke away.
		let poster = FakeEventPoster()
		let peer = Peer(poster: poster)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		forgetTheHandshakeProbe(poster)

		try peer.send(
			id: 2, cmd: "pressGesture",
			params: ["gestures": .array([.string("go to desktop")]), "graceMs": .int(0)])
		let reply = try peer.reply()
		let error = try #require(reply.error)
		// The id it refused, so a batch says WHICH one.
		#expect(error.message.contains("go to desktop"))
		// The two routes a person actually has, named in the message.
		#expect(error.message.contains("vo+m"))
		#expect(error.message.contains("Commands menu"))
		// NOTHING WAS PRESSED, which is what makes the refusal safe: the batch is
		// classified before any of it moves the machine.
		#expect(poster.keyed.isEmpty)
		#expect(poster.posted.isEmpty)
		#expect(peer.transcript.gestures.isEmpty)

		// Still alive, which is the half that matters for a whole test run.
		try peer.send(id: 3, cmd: "ping")
		#expect(try peer.reply().id == 3)
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
		//
		// AND 13.20 CHANGED HOW IT IS SET UP WITHOUT WEAKENING WHAT IT ASSERTS. The
		// handshake now READS both grants and refuses a session that does not hold
		// them, so this scenario can no longer begin on a machine with nothing
		// granted -- which is the one capability that entry took away, and it is
		// written down in spec 0050 §2.2. The grant is therefore held at the
		// handshake and REVOKED immediately after, which is a thing macOS itself
		// does live; what the scenario proves is unchanged, and the claim it can now
		// make is strictly stronger: the handshake READS both and REQUESTS neither.
		let permissions = FakePermissionBroker(state: .granted)
		let peer = Peer(permissions: permissions)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		// Exactly the handshake's own two reads, and not one request.
		#expect(permissions.statusReads == Permission.allCases)
		#expect(permissions.requests.isEmpty)
		permissions.state = .notGranted

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
		// Nothing SINCE the handshake has even read a grant, let alone asked for
		// one: the two reads below are the ones asserted above.
		#expect(permissions.statusReads == Permission.allCases)

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

	@Test("A CHORD OFF THE WIRE REACHES THE EVENT PATH")
	func aChordOffTheWireReachesTheEventPath() throws {
		// THE TEST THE UNITS CANNOT WRITE. Every unit above runs against a
		// hand-built `AdapterSet`; this one goes in at the socket, through the real
		// Registry, the real handler, the real `VoiceOverAdapterFactory` and the
		// real `CGKeystrokePresser`, and comes out at the two seams that touch the
		// machine. It is what proves the wiring, and it is the assertion that would
		// have caught the bridge dispatching `command+l` to VoiceOver as though it
		// were one of the reader's own command names -- which is what it did until
		// 13.17, right up to `Command does not exist (6)`.
		let poster = FakeEventPoster()
		let peer = Peer(poster: poster)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		forgetTheHandshakeProbe(poster)
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
		// AND IT DID NOT ARRIVE AS TYPED TEXT, which would have inserted an `l` where
		// a location bar should have opened. The other half of this assertion --
		// that the chord did not go to the reader by name -- was here until 13.31
		// and cannot be written any more: there is nowhere for it to have gone.
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
		// between them: the same letter, prefixed and bare, and only one of them is
		// a gesture id at all since 13.31.
		let poster = FakeEventPoster()
		let peer = Peer(poster: poster)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		forgetTheHandshakeProbe(poster)

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
		// And not as typed text -- which is the route that made this reachable by
		// accident and meant something else entirely.
		#expect(poster.posted.isEmpty)
		// What the session is TOLD it pressed keeps the prefix, so the line can be
		// replayed: `h` fed back in is a command name.
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["kb:h"])
		#expect(peer.transcript.gestures == ["kb:h"])

		// AND THE UNPREFIXED LETTER IS REFUSED, WHICH IS WHAT CHANGED AT 13.31. It
		// used to go to the reader as a command name -- that is what made `kb:` a
		// discriminator and not a decoration. There is no such vocabulary now, so a
		// bare `h` is a mistake, and the refusal names the spelling that works
		// rather than leaving an agent to guess which of the two it meant.
		try peer.send(
			id: 3, cmd: "pressGesture",
			params: ["gestures": .array([.string("h")]), "graceMs": .int(0)])
		let refused = try peer.reply()
		#expect(try #require(refused.error).message.contains("kb:h"))
		// The rule is still doing the deciding: nothing more was pressed.
		#expect(poster.keyed.count == 2)
		peer.hangUp()
	}

	@Test("TWO KEYS HELD TOGETHER OFF THE WIRE REACH THE EVENT PATH AS ONE CHORD")
	func aTwoKeyChordOffTheWireReachesTheEventPath() throws {
		// 13.22, end to end. The id that failed before it -- "'leftarrow' is not a
		// modifier this bridge knows" -- is arrow-key Quick Nav, the chord an
		// ordinary VoiceOver user presses to turn on the mode they navigate with
		// all day. What the units cannot show is that it survives the wire, the
		// Registry, the real handler and the real factory as ONE gesture rather
		// than two.
		let poster = FakeEventPoster()
		let peer = Peer(poster: poster)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		forgetTheHandshakeProbe(poster)

		try peer.send(
			id: 2, cmd: "pressGesture",
			params: [
				"gestures": .array([.string("kb:leftArrow+rightArrow")]), "graceMs": .int(0),
			])
		let reply = try peer.reply()
		#expect(reply.error == nil)
		guard case .success(let value) = try reply.outcome() else {
			Issue.record("pressGesture failed: \(reply)")
			return
		}
		// BOTH DOWN, THEN BOTH UP IN REVERSE -- the two arrows are held at the same
		// moment, which is the difference the reader detects and the whole reason
		// this notation exists. Sequential presses move nothing (measured).
		#expect(poster.keyed.map(\.keyCode) == [0x7B, 0x7C, 0x7C, 0x7B])
		#expect(poster.keyed.map(\.keyDown) == [true, true, false, false])
		// Named keys, so the layout was never asked; no modifiers, so nothing was
		// held and nothing can be left held.
		#expect(poster.flagTransitions.isEmpty)
		// And not as typed text.
		#expect(poster.posted.isEmpty)
		// ONE press is reported, not two, and it is replayable.
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["kb:leftArrow+rightArrow"])
		#expect(peer.transcript.gestures == ["kb:leftArrow+rightArrow"])

		// AND THE SAME TWO KEYS AS A BATCH ARE TWO GESTURES, which is the
		// contract's own distinction: four more events, each key down and up on its
		// own, and nothing simultaneous about them.
		try peer.send(
			id: 3, cmd: "pressGesture",
			params: [
				"gestures": .array([.string("kb:leftArrow"), .string("kb:rightArrow")]),
				"graceMs": .int(0),
			])
		_ = try peer.reply()
		#expect(poster.keyed.map(\.keyCode) == [0x7B, 0x7C, 0x7C, 0x7B, 0x7B, 0x7B, 0x7C, 0x7C])
		#expect(
			poster.keyed.map(\.keyDown) == [true, true, false, false, true, false, true, false])
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

	@Test("a getFocusInfo off the wire FAILS BY NAME when the grant is revoked mid-session")
	func focusNamesTheGrantWhenItIsRevoked() throws {
		// THE ROUTE THAT REPLACED A ROUTE. Until 13.31 a session without the
		// Accessibility grant still answered `getFocusInfo`, thinly, from
		// VoiceOver's own cursor over an AppleEvent. There is no such session now --
		// rung 1 refuses a machine that will not grant it, because pressing keys is
		// the only way this bridge drives the reader -- so the branch went with the
		// channel.
		//
		// WHAT MUST NOT HAPPEN IS AN EMPTY SNAPSHOT. A grant revoked while a session
		// runs is a real state, and "nothing is focused" is a sentence an agent
		// would act on by going to look for a defect in the application. So it
		// fails, and the failure names the permission and its recovery.
		let trust = FakeAccessibilityTrust(trusted: true)
		let peer = Peer(trust: trust)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		trust.trusted = false
		try peer.send(id: 2, cmd: "getFocusInfo")
		let reply = try peer.reply()
		let error = try #require(reply.error)
		#expect(error.message.contains(Permission.accessibility.rawValue))
		#expect(error.message.contains("Accessibility"))

		// Still alive: a revoked grant is a thing to report, not a session to end.
		try peer.send(id: 3, cmd: "ping")
		#expect(try peer.reply().id == 3)
		peer.hangUp()
	}

	@Test("A SESSION THAT ALSO READS FOCUS STILL NEVER ASKS FOR THE ACCESSIBILITY GRANT")
	func focusNeverTriggersAPermissionRequest() throws {
		// 13.9 IS THE ENTRY THAT COULD HAVE QUIETLY SPENT 13.8's LEVER, because
		// focus WANTS the same grant. It reads that fact through an adapter seam
		// that shows no dialog, and never through the broker -- so a session that
		// reads where it is goes past a counting broker without asking it anything
		// at all.
		//
		// THE LEVER IT WAS PROTECTING IS SPENT, AND THIS SCENARIO OUTLIVED IT. 13.25
		// made keys the way this bridge drives the reader and 13.31 removed the
		// alternative, so an ordinary session IS asked for Accessibility -- once, by
		// a command that is about to post an event. What is still true, and still
		// worth a scenario at this layer, is the narrower claim underneath it:
		// NOTHING BUT THOSE COMMANDS ASKS. Not the handshake, which reads the grant
		// at rung 1 and requests nothing, and not focus, which cannot request
		// anything because of what it is holding.
		let permissions = FakePermissionBroker(state: .granted)
		let trust = FakeAccessibilityTrust(trusted: true)
		let peer = Peer(permissions: permissions, trust: trust)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		try peer.send(id: 2, cmd: "getFocusInfo")
		_ = try peer.reply()
		try peer.send(id: 3, cmd: "getFocusInfo")
		_ = try peer.reply()

		#expect(permissions.requests.isEmpty)
		// The handshake's one read and nothing since. It was two until 13.31, when
		// the automation permission went with the channel that answered it.
		#expect(permissions.statusReads == [.accessibility])
		#expect(Permission.allCases == [.accessibility])
		// It did ask the cheap question -- once per command.
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
				"gestures": .array([.string("vo+f")]), "graceMs": .int(0),
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
		// AN ID THE BRIDGE ITSELF REFUSES, AND THAT IS 13.31's DOING. It used to be
		// an id the READER refused -- `Command does not exist (6)`, the clean
		// failure the command-name route was chosen for -- and the assertion was
		// that a bad name cost one round trip and left the session alive. The
		// vocabulary answers it now, before anything is dispatched, which is
		// cheaper and says more; what has not changed is the half this test is
		// named for.
		let peer = Peer()
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

	@Test("`vo+m` OFF THE WIRE IS RESOLVED FROM THE MACHINE AND POSTED AS KEYS")
	func aReaderModifierChordOffTheWireReachesTheEventPath() throws {
		// 13.25, end to end, and it is the entry's whole claim in one exchange: a
		// VoiceOver user presses VO-M to reach the menu bar, and what leaves this
		// bridge is the two keys their machine says VO is -- through the window
		// server, past the application under test, rather than dispatched inside
		// the reader where an application that swallows the chord cannot be seen.
		let poster = FakeEventPoster()
		let layout = FakeKeyboardLayout(keys: ["m": LayoutKey(keyCode: 206, shifted: false)])
		let peer = Peer(poster: poster, layout: layout)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		forgetTheHandshakeProbe(poster)

		try peer.send(
			id: 2, cmd: "pressGesture",
			params: ["gestures": .array([.string("vo+m")]), "graceMs": .int(0)])
		let reply = try peer.reply()
		#expect(reply.error == nil)
		guard case .success(let value) = try reply.outcome() else {
			Issue.record("pressGesture failed: \(reply)")
			return
		}
		// Control and Option held as REAL transitions, the key down and up between
		// them, and the transitions unwound to nothing -- so the keyboard is not
		// left holding the reader's own modifier, which would make every keystroke
		// afterwards a VoiceOver command.
		#expect(poster.keyed.map(\.keyCode) == [206, 206])
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskControl) })
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskAlternate) })
		#expect(poster.flagTransitions.last == [])
		// And the event says it is `m`, which is what this reader matches on.
		#expect(poster.keyed.map(\.characters) == ["m", "m"])
		// And not as typed text. "Not to the reader by name" was the other half of
		// this assertion until 13.31 deleted the route 13.25 had demoted.
		#expect(poster.posted.isEmpty)
		// What the session is told it pressed is the RESOLVED spelling, so a record
		// of the run says which keys went out on this machine.
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["control+option+m"])
		#expect(peer.transcript.gestures == ["control+option+m"])
		peer.hangUp()
	}

	@Test("A CAPS LOCK MACHINE IS REFUSED AT THE HANDSHAKE, AND GETS NO SESSION")
	func aCapsLockMachineIsRefusedAtTheHandshake() throws {
		// THE REFUSAL MOVED, AND THAT IS THE COST OF 13.31 IN ONE TEST. A machine
		// whose VoiceOver modifier is Caps Lock alone cannot be driven by keys: a
		// synthesized Caps Lock is invisible to the reader (measured 2026-09-02).
		// Until this entry such a machine still got a session, because the
		// command-name route did not need the modifier -- so the refusal happened
		// per gesture, and `vo+m` came back with a message about Caps Lock while
		// everything else worked.
		//
		// There is no second route now, so there is nothing to establish a session
		// FOR, and rung 1 says so before anything is touched. That is board entry
		// 13.28, and it is open.
		let poster = FakeEventPoster()
		let peer = Peer(poster: poster, readerModifier: FakeReaderModifierSetting(.capsLock))
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		let reply = try peer.reply()
		let error = try #require(reply.error)
		// It names the setting and where a human changes it, because that is the
		// only thing anybody can do about this machine.
		#expect(error.message.contains("capsLock"))
		#expect(error.message.contains("VoiceOver Utility"))
		// Nothing was pressed -- not even the capture probe, which is three rungs
		// further up the ladder than the one that refused.
		#expect(poster.keyed.isEmpty)
		peer.hangUp()
	}
}
