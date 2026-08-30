// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Session.swift.
//
// A BUILDER, NOT A FIXTURE, and AGENTS.md says why: every test here customises
// something -- the script the peer plays, the handler that answers, a clock that
// jumps, a cue that fails -- so a fixture per permutation would be one fixture
// per test. Fixtures suit uniform collaborators; builders suit scenarios.
//
// EVERY TIMING TEST RUNS IN MICROSECONDS, because FakeClock.sleep is an instant
// advance and the loop reads the clock through the port. Nothing here waits.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("Session")
struct SessionTests {
	/// Everything a test wants to look at afterwards.
	struct Run {
		let channel: FakeChannel
		let transcript: FakeTranscript
		let signals: FakeSessionSignals
		let clock: FakeClock
		let session: Session

		/// The reason the transcript recorded, which is the session's own account
		/// of why it ended.
		var closedReason: String? { transcript.closedReasons.last }

		/// The replies, in order.
		var replies: [Response] { channel.written }
	}

	private func hello(_ params: [String: JSONValue] = [:]) -> FakeChannel.Step {
		.request(["id": .int(1), "cmd": .string("hello"), "params": .object(params)])
	}

	private func request(_ id: Int, _ command: String) -> FakeChannel.Step {
		.request(["id": .int(id), "cmd": .string(command)])
	}

	/// Run a whole session against a scripted peer.
	///
	/// `advancePerRead` is how a watchdog test says "time passed while nothing
	/// arrived" without any test waiting for it.
	@discardableResult
	private func run(
		_ script: [FakeChannel.Step],
		handlers: [String: any CommandHandler]? = nil,
		config: SessionConfig = SessionConfig(readerVersion: "macOS 15.0.0"),
		signals: FakeSessionSignals = FakeSessionSignals(),
		advancePerRead: Double = 0
	) -> Run {
		let clock = FakeClock()
		let channel = FakeChannel(script)
		if advancePerRead > 0 {
			channel.onRead = { clock.advance(advancePerRead) }
		}
		let transcript = FakeTranscript()
		let session = Session(
			channel: channel,
			transcript: transcript,
			clock: clock,
			config: config,
			handlers: handlers ?? defaultHandlers(),
			signals: signals
		)
		session.run()
		return Run(
			channel: channel, transcript: transcript, signals: signals, clock: clock, session: session
		)
	}

	/// A hello that establishes, a ping that does not reset inactivity, an echo
	/// that does, and a bye that closes -- the four shapes the loop distinguishes.
	private func defaultHandlers() -> [String: any CommandHandler] {
		[
			"hello": FakeHandler(availableBeforeHello: true),
			"ping": FakeHandler(resetsInactivity: false),
			"echo": FakeHandler(),
			"bye": byeHandler(),
		]
	}

	private func byeHandler() -> FakeHandler {
		let handler = FakeHandler()
		handler.onExecute = { context, _ in context.close(.clientBye) }
		return handler
	}

	// -- the handshake -------------------------------------------------------

	@Test("a command before hello is refused, and the handshake is over")
	func nothingBeforeHello() {
		let outcome = run([request(1, "ping")])
		#expect(outcome.replies.count == 1)
		#expect(try! outcome.replies[0].outcome() == .failure(ErrorInfo(message: "handshake: expected hello")))
		#expect(outcome.closedReason == TeardownReason.handshakeFailed.rawValue)
	}

	@Test("hello establishes the session, and the start cue names the persona")
	func helloEstablishes() {
		let handler = FakeHandler(availableBeforeHello: true)
		handler.onExecute = { context, _ in context.persona = "a curious tester" }
		let outcome = run(
			[hello(), request(2, "ping"), .closed],
			handlers: ["hello": handler, "ping": FakeHandler(resetsInactivity: false)]
		)
		#expect(outcome.replies.count == 2)
		#expect(outcome.signals.startedWith == ["a curious tester"])
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}

