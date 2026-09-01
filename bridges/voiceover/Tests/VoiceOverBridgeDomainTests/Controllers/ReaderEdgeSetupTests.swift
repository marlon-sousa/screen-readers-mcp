// Mirrors Sources/VoiceOverBridgeDomain/Controllers/ReaderEdgeSetup.swift.
//
// WHAT THIS FILE IS ACTUALLY ABOUT. 13.20's claim is not "the bridge can
// register an extension" -- it is that a handshake either hands back a session
// that can capture, or says BY NAME what stopped it and what the agent must do.
// So every test below drives the whole climb and asserts on one rung's failure,
// and three of them assert on things that must NOT happen: no consent dialog is
// ever raised, no registration is ever undone, and the reader is never restarted.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("ReaderEdgeSetup")
struct ReaderEdgeSetupTests {
	/// The whole reader edge, every rung healthy, with the pieces a test wants to
	/// reach back into.
	///
	/// A builder rather than a fixture, for the reason AGENTS.md gives: every test
	/// here customises the machine -- a grant withheld, a reader that will not
	/// come up, a registration that does not take -- and one fixture per
	/// permutation is not a fixture.
	private func machine(
		mode: CaptureMode = .live,
		permissions: FakePermissionBroker = FakePermissionBroker(),
		liveness: FakeReaderLiveness = FakeReaderLiveness(),
		lifecycle: FakeProviderLifecycle = FakeProviderLifecycle(),
		gestures: FakeGestureSender = FakeGestureSender(),
		silence: FakeSilenceControl = FakeSilenceControl(),
		speechSource: FakeSpeechSource = FakeSpeechSource(),
		transcript: FakeTranscript = FakeTranscript(),
		captureProbeSpeaks: Bool = true
	) -> (setup: ReaderEdgeSetup, context: SessionContext, speech: SpeechBuffer) {
		let adapters = fakeAdapterSet(
			mode: mode,
			speechSource: speechSource,
			silenceControl: silence,
			providerLifecycle: lifecycle,
			gestureSender: gestures,
			readerLiveness: liveness,
			permissions: permissions,
			captureProbeSpeaks: captureProbeSpeaks
		)
		let clock = FakeClock()
		let context = SessionContext(
			clock: clock, transcript: transcript, attended: true, close: { _ in })
		context.adapters = adapters
		let speech = SpeechBuffer(clock: clock)
		speechSource.start(speech)
		context.speech = speech
		return (ReaderEdgeSetup(adapters: adapters, context: context, speech: speech), context, speech)
	}

	private func failure(_ block: () throws -> Void) -> String? {
		do {
			try block()
			return nil
		} catch let error as CommandError {
			return error.description
		} catch {
			Issue.record("unexpected error: \(error)")
			return nil
		}
	}

	// -- the healthy climb -----------------------------------------------------

	@Test("A HEALTHY MACHINE CLIMBS ALL FIVE RUNGS, and the proof is an utterance arriving")
	func aHealthyMachineClimbs() throws {
		let gestures = FakeGestureSender()
		let lifecycle = FakeProviderLifecycle()
		let transcript = FakeTranscript()
		let (setup, context, speech) = machine(
			lifecycle: lifecycle, gestures: gestures, transcript: transcript)
		try setup.establish()

		// The reader was pointed at our voice, and what the user had is held for
		// teardown.
		#expect(lifecycle.selectCalls == 1)
		#expect(context.previousVoice == "com.apple.voice.compact.pt-BR.Luciana")
		// The probe was pressed, and its answer is in the buffer -- which is the
		// only evidence `ProviderState.capturing` accepts.
		#expect(gestures.pressed == [ReaderEdgeSetup.captureProbeCommand])
		#expect(speech.lastIndex() == 1)
		#expect(lifecycle.state().observing(captured: !speech.isEmpty) == .capturing)
		#expect(transcript.notes.contains { $0.contains("capturing") })
	}

