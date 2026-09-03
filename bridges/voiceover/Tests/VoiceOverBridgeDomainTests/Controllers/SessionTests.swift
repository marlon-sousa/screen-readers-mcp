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
			context.adapters = fakeAdapterSet(speechSource: source)
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
			context.adapters = fakeAdapterSet(speechSource: source)
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

	// -- hard invariant 3, in its macOS form (13.6) -----------------------------

	/// A session whose handshake installs a reader edge of doubles, so teardown
	/// can be watched.
	private func edgeHandler(_ set: AdapterSet, mode: CaptureMode = .live) -> FakeHandler {
		let handler = FakeHandler(availableBeforeHello: true)
		handler.onExecute = { context, _ in
			context.mode = mode
			context.adapters = set
			context.previousVoice = "com.apple.eloquence.pt-BR.Reed"
		}
		return handler
	}

	@Test("TEARDOWN RELEASES THE SILENCE AND PUTS THE USER'S VOICE BACK, in that order")
	func teardownRestores() {
		// Pass-through first: if the restoration fails, a released marker still
		// leaves the human hearing their machine through our voice -- degraded, and
		// safe. The reverse order leaves a window where the reader is back on the
		// user's own voice while a marker still says silence.
		let silence = FakeSilenceControl()
		let lifecycle = FakeProviderLifecycle()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: lifecycle)
		run([hello(), request(2, "bye")], handlers: ["hello": edgeHandler(set), "bye": byeHandler()])
		#expect(silence.acts.last == .release)
		#expect(lifecycle.restored == ["com.apple.eloquence.pt-BR.Reed"])
	}

	@Test("restoration runs however the session ended -- including a watchdog firing")
	func teardownRestoresOnEveryPath() {
		let silence = FakeSilenceControl()
		let lifecycle = FakeProviderLifecycle()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: lifecycle)
		let outcome = run(
			[hello(), .quiet, .quiet],
			handlers: ["hello": edgeHandler(set)],
			advancePerRead: 40
		)
		#expect(outcome.closedReason == TeardownReason.heartbeatTimeout.rawValue)
		#expect(silence.acts.contains(.release))
		#expect(lifecycle.restored == ["com.apple.eloquence.pt-BR.Reed"])
	}

	@Test("A FAILED RESTORATION IS WRITTEN DOWN, because a human has to know they are still on our voice")
	func aFailedRestorationIsReported() {
		let lifecycle = FakeProviderLifecycle()
		lifecycle.restoreRefusal = ProviderError("the write did not take")
		let set = fakeAdapterSet(providerLifecycle: lifecycle)
		let outcome = run(
			[hello(), request(2, "bye")], handlers: ["hello": edgeHandler(set), "bye": byeHandler()])
		#expect(outcome.transcript.notes.contains { $0.contains("did not take") })
		// And the rest of teardown still ran.
		#expect(outcome.channel.isClosed)
		#expect(outcome.transcript.closedReasons.count == 1)
	}

	@Test("nothing is restored when there was nothing to restore")
	func nothingToRestore() {
		// The reader was already on our voice when the session started, which means
		// a previous one died without restoring. Writing our own voice back would
		// be the bridge keeping the machine on the capture voice deliberately.
		let lifecycle = FakeProviderLifecycle()
		let set = fakeAdapterSet(providerLifecycle: lifecycle)
		let handler = FakeHandler(availableBeforeHello: true)
		handler.onExecute = { context, _ in context.adapters = set }
		run([hello(), request(2, "bye")], handlers: ["hello": handler, "bye": byeHandler()])
		#expect(lifecycle.restored.isEmpty)
	}

	// -- the third watchdog -----------------------------------------------------

	@Test("THE LEASE IS RENEWED WHILE THE SESSION LIVES, on every wakeup including quiet ones")
	func theLeaseIsRenewed() {
		// This is what makes a SIGKILLed bridge un-mute the machine: the extension
		// treats a marker nobody refreshed as pass-through, so silence survives
		// exactly as long as this loop does.
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		run(
			[hello(), .quiet, .quiet, request(2, "bye")],
			handlers: ["hello": edgeHandler(set, mode: .silent), "bye": byeHandler()])
		#expect(silence.renewals >= 3)
	}

	@Test("a LIVE session renews too: the marker carries the user's voice in both modes")
	func liveRenewsAsWell() {
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		run(
			[hello(), .quiet, request(2, "bye")],
			handlers: ["hello": edgeHandler(set), "bye": byeHandler()])
		#expect(silence.renewals >= 2)
	}

	@Test("the cap WARNS the human before it acts, once")
	func theCapWarns() {
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		let outcome = run(
			[hello(), .quiet, .quiet],
			handlers: ["hello": edgeHandler(set, mode: .silent)],
			config: SessionConfig(readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		#expect(signals.warnedCount == 1)
		#expect(outcome.transcript.notes.contains { $0.contains("silence cap") })
	}

	@Test("THE CAP LIFTS THE SILENCE, which is the guarantee rather than the courtesy")
	func theCapLifts() {
		// Capture is untouched: the same entries, at the same indices, with the
		// same stamps. The agent loses its silence and none of its evidence.
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		run(
			[hello(), .quiet, .quiet, .quiet],
			handlers: ["hello": edgeHandler(set, mode: .silent)],
			config: SessionConfig(readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		#expect(silence.acts.contains(.passThrough))
		#expect(signals.liftedCount == 1)
	}

	@Test("THE SILENCE RE-ARMS AFTER AN ANNOUNCEMENT, AND THE LOOP IS WHAT DOES IT")
	func theCapReArmsAfterTheHumanHears() {
		// THE DEFECT, ASSERTED AT THE LAYER THAT REPEATS. Reported by Marlon on
		// 2026-09-01 driving the bridge: connect silent, stay quiet, get warned,
		// stay quiet, get lifted, then announce -- and the machine stayed audible
		// for the rest of the session.
		//
		// It is a SESSION test rather than an entity one on purpose, and this file
		// already carries the reason (AGENTS.md, learned 2026-08-30): a passing
		// `swift test` does not prove the loop calls what you added. The entity's
		// own tests would go on passing against a `checkSilence` that never acted
		// on `.resuppress`, which is exactly the shape of the 13.6 lease bug.
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		// The command that tells the human something: it is the ONLY thing in this
		// script that resets the window, which is the contract's own rule -- four
		// hundred gestures would reset nothing.
		let narrate = FakeHandler()
		narrate.onExecute = { context, _ in context.humanHeard() }
		let outcome = run(
			// It ends at the announcement, on purpose: another two quiet reads at
			// 50 s each would lift the FRESH window as well, which is correct
			// behaviour and would make this test about something else.
			[hello(), .quiet, .quiet, .quiet, request(2, "announce"), .closed],
			handlers: ["hello": edgeHandler(set, mode: .silent), "announce": narrate],
			// BOTH watchdogs held off, not just the heartbeat: this script advances
			// the clock past the 120 s inactivity default, and a session torn down
			// for going idle would answer the question by not reaching it.
			config: SessionConfig(
				readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000, inactivityTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		// Lifted once, then taken back once. The assertion that matters is the
		// ORDER of the two acts that change what the human can hear: before this
		// fix the sequence ended at `passThrough` and never came back, whatever the
		// agent said afterwards. (`release` follows at teardown in every session,
		// which is why the raw last act is not the thing to look at.)
		#expect(signals.liftedCount == 1)
		#expect(signals.resuppressedCount == 1)
		let audibility = silence.acts.filter { $0 == .suppress || $0 == .passThrough }
		#expect(audibility.contains(.passThrough))
		#expect(audibility.last == .suppress)
		#expect(outcome.transcript.notes.contains { $0.contains("re-armed") })
	}

	@Test("nothing audible, nothing re-armed: a lifted session stays audible until it is told")
	func aLiftedSessionStaysAudibleWithoutAnAnnouncement() {
		// The control for the test above, and the half that must not regress: the
		// lift happened because the human had been told nothing for ninety seconds,
		// so re-arming on the clock alone would take their machine away again for
		// the very reason it was given back.
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		run(
			[hello(), .quiet, .quiet, .quiet, .quiet, .quiet, .quiet],
			handlers: ["hello": edgeHandler(set, mode: .silent)],
			config: SessionConfig(
				readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000, inactivityTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		#expect(signals.liftedCount == 1)
		#expect(signals.resuppressedCount == 0)
		let audibility = silence.acts.filter { $0 == .suppress || $0 == .passThrough }
		#expect(audibility.last == .passThrough)
	}

	@Test("a re-arm cue that fails does not leave the machine audible")
	func aFailedReArmCueStillSuppresses() {
		// The same ranking the lift already has, pointing the other way: the cue is
		// a courtesy and the suppression is what the session promised. A cue that
		// could undo it would be a courtesy with more power than the guarantee.
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		let narrate = FakeHandler()
		narrate.onExecute = { context, _ in
			context.humanHeard()
			signals.fails = true
		}
		run(
			// It ends at the announcement, on purpose: another two quiet reads at
			// 50 s each would lift the FRESH window as well, which is correct
			// behaviour and would make this test about something else.
			[hello(), .quiet, .quiet, .quiet, request(2, "announce"), .closed],
			handlers: ["hello": edgeHandler(set, mode: .silent), "announce": narrate],
			// BOTH watchdogs held off, not just the heartbeat: this script advances
			// the clock past the 120 s inactivity default, and a session torn down
			// for going idle would answer the question by not reaching it.
			config: SessionConfig(
				readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000, inactivityTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		// The suppression ran and the cue threw: the last act that changed what the
		// human can hear is still the re-arm. (`isSuppressing` is false by the time
		// this reads it, because teardown releases the marker on every path.)
		let audibility = silence.acts.filter { $0 == .suppress || $0 == .passThrough }
		#expect(audibility.last == .suppress)
		#expect(signals.resuppressedCount == 1)
	}

	@Test("a LIVE session is never capped, because nothing is being withheld")
	func liveIsNotCapped() {
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		run(
			[hello(), .quiet, .quiet, .quiet],
			handlers: ["hello": edgeHandler(set)],
			config: SessionConfig(readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		#expect(signals.warnedCount == 0)
		#expect(silence.acts.contains(.passThrough) == false)
	}

	@Test("an UNATTENDED machine is never lifted: un-muting a room with nobody in it is damage")
	func unattendedIsNotLifted() {
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		run(
			[hello(), .quiet, .quiet, .quiet],
			handlers: ["hello": edgeHandler(set, mode: .silent)],
			config: SessionConfig(
				readerVersion: "macOS 15.0.0",
				heartbeatTimeout: 1000,
				attended: false,
				silenceCap: SilenceCapPolicy(enabled: false)
			),
			signals: signals,
			advancePerRead: 50
		)
		#expect(signals.liftedCount == 0)
		#expect(silence.acts.contains(.passThrough) == false)
		// The lease is still renewed: the silence the machine asked for holds, and
		// it still expires if this process dies.
		#expect(silence.renewals >= 3)
	}

	@Test("a cue that fails does not stop the lift: the guarantee outranks the courtesy")
	func aFailedCueDoesNotStopTheLift() {
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, providerLifecycle: FakeProviderLifecycle())
		let signals = FakeSessionSignals()
		signals.fails = true
		run(
			[hello(), .quiet, .quiet, .quiet],
			handlers: ["hello": edgeHandler(set, mode: .silent)],
			config: SessionConfig(readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		#expect(silence.acts.contains(.passThrough))
	}

	// -- the human channel's two effects on the loop (13.10) --------------------

	/// A handshake that also leaves a question in front of the human, so the loop
	/// can be watched with a window open.
	private func askingHandler(_ set: AdapterSet, _ prompter: FakeUserPrompter) -> FakeHandler {
		let handler = FakeHandler(availableBeforeHello: true)
		handler.onExecute = { context, _ in
			context.mode = .silent
			context.adapters = set
			let ticket = try? prompter.present("did the menu open?")
			context.outstandingPrompt = UserPrompt(
				ticket: ticket ?? "", prompt: "did the menu open?", now: context.clock.monotonic())
		}
		return handler
	}

	@Test("AN OPEN QUESTION HOLDS THE SILENCE WINDOW OPEN, however long the human takes")
	func anOpenPromptKeepsTheCapFresh() {
		// A human reading a prompt IS hearing their machine -- `askUser` gave the
		// reader back to let them answer (protocol.md §5). A cap that went on
		// counting through that would lift a suppression that is not in force and
		// mark itself lifted for the rest of the session, so the next command would
		// be unable to make the machine quiet again.
		let prompter = FakeUserPrompter()
		let silence = FakeSilenceControl()
		let set = fakeAdapterSet(silenceControl: silence, userPrompter: prompter)
		let signals = FakeSessionSignals()
		run(
			[hello(), .quiet, .quiet, .quiet, .quiet],
			handlers: ["hello": askingHandler(set, prompter)],
			config: SessionConfig(readerVersion: "macOS 15.0.0", heartbeatTimeout: 1000),
			signals: signals,
			advancePerRead: 50
		)
		#expect(signals.warnedCount == 0)
		#expect(signals.liftedCount == 0)
		#expect(!silence.acts.contains(.passThrough))
		// AND THE LEASE IS STILL RENEWED, which is the half that must not be traded
		// for the other: an open prompt suspends the CAP, never the expiry that
		// un-mutes a machine whose bridge has died.
		#expect(silence.renewals >= 4)
	}

	@Test("TEARDOWN TAKES AN OPEN QUESTION OFF THE SCREEN")
	func teardownCancelsAnOpenPrompt() {
		// A question outlives the session that asked it otherwise, and there is
		// nobody left to answer it to.
		let prompter = FakeUserPrompter()
		let set = fakeAdapterSet(userPrompter: prompter)
		let outcome = run(
			[hello(), request(2, "bye")],
			handlers: ["hello": askingHandler(set, prompter), "bye": byeHandler()])
		#expect(prompter.cancelled == [prompter.lastTicket])
		#expect(outcome.session.sessionContext.outstandingPrompt == nil)
	}
}