	@Test("a second hello is refused, and the session survives it")
	func helloTwice() {
		let outcome = run([hello(), hello(), request(3, "ping"), .closed])
		#expect(outcome.replies.count == 3)
		#expect(
			try! outcome.replies[1].outcome() == .failure(ErrorInfo(message: "session already established"))
		)
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}

	@Test("a hello that FAILS ends the handshake rather than leaving a half session")
	func aFailedHelloEndsIt() {
		let handler = FakeHandler(availableBeforeHello: true)
		handler.failure = CommandError("protocol version mismatch")
		let outcome = run([hello(), request(2, "ping")], handlers: ["hello": handler])
		#expect(outcome.replies.count == 1)
		#expect(
			try! outcome.replies[0].outcome() == .failure(ErrorInfo(message: "protocol version mismatch"))
		)
		#expect(outcome.closedReason == TeardownReason.handshakeFailed.rawValue)
		// It never established, so nothing announced it and nothing un-announces it.
		#expect(outcome.signals.startedWith.isEmpty)
		#expect(outcome.signals.endedCount == 0)
	}

	@Test("an unreadable first line is not our client at all")
	func garbageBeforeHello() {
		let outcome = run([.unreadable("line is not JSON")])
		#expect(outcome.closedReason == TeardownReason.handshakeFailed.rawValue)
	}

	// -- an established session is tolerant ----------------------------------

	@Test("an unknown command is an error frame, and the session carries on")
	func unknownCommand() {
		let outcome = run([hello(), request(2, "makeCoffee"), request(3, "ping"), .closed])
		#expect(outcome.replies.count == 3)
		#expect(
			try! outcome.replies[1].outcome()
				== .failure(ErrorInfo(message: "unknown command: 'makeCoffee'"))
		)
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}

	@Test("a handler that throws costs its command and not the session")
	func aFailingHandlerIsSurvived() {
		let failing = FakeHandler()
		failing.failure = CommandError("the reader said no")
		let outcome = run(
			[hello(), request(2, "echo"), request(3, "ping"), .closed],
			handlers: [
				"hello": FakeHandler(availableBeforeHello: true), "echo": failing,
				"ping": FakeHandler(resetsInactivity: false),
			]
		)
		#expect(
			try! outcome.replies[1].outcome() == .failure(ErrorInfo(message: "the reader said no"))
		)
		#expect(outcome.replies.count == 3)
	}

	@Test("an unreadable line mid-session is noted and survived")
	func garbageMidSession() {
		let outcome = run([hello(), .unreadable("line is not JSON"), request(3, "ping"), .closed])
		#expect(outcome.transcript.notes.contains { $0.contains("unreadable message") })
		#expect(outcome.replies.count == 2)
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}

	@Test("a frame with no id to answer is recorded rather than answered into the void")
	func anUnattributableFault() {
		let outcome = run([hello(), .request(["cmd": .string("ping")]), .closed])
		#expect(outcome.replies.count == 1)
		#expect(outcome.transcript.notes.contains { $0.contains("unattributable error") })
	}

	@Test("a frame that is not a request, but carries an id, is answered with that id")
	func aBadRequestWithAnId() {
		let outcome = run([hello(), .request(["id": .int(4), "cmd": .int(7)]), .closed])
		#expect(outcome.replies.count == 2)
		#expect(outcome.replies[1].id == 4)
		if case .failure(let error) = try! outcome.replies[1].outcome() {
			#expect(error.message.contains("invalid request"))
		} else {
			Issue.record("expected an error frame")
		}
	}

	// -- the watchdogs -------------------------------------------------------

	@Test("nothing at all for the heartbeat window ends the session")
	func heartbeat() {
		let outcome = run(
			[hello(), .quiet, .quiet],
			config: SessionConfig(readerVersion: "test", heartbeatTimeout: 30, inactivityTimeout: 120),
			advancePerRead: 31
		)
		#expect(outcome.closedReason == TeardownReason.heartbeatTimeout.rawValue)
	}

	@Test("silence BEFORE the handshake is a failed handshake, not a lost heartbeat")
	func heartbeatBeforeHello() {
		let outcome = run(
			[.quiet],
			config: SessionConfig(readerVersion: "test", heartbeatTimeout: 30),
			advancePerRead: 31
		)
		#expect(outcome.closedReason == TeardownReason.handshakeFailed.rawValue)
	}

	@Test("pings keep the heartbeat alive and do NOT keep the session alive")
	func pingsDoNotHoldTheSessionOpen() {
		// The distinction the two windows exist for: the harness process is
		// plainly alive -- it is pinging -- and the agent has stopped testing.
		let outcome = run(
			[hello(), request(2, "ping"), request(3, "ping"), request(4, "ping"), .closed],
			config: SessionConfig(readerVersion: "test", heartbeatTimeout: 100, inactivityTimeout: 120),
			advancePerRead: 60
		)
		#expect(outcome.closedReason == TeardownReason.inactivityTimeout.rawValue)
	}

	@Test("a real command DOES reset it, so a slow but working agent is never cut off")
	func aRealCommandResetsInactivity() {
		let outcome = run(
			[hello(), request(2, "echo"), request(3, "echo"), request(4, "echo"), .closed],
			config: SessionConfig(readerVersion: "test", heartbeatTimeout: 100, inactivityTimeout: 120),
			advancePerRead: 60
		)
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}

	// -- ending --------------------------------------------------------------

	@Test("bye is acknowledged BEFORE the session closes")
	func byeIsAcknowledged() {
		let outcome = run([hello(), request(2, "bye"), request(3, "ping")])
		#expect(outcome.replies.count == 2)
		#expect(outcome.replies[1].id == 2)
		#expect(outcome.closedReason == TeardownReason.clientBye.rawValue)
	}

	@Test("the peer going away is a normal ending")
	func theClientHangsUp() {
		let outcome = run([hello(), .closed])
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}

	@Test("a teardown asked for from another thread is honoured at the next wakeup")
	func externalTeardown() {
		let clock = FakeClock()
		let channel = FakeChannel([hello(), .quiet, .quiet, .quiet])
		let transcript = FakeTranscript()
		let session = Session(
			channel: channel,
			transcript: transcript,
			clock: clock,
			config: SessionConfig(readerVersion: "test"),
			handlers: defaultHandlers(),
			signals: FakeSessionSignals()
		)
		// Standing in for the control dialog or a machine shutting the bridge
		// down: the request lands mid-run and the loop notices at its next read.
		var reads = 0
		channel.onRead = {
			reads += 1
			if reads == 2 { session.requestTeardown(.external) }
		}
		session.run()
		#expect(transcript.closedReasons.last == TeardownReason.external.rawValue)
	}

	@Test("the first teardown request wins; a later one does not rewrite the reason")
	func theFirstReasonWins() {
		let clock = FakeClock()
		let channel = FakeChannel([hello(), .quiet, .quiet])
		let transcript = FakeTranscript()
		let session = Session(
			channel: channel,
			transcript: transcript,
			clock: clock,
			config: SessionConfig(readerVersion: "test"),
			handlers: defaultHandlers(),
			signals: FakeSessionSignals()
		)
		channel.onRead = {
			session.requestTeardown(.external)
			session.requestTeardown(.heartbeatTimeout)
		}
		session.run()
		#expect(transcript.closedReasons.last == TeardownReason.external.rawValue)
	}

	@Test("teardown always closes the channel and the transcript, once")
	func teardownRunsOnce() {
		let outcome = run([hello(), request(2, "bye")])
		#expect(outcome.channel.isClosed)
		#expect(outcome.transcript.closedReasons.count == 1)
		#expect(outcome.signals.endedCount == 1)
	}

	@Test("teardown STOPS what the handshake started")
	func teardownStopsCapture() {
		// The reader edge is started by hello and must be stopped on every exit
		// path, however the session ended. A source left running would go on
		// appending into a buffer nobody will ever read, holding the feed's file
		// open past the session that opened it.
		let source = FakeSpeechSource()
		let handler = FakeHandler(availableBeforeHello: true)
		handler.onExecute = { context, _ in
			context.adapters = AdapterSet(mode: .live, speechSource: source)
		}
		let outcome = run(
			[hello(), request(2, "bye")], handlers: ["hello": handler, "bye": byeHandler()]
		)
		#expect(source.stopCount == 1)
		#expect(outcome.transcript.closedReasons.count == 1)
	}

	@Test("a session torn down from another thread stops capture just the same")
	func anExternalTeardownStopsCapture() {
		let source = FakeSpeechSource()
		let handler = FakeHandler(availableBeforeHello: true)
		handler.onExecute = { context, _ in
			context.adapters = AdapterSet(mode: .live, speechSource: source)
		}
		let clock = FakeClock()
		let channel = FakeChannel([hello(), .quiet])
		let session = Session(
			channel: channel,
			transcript: FakeTranscript(),
			clock: clock,
			config: SessionConfig(readerVersion: "macOS 15.0.0"),
			handlers: ["hello": handler],
			signals: FakeSessionSignals()
		)
		channel.onRead = { session.requestTeardown(.external) }
		session.run()
		#expect(source.stopCount == 1)
	}

	@Test("a session that never got past the handshake has nothing to stop, and does not try")
	func teardownWithoutAHandshake() {
		// Naturally skipped rather than guarded: the adapter set is nil until
		// hello installs one, which is what the optional on the context buys.
		let outcome = run([.closed])
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}

	@Test("a session that never established gets no end cue")
	func noEndCueWithoutAStart() {
		let outcome = run([.closed])
		#expect(outcome.signals.startedWith.isEmpty)
		#expect(outcome.signals.endedCount == 0)
		#expect(outcome.transcript.closedReasons.last == TeardownReason.channelClosed.rawValue)
	}

	@Test("a cue that FAILS costs neither the handshake nor the teardown")
	func aFailingCueIsGuarded() {
		// A courtesy is never worth a session. The start cue reaches an audio
		// device that may be gone, and a session that died because a tone could
		// not be played would be a bridge that works only on a machine with
		// speakers.
		let signals = FakeSessionSignals()
		signals.fails = true
		let outcome = run([hello(), request(2, "ping"), .closed], signals: signals)
		#expect(outcome.replies.count == 2)
		#expect(signals.startedWith.count == 1)
		#expect(signals.endedCount == 1)
		#expect(outcome.channel.isClosed)
		#expect(outcome.closedReason == TeardownReason.channelClosed.rawValue)
	}
}
