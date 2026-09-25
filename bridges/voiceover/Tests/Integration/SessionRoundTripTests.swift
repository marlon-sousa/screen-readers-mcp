// Headless integration: a real Session over the real JsonLinesChannel and a loopback transport, driving the real handlers.

import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("session round trip")
struct SessionRoundTripTests {
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

	/// Forgets the handshake's capture-probe key press, checking that it happened, so what is left is the command's.
	private func forgetTheHandshakeProbe(_ poster: FakeEventPoster) {
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
		#expect(hello.capabilities == [.speech, .gestures, .typing, .focus, .interact, .guidance])
		#expect(hello.attended == true)
		#expect(hello.bridgeVersion == "1.2.3")
		let guidance = try #require(hello.guidance)
		#expect(guidance.text.contains("Driving VoiceOver on macOS"))
		#expect(guidance.persona == "")
		#expect(!guidance.recognised)
		peer.hangUp()
	}

	@Test("the handshake's guidance is the persona's, and getGuidance answers with the same text")
	func guidanceTravelsBothWays() throws {
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
		let peer = Peer()
		try peer.send(
			id: 1, cmd: "hello", params: ["mode": .string("silent"), "protocolVersion": .int(1)])
		guard case .success(let value) = try peer.reply().outcome() else {
			Issue.record("expected silent mode to be established")
			return
		}
		#expect(try value.decoded(as: HelloResult.self).mode == .silent)

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
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.stateAfterRegistering = .registered
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
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.stateAfterRegistering = .registered
		lifecycle.stateAfterPublishing = .registered
		let peer = Peer(lifecycle: lifecycle)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		guard case .failure(let error) = try peer.reply().outcome() else {
			Issue.record("expected a live session to be refused on an unusable reader edge")
			return
		}
		#expect(error.message.contains(SetupRung.registration.rawValue))
		#expect(error.message.contains(ReaderCondition.providerNotRunning.rawValue))
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
		let deadline = Date().addingTimeInterval(2)
		while peer.transcript.closedReasons.isEmpty, Date() < deadline {
			usleep(2000)
		}
		#expect(peer.transcript.closedReasons.last == "client-bye")
		#expect(peer.signals.endedCount == 1)
	}

	@Test("two frames arriving in ONE write are both answered")
	func twoFramesInOneWrite() throws {
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
		#expect(error.message.contains("go to desktop"))
		#expect(error.message.contains("vo+m"))
		#expect(error.message.contains("Commands menu"))
		#expect(poster.keyed.isEmpty)
		#expect(poster.posted.isEmpty)
		#expect(peer.transcript.gestures.isEmpty)

		try peer.send(id: 3, cmd: "ping")
		#expect(try peer.reply().id == 3)
		peer.hangUp()
	}

	@Test("a typeText off the wire reaches the event poster as the keystrokes it asked for")
	func typedTextReachesTheEventPoster() throws {
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
		#expect(result.typed == 10)
		#expect(result.speech.isEmpty)
		#expect(result.state == nil)

		#expect(poster.typedText == "caf\u{00E9} \u{2014} 50%")
		#expect(poster.posted.count == 2)
		#expect(poster.posted.map(\.keyDown) == [true, false])
		#expect(peer.transcript.typedLengths == [10])
		peer.hangUp()
	}

	@Test("A SESSION THAT ONLY PRESSES COMMAND NAMES NEVER ASKS FOR THE ACCESSIBILITY GRANT")
	func gesturesNeverTriggerAPermissionRequest() throws {
		let permissions = FakePermissionBroker(state: .granted)
		let peer = Peer(permissions: permissions)
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()
		#expect(permissions.statusReads == Permission.allCases)
		#expect(permissions.requests.isEmpty)
		permissions.state = .notGranted

		try peer.send(
			id: 2, cmd: "pressGesture",
			params: ["gestures": .array([.string("go to desktop")]), "graceMs": .int(0)])
		_ = try peer.reply()
		try peer.send(id: 3, cmd: "getNextSpeechIndex")
		_ = try peer.reply()
		try peer.send(id: 10, cmd: "announce", params: ["text": .string("still here")])
		_ = try peer.reply()
		try peer.send(id: 11, cmd: "askUser", params: ["prompt": .string("ready?")])
		_ = try peer.reply()
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads == Permission.allCases)

		try peer.send(id: 4, cmd: "typeText", params: ["text": .string("hello")])
		let refused = try peer.reply()
		#expect(try #require(refused.error).message.contains("System Settings"))
		#expect(permissions.requests == [.accessibility])

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