	@Test("an already-registered machine is not registered again")
	func registrationIsSkippedWhenItIsNotNeeded() throws {
		// Re-registering something already registered publishes nothing new and
		// costs two subprocesses and a five-second poll, so the ordinary handshake
		// pays one cheap read here.
		let lifecycle = FakeProviderLifecycle(machineState: .published)
		let (setup, _, _) = machine(lifecycle: lifecycle)
		try setup.establish()
		#expect(lifecycle.registerCalls == 0)
	}

	@Test("a reader already answering is not started")
	func theReaderIsNotStartedWhenItIsAlreadyThere() throws {
		let liveness = FakeReaderLiveness(answersItsOwnName: true)
		let (setup, _, _) = machine(liveness: liveness)
		try setup.establish()
		#expect(liveness.activations == 0)
	}

	// -- rung 1: permissions ---------------------------------------------------

	@Test("A MISSING GRANT STOPS THE HANDSHAKE, AND NOTHING ASKS FOR IT")
	func aMissingGrantStopsTheClimbWithoutAsking() {
		// 13.8's LEVER, DEFENDED FROM THE ENTRY THAT MOST WANTED TO SPEND IT. The
		// handshake reads both grants and requests neither: `request` raises a
		// system consent dialog, and a handshake that waited on a modal nobody may
		// be looking at is a handshake that hangs. There are still exactly two
		// callers of `request` in this bridge and both are command handlers.
		let permissions = FakePermissionBroker(state: .notGranted)
		let lifecycle = FakeProviderLifecycle()
		let (setup, _, _) = machine(permissions: permissions, lifecycle: lifecycle)
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.permissions.rawValue) == true)
		#expect(permissions.requests.isEmpty)
		// And it stopped before it touched anything: a refused handshake leaves the
		// machine exactly as it was.
		#expect(lifecycle.selectCalls == 0)
		#expect(lifecycle.registerCalls == 0)
	}

	@Test("the refusal tells the AGENT what to do, which is to ask a human and connect again")
	func theRefusalIsAddressedToTheAgent() {
		// The audience is not the person at the machine -- nobody may be there.
		// `Permission.recovery` is what a human acts on and it is carried INSIDE an
		// instruction the agent can actually carry out.
		let (setup, _, _) = machine(permissions: FakePermissionBroker(state: .notGranted))
		let message = failure { try setup.establish() }
		#expect(message?.contains("ask the human at this machine to grant it") == true)
		#expect(message?.contains("connect again") == true)
		#expect(message?.contains(Permission.accessibility.recovery) == true)
	}

	@Test("`cannotTell` stops it too, and says which read was inconclusive")
	func anUnreadableGrantStopsIt() {
		// Reporting it as `notGranted` would send a human to System Settings to fix
		// a grant they already hold, which is the false negative 13.11 removed.
		let (setup, _, _) = machine(permissions: FakePermissionBroker(state: .cannotTell))
		let message = failure { try setup.establish() }
		#expect(message?.contains("could not determine") == true)
	}

	@Test("BOTH grants are read, so a permission added later is one a session cannot skip")
	func everyPermissionIsRead() throws {
		let permissions = FakePermissionBroker()
		let (setup, _, _) = machine(permissions: permissions)
		try setup.establish()
		#expect(permissions.statusReads == Permission.allCases)
	}

	// -- rung 2: a reader to talk to -------------------------------------------

	@Test("A READER THAT IS NOT ANSWERING IS STARTED, and then asked again")
	func theReaderIsStarted() throws {
		let liveness = FakeReaderLiveness(answersItsOwnName: false)
		let transcript = FakeTranscript()
		let (setup, _, _) = machine(liveness: liveness, transcript: transcript)
		try setup.establish()
		#expect(liveness.activations == 1)
		#expect(transcript.notes.contains { $0.contains("starting it") })
	}

	@Test("a reader that will not come up fails by name, and nothing is restarted")
	func aReaderThatWillNotStartIsNamed() {
		// STARTING is all this rung may do. A restart takes the reader away from
		// somebody who may be using it, and the failure names it for a human
		// instead of taking it.
		let liveness = FakeReaderLiveness(answersItsOwnName: false)
		liveness.activationSucceeds = false
		let (setup, _, _) = machine(liveness: liveness)
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.readerRunning.rawValue) == true)
		#expect(message?.contains(ReaderCondition.readerNotRunning.rawValue) == true)
		#expect(message?.contains("killall") == false)
	}

	// -- rung 3: registration --------------------------------------------------

	@Test("AN UNREGISTERED MACHINE IS REGISTERED BY THE HANDSHAKE, which is the entry")
	func anUnregisteredMachineIsRepaired() throws {
		// `poe build` deletes and reassembles the bundle, so the system forgets the
		// extension and every session afterwards answers `speech: []`. This is the
		// repair, and it is the reason 13.20 exists.
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		let (setup, _, _) = machine(lifecycle: lifecycle)
		try setup.establish()
		#expect(lifecycle.registerCalls == 1)
		#expect(lifecycle.state() == .selected)
	}

	@Test("a registration that will not take fails by name, carrying what a human can run")
	func aFailedRegistrationIsNamed() {
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.registrationRefusal = ProviderError("pluginkit still does not list it")
		let (setup, _, _) = machine(lifecycle: lifecycle)
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.registration.rawValue) == true)
		#expect(message?.contains("pluginkit still does not list it") == true)
	}

	@Test("REGISTRATION IS MACHINE STATE: nothing here ever undoes it")
	func registrationIsNeverUndone() throws {
		// The symmetry is tempting and the temptation is the bug. Undoing it would
		// put the next session back in the state this entry repairs, and the accept
		// loop will not always be serial -- one client's disconnect must never
		// deregister the voice under another. There is no `unregister()` on the
		// port, and this is the test that fails if somebody adds one and calls it.
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		let (setup, _, _) = machine(lifecycle: lifecycle)
		try setup.establish()
		#expect(lifecycle.state() >= .registered)
		// A second session on the same machine finds it registered and leaves it be.
		let again = machine(lifecycle: lifecycle)
		try again.setup.establish()
		#expect(lifecycle.registerCalls == 1)
		#expect(lifecycle.state() >= .registered)
	}

	// -- rung 4: the voice -----------------------------------------------------

	@Test("THE USER'S OWN VOICE IS RECORDED BEFORE OURS IS WRITTEN")
	func thePreviousVoiceIsRecordedFirst() {
		// The order is what makes teardown able to put it back even when a LATER
		// rung throws -- and the capture proof is a later rung that really can.
		let lifecycle = FakeProviderLifecycle()
		let (setup, context, _) = machine(lifecycle: lifecycle, captureProbeSpeaks: false)
		_ = failure { try setup.establish() }
		#expect(context.previousVoice == "com.apple.voice.compact.pt-BR.Luciana")
	}

	@Test("OUR OWN leftover voice is not recorded as the user's")
	func ourVoiceIsNotTheUsers() throws {
		// Rule 0's first caveat: a session that died without restoring leaves our
		// voice selected, and recording that as "the user's own" would hand the
		// extension itself as its own pass-through voice -- infinite recursion.
		let lifecycle = FakeProviderLifecycle(selected: "org.screen-readers-mcp.capture.voice")
		let (setup, context, _) = machine(lifecycle: lifecycle)
		try setup.establish()
		#expect(context.previousVoice == nil)
		// And nothing was written: the reader is already on our voice.
		#expect(lifecycle.selectCalls == 0)
	}

	@Test("a voice that will not stick fails by name, with the condition nothing else can see")
	func aVoiceThatWillNotStickIsNamed() {
		let lifecycle = FakeProviderLifecycle()
		lifecycle.selectionRefusal = ProviderError("the capture voice was written and did not take")
		let (setup, _, _) = machine(lifecycle: lifecycle)
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.voiceSelection.rawValue) == true)
		#expect(message?.contains("did not take") == true)
	}

	// -- rung 5: the proof -----------------------------------------------------

	@Test("THE PROBE IS THE SAFE ONE, and it is pressed after the bookmark is taken")
	func theProbeMovesNothing() throws {
		// `describe item in voiceover cursor` describes what the cursor is on and
		// MOVES NOTHING. A probe that navigated would make every connect a small
		// invisible edit to where the person was standing.
		let gestures = FakeGestureSender()
		let (setup, _, speech) = machine(gestures: gestures)
		try setup.establish()
		#expect(gestures.pressed == ["describe item in voiceover cursor"])
		// The utterance the probe caused landed at 1, after the sentinel -- so it
		// was bookmarked before the press and not counted from stale speech.
		#expect(speech.entry(at: 1).text == captureProbeUtterance)
	}

	@Test("NOTHING ARRIVING IS A NAMED FAILURE that points at the reader restart")
	func silenceAfterTheProbeIsNamed() {
		// THE RUNG THIS BRIDGE CANNOT CLIMB. The system publishes a newly
		// registered voice only after VoiceOver restarts, and a handshake may not
		// restart a blind person's screen reader -- so the failure names the
		// restart as the remaining action and gives the command to do it with.
		let (setup, _, _) = machine(captureProbeSpeaks: false)
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.captureProof.rawValue) == true)
		#expect(message?.contains(readerRestartCommand) == true)
		// BOTH candidates named, because from outside the reader nothing
		// distinguishes them -- which is honest where "found: false" would be a
		// confident wrong answer.
		#expect(message?.contains(ReaderCondition.providerNotRunning.rawValue) == true)
		#expect(message?.contains(ReaderCondition.captureVoiceNotOfferedByReader.rawValue) == true)
	}

	@Test("a reader that will not take the probe is reported as that, not as silence")
	func aRefusedProbeIsItsOwnFailure() {
		let gestures = FakeGestureSender()
		gestures.failures[ReaderEdgeSetup.captureProbeCommand] = .scriptingChannelDead
		let (setup, _, _) = machine(gestures: gestures)
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.captureProof.rawValue) == true)
		#expect(message?.contains("would not take") == true)
	}

	// -- the marker channel, and where it sits ---------------------------------

	@Test("A SILENT SESSION IS SUPPRESSED BEFORE THE PROBE IS PRESSED, or the proof is audible")
	func silenceComesBeforeTheProof() throws {
		// The ordering is the whole reason the marker work lives in this controller
		// rather than in the handler: the proof makes the reader SPEAK, and in the
		// one mode whose promise is that a human hears nothing it has to be
		// inaudible. Capture is unaffected -- the capture voice emits to the sink
		// before it synthesizes (13.5), so a silent proof still proves.
		let silence = FakeSilenceControl()
		let gestures = FakeGestureSender()
		var suppressedWhenPressed = false
		gestures.onPress = { _ in suppressedWhenPressed = silence.isSuppressing }
		let (setup, _, _) = machine(mode: .silent, gestures: gestures, silence: silence)
		try setup.establish()
		#expect(suppressedWhenPressed)
		#expect(
			silence.acts == [
				.begin(preferredVoice: "com.apple.voice.compact.pt-BR.Luciana"), .suppress,
			])
	}

	@Test("a LIVE session opens the channel and suppresses nothing")
	func liveOpensTheChannelOnly() throws {
		// Open in both modes: it carries the user's own voice so pass-through is
		// acoustically invisible (Rule 0), and it is a lease the session renews.
		let silence = FakeSilenceControl()
		let (setup, _, _) = machine(mode: .live, silence: silence)
		try setup.establish()
		#expect(silence.acts == [.begin(preferredVoice: "com.apple.voice.compact.pt-BR.Luciana")])
		#expect(!silence.isSuppressing)
	}

	@Test("A FAILED CLIMB LEAVES THE MACHINE UNSUPPRESSED, in both modes")
	func arefusedSilentHandshakeSuppressesNothing() {
		// A refused promise must not take somebody's hearing away on its way out.
		let silence = FakeSilenceControl()
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.stateAfterRegistering = .registered
		for mode in [CaptureMode.silent, .live] {
			let (setup, _, _) = machine(mode: mode, lifecycle: lifecycle, silence: silence)
			_ = failure { try setup.establish() }
			#expect(!silence.isSuppressing)
		}
	}
}