		#expect(poster.keyed.map(\.keyCode) == [201, 201])
		#expect(poster.keyed.allSatisfy { $0.flags == .maskCommand })
		#expect(poster.keyed.map(\.keyDown) == [true, false])
		#expect(poster.posted.isEmpty)
		peer.hangUp()
	}

	@Test("`kb:h` OFF THE WIRE IS THE LETTER KEY, AND `h` IS STILL A COMMAND NAME")
	func aSourcePrefixedKeyOffTheWireReachesTheEventPath() throws {
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
		#expect(poster.keyed.map(\.keyCode) == [205, 205])
		#expect(poster.keyed.allSatisfy { $0.flags == [] })
		#expect(poster.keyed.map(\.keyDown) == [true, false])
		#expect(poster.flagTransitions.isEmpty)
		#expect(poster.posted.isEmpty)
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["kb:h"])
		#expect(peer.transcript.gestures == ["kb:h"])

		try peer.send(
			id: 3, cmd: "pressGesture",
			params: ["gestures": .array([.string("h")]), "graceMs": .int(0)])
		let refused = try peer.reply()
		#expect(try #require(refused.error).message.contains("kb:h"))
		#expect(poster.keyed.count == 2)
		peer.hangUp()
	}

	@Test("TWO KEYS HELD TOGETHER OFF THE WIRE REACH THE EVENT PATH AS ONE CHORD")
	func aTwoKeyChordOffTheWireReachesTheEventPath() throws {
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
		#expect(poster.keyed.map(\.keyCode) == [0x7B, 0x7C, 0x7C, 0x7B])
		#expect(poster.keyed.map(\.keyDown) == [true, true, false, false])
		#expect(poster.flagTransitions.isEmpty)
		#expect(poster.posted.isEmpty)
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["kb:leftArrow+rightArrow"])
		#expect(peer.transcript.gestures == ["kb:leftArrow+rightArrow"])

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
		#expect(result.role == "AXButton")
		#expect(result.states == ["focused", "disabled"])
		#expect(result.value == "on")
		#expect(result.appModule == "com.apple.TextEdit")

		let query = try #require(tree.queries.first)
		#expect(query.pid == 4242)
		#expect(query.attributes.contains("AXRole"))
		#expect(!query.attributes.contains("AXRoleDescription"))
		peer.hangUp()
	}

	@Test("a getFocusInfo off the wire FAILS BY NAME when the grant is revoked mid-session")
	func focusNamesTheGrantWhenItIsRevoked() throws {
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

		try peer.send(id: 3, cmd: "ping")
		#expect(try peer.reply().id == 3)
		peer.hangUp()
	}

	@Test("A SESSION THAT ALSO READS FOCUS STILL NEVER ASKS FOR THE ACCESSIBILITY GRANT")
	func focusNeverTriggersAPermissionRequest() throws {
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
		#expect(permissions.statusReads == [.accessibility])
		#expect(Permission.allCases == [.accessibility])
		#expect(trust.reads == 2)
		peer.hangUp()
	}

	@Test("AN `announce` IN A SILENT SESSION SUCCEEDS, AND THE WORDS LEAVE THE BRIDGE")
	func announceReachesTheHumanInASilentSession() throws {
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
		try peer.send(id: 3, cmd: "ping")
		guard case .success(let pong) = try peer.reply().outcome() else {
			Issue.record("ping failed")
			return
		}
		#expect(try pong.decoded(as: PingResult.self).suppressing == true)

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

		try peer.send(
			id: 3, cmd: "waitForUserReply",
			params: ["ticket": .string(ticket), "timeout": .double(0)])
		guard case .success(let miss) = try peer.reply().outcome() else {
			Issue.record("the first poll failed")
			return
		}
		#expect(try miss.decoded(as: WaitForUserReplyResult.self).answered == false)

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
		let peer = Peer()
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		_ = try peer.reply()

		try peer.send(
			id: 2, cmd: "pressGesture", params: ["gestures": .array([.string("no such command")])])
		let failed = try peer.reply()
		#expect(failed.id == 2)
		#expect(try #require(failed.error).message.contains("no such command"))

		try peer.send(id: 3, cmd: "ping")
		#expect(try peer.reply().id == 3)
		peer.hangUp()
	}

	@Test("`vo+m` OFF THE WIRE IS RESOLVED FROM THE MACHINE AND POSTED AS KEYS")
	func aReaderModifierChordOffTheWireReachesTheEventPath() throws {
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
		#expect(poster.keyed.map(\.keyCode) == [206, 206])
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskControl) })
		#expect(poster.keyed.allSatisfy { $0.flags.contains(.maskAlternate) })
		#expect(poster.flagTransitions.last == [])
		#expect(poster.keyed.map(\.characters) == ["m", "m"])
		#expect(poster.posted.isEmpty)
		let result = try value.decoded(as: GestureResult.self)
		#expect(result.pressed.map(\.gesture) == ["control+option+m"])
		#expect(peer.transcript.gestures == ["control+option+m"])
		peer.hangUp()
	}

	@Test("A CAPS LOCK MACHINE IS REFUSED AT THE HANDSHAKE, AND GETS NO SESSION")
	func aCapsLockMachineIsRefusedAtTheHandshake() throws {
		let poster = FakeEventPoster()
		let peer = Peer(poster: poster, readerModifier: FakeReaderModifierSetting(.capsLock))
		try peer.send(id: 1, cmd: "hello", params: ["mode": .string("live"), "protocolVersion": .int(1)])
		let reply = try peer.reply()
		let error = try #require(reply.error)
		#expect(error.message.contains("capsLock"))
		#expect(error.message.contains("VoiceOver Utility"))
		#expect(poster.keyed.isEmpty)
		peer.hangUp()
	}
}
