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
		modifier: FakeReaderModifierSetting = FakeReaderModifierSetting(),
		keys: FakeKeyPresser = FakeKeyPresser(),
		silence: FakeSilenceControl = FakeSilenceControl(),
		speechSource: FakeSpeechSource = FakeSpeechSource(),
		transcript: FakeTranscript = FakeTranscript(),
		restart: FakeReaderRestart = FakeReaderRestart(),
		journal: FakeChangeJournal = FakeChangeJournal(),
		announcer: FakeAnnouncer = FakeAnnouncer(),
		captureProbeSpeaks: Bool = true
	) -> (setup: ReaderEdgeSetup, context: SessionContext, speech: SpeechBuffer) {
		let adapters = fakeAdapterSet(
			mode: mode,
			speechSource: speechSource,
			silenceControl: silence,
			providerLifecycle: lifecycle,
			readerLiveness: liveness,
			keyPresser: keys,
			readerModifier: modifier,
			readerRestart: restart,
			changeJournal: journal,
			permissions: permissions,
			announcer: announcer,
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

	// ==========================================================================
	// 13.26: REGISTERING PUBLISHES, WHICH IS THE RUNG 13.20 COULD NOT CLIMB.
	// ==========================================================================

	@Test("REGISTERING RESTARTS THE READER, because nothing else publishes the voice")
	func registeringPublishesByRestarting() throws {
		// macOS offers a newly registered voice only after VoiceOver restarts. 13.20
		// could only NAME that restart and ask a human to run it; spec 0053 §3.2 lets
		// the handshake take it. In practice the trigger is `poe build`, which begins
		// `rm -rf build` and makes the system forget the extension.
		let lifecycle = FakeProviderLifecycle()
		lifecycle.machineState = .notRegistered
		lifecycle.stateAfterRegistering = .registered
		let restart = FakeReaderRestart()
		let announcer = FakeAnnouncer()
		let machine = machine(lifecycle: lifecycle, restart: restart, announcer: announcer)
		try machine.setup.establish()
		#expect(lifecycle.registerCalls == 1)
		#expect(restart.restarts == 1)
		// ANNOUNCED FIRST, like every restart this bridge takes.
		#expect(announcer.spoken.first?.contains("restarting VoiceOver") == true)
	}

	@Test("a machine that never needed registering is never restarted")
	func anAlreadyPublishedVoiceCostsNoRestart() throws {
		// THE CONTROL, and it is the one that matters: the blind person who has not
		// rebuilt anything must pay no restart at all. Only the developer who just
		// ran `poe build` does.
		let lifecycle = FakeProviderLifecycle()
		lifecycle.machineState = .published
		let restart = FakeReaderRestart()
		let machine = machine(lifecycle: lifecycle, restart: restart)
		try machine.setup.establish()
		#expect(lifecycle.registerCalls == 0)
		#expect(restart.restarts == 0)
	}

	@Test("a restart that FAILS here is written down, and a LATER rung refuses by name")
	func afailedPublishingRestartIsNotFatalHere() {
		// The difference from the modifier rung. There, the restart is the only thing
		// that puts the reader on keys this bridge can press, so failing it fails the
		// rung. Here this rung cannot tell whether the failure mattered -- so it says
		// so and climbs on, and the rung that CAN tell refuses by name with a recovery
		// that fits. This test is the record that the session is still refused: not
		// failing here must never mean establishing a session that cannot capture,
		// which is the whole of 13.20.
		let lifecycle = FakeProviderLifecycle()
		lifecycle.machineState = .notRegistered
		lifecycle.stateAfterRegistering = .registered
		let restart = FakeReaderRestart()
		restart.failure = ReaderRestartError("it would not stop", readerStillRunning: true)
		let transcript = FakeTranscript()
		let machine = machine(lifecycle: lifecycle, transcript: transcript, restart: restart)
		let message = failure { try machine.setup.establish() }
		#expect(
			transcript.notes.contains { $0.contains("could not be restarted to publish") })
		// THE SESSION STILL STANDS, because the restart was not what decided anything
		// here: the voice was published before it, so the reader has it.
		#expect(message == nil)
	}

	// -- what the journal records ----------------------------------------------

	@Test("the voice change is journalled, because it is the one a crash leaves dangerous")
	func theVoiceChangeIsRecorded() throws {
		// 13.23: a session that dies leaves the capture voice selected, and the next
		// reader restart finds it unpublished, falls back AND PERSISTS THE FALLBACK.
		// The 2026-09-02 field report is that failure with a human recovering it by
		// hand, and the hand recovery cost them their pitch, rate and volume.
		let lifecycle = FakeProviderLifecycle()
		lifecycle.selected = "com.apple.voice.premium.pt-BR.Luciana"
		let journal = FakeChangeJournal()
		let machine = machine(lifecycle: lifecycle, journal: journal)
		try machine.setup.establish()
		// OPEN, because the handshake does not put the voice back -- teardown does.
		#expect(journal.openKinds == [.voice])
		let entry = try #require(journal.entries.first)
		#expect(entry.change.was == "com.apple.voice.premium.pt-BR.Luciana")
		#expect(entry.change.store.contains("com.apple.SpeakSelection"))
	}

	// -- the healthy climb -----------------------------------------------------

	@Test("A HEALTHY MACHINE CLIMBS ALL FIVE RUNGS, and the proof is an utterance arriving")
	func aHealthyMachineClimbs() throws {
		let keys = FakeKeyPresser()
		let lifecycle = FakeProviderLifecycle()
		let transcript = FakeTranscript()
		let (setup, context, speech) = machine(
			lifecycle: lifecycle, keys: keys, transcript: transcript)
		try setup.establish()

		// The reader was pointed at our voice, and what the user had is held for
		// teardown.
		#expect(lifecycle.selectCalls == 1)
		#expect(context.previousVoice == "com.apple.voice.compact.pt-BR.Luciana")
		// The probe was pressed, and its answer is in the buffer -- which is the
		// only evidence `ProviderState.capturing` accepts.
		#expect(keys.describedPresses == ["control+option+f7"])
		#expect(speech.lastIndex() == 1)
		#expect(lifecycle.state().observing(captured: !speech.isEmpty) == .capturing)
		#expect(transcript.notes.contains { $0.contains("capturing") })
	}

	// ==========================================================================
	// 13.24: A USER'S VOICE THIS MACHINE NO LONGER PUBLISHES.
	// ==========================================================================
	//
	// THE THREE TESTS BELOW ARE ONE DECISION IN THREE HALVES, and the decision is
	// spec 0056 §2.2 -- Marlon, 2026-09-03: *"I would like to have a default voice,
	// but that handshake announcement must let the user know and give them
	// instructions to install the voice."* So: the session ESTABLISHES, the person
	// is TOLD, and the identifier is recorded ANYWAY so teardown still takes the
	// reader off the capture voice.
	//
	// THE FOURTH IS THE CONTROL, and it is the one that would catch the mistake
	// most likely to be made here: announcing on every handshake because the
	// resolution was written the wrong way round.

	@Test("A VOICE THIS MACHINE NO LONGER PUBLISHES DOES NOT REFUSE THE SESSION")
	func aRemovedVoiceStillEstablishes() throws {
		// The machine was already in this state before the session connected. It did
		// not cause it, it cannot fix it, and refusing would deny testing on a reader
		// that is otherwise perfectly capable -- while putting nothing back.
		let lifecycle = FakeProviderLifecycle(selected: "com.apple.voice.gone.pt-BR.Ghost")
		lifecycle.publishedVoices = ["com.apple.voice.compact.pt-BR.Luciana"]
		let (setup, context, _) = machine(lifecycle: lifecycle)
		try setup.establish()
		// Recorded ANYWAY: writing it at teardown is what takes the reader off the
		// capture voice, and refusing to record would leave our own voice selected --
		// 13.23's hazard, reached by the cleanup itself.
		#expect(context.previousVoice == "com.apple.voice.gone.pt-BR.Ghost")
		#expect(lifecycle.selectCalls == 1)
	}

	@Test("AND THE PERSON IS TOLD OUT LOUD, with the identifier and how to install it")
	func aRemovedVoiceIsAnnounced() throws {
		// SPOKEN rather than noted, and that is the whole of Marlon's answer: it goes
		// through the bridge's own synthesizer, which is audible even in a silent
		// session because it goes around the reader entirely. A transcript note
		// reaches an agent; only this reaches the person who can act on it.
		let lifecycle = FakeProviderLifecycle(selected: "com.apple.voice.gone.pt-BR.Ghost")
		lifecycle.publishedVoices = []
		let announcer = FakeAnnouncer()
		let transcript = FakeTranscript()
		let (setup, _, _) = machine(
			mode: .silent, lifecycle: lifecycle, transcript: transcript, announcer: announcer)
		try setup.establish()

		let spoken = try #require(announcer.spoken.first { $0.contains("com.apple.voice.gone") })
		// The recovery, in full: a half-named settings path is a path somebody hunts
		// for, and this one is read aloud rather than clicked from a link.
		#expect(spoken.contains("Manage Voices"))
		#expect(spoken.contains("System Settings"))
		#expect(transcript.notes.contains { $0.contains(ReaderCondition.usersVoiceNotAvailable.rawValue) })
	}

	@Test("an ordinary machine is told nothing at all about its voice")
	func aPublishedVoiceIsNotAnnounced() throws {
		// THE CONTROL. A resolution written the wrong way round would announce on
		// every single handshake, which is the mistake this test exists to catch --
		// and the one a person would notice most.
		let lifecycle = FakeProviderLifecycle(selected: "com.apple.voice.compact.pt-BR.Luciana")
		lifecycle.publishedVoices = ["com.apple.voice.compact.pt-BR.Luciana"]
		let announcer = FakeAnnouncer()
		let (setup, context, _) = machine(lifecycle: lifecycle, announcer: announcer)
		try setup.establish()
		#expect(announcer.spoken.isEmpty)
		#expect(context.previousVoice == "com.apple.voice.compact.pt-BR.Luciana")
	}

	@Test("a session that finds OUR OWN voice selected asks nothing about it")
	func theCaptureVoiceIsNotResolvedAsTheUsers() throws {
		// A previous session died without restoring, so the reader is on our voice.
		// `previousVoice` stays nil -- Rule 0's first caveat -- and there is
		// therefore nothing to resolve and nobody to warn. A resolution placed
		// outside that guard would announce that the CAPTURE voice is missing, which
		// is both false and alarming.
		let lifecycle = FakeProviderLifecycle(selected: "org.screen-readers-mcp.capture.voice")
		lifecycle.publishedVoices = []
		let announcer = FakeAnnouncer()
		let (setup, context, _) = machine(lifecycle: lifecycle, announcer: announcer)
		try setup.establish()
		#expect(context.previousVoice == nil)
		#expect(announcer.spoken.isEmpty)
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
		let liveness = FakeReaderLiveness(isRunning: true)
		let (setup, _, _) = machine(liveness: liveness)
		try setup.establish()
		#expect(liveness.activations == 0)
	}

	// -- rung 1: permissions ---------------------------------------------------

	@Test("A MISSING GRANT STOPS THE HANDSHAKE, AND NOTHING ASKS FOR IT")
	func aMissingGrantStopsTheClimbWithoutAsking() {
		// 13.8's LEVER, DEFENDED FROM THE ENTRY THAT MOST WANTED TO SPEND IT. The
		// handshake READS the grant and never requests it: `request` raises a system
		// consent dialog, and a handshake that waited on a modal nobody may be
		// looking at is a handshake that hangs. There are still exactly two callers
		// of `request` in this bridge and both are command handlers.
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

	@Test("the refusal tells the AGENT what to do, and names the one route there is")
	func theRefusalIsAddressedToTheAgent() {
		// The audience is not the person at the machine -- nobody may be there.
		//
		// IT NAMED TWO WAYS OUT FROM 13.26 TO 13.31, because either grant was enough
		// on its own and a refusal naming one would send a human to grant the wrong
		// thing. There is one route now: this bridge presses the keys a person
		// presses, so Accessibility and a pressable modifier are the whole of it.
		let (setup, _, _) = machine(permissions: FakePermissionBroker(state: .notGranted))
		let message = failure { try setup.establish() }
		#expect(message?.contains("ask the human at this machine") == true)
		#expect(message?.contains("connect again") == true)
		#expect(message?.contains("Accessibility") == true)
		#expect(message?.contains("VoiceOver Utility") == true)
		// AND IT NO LONGER MENTIONS APPLESCRIPT, which would send a human to switch
		// on a channel this bridge does not use -- the very switch 13.31 exists so
		// that nobody has to leave on.
		#expect(message?.contains("AppleScript") == false)
	}

	// -- rung 1 as a ROUTE check, which is 13.26 as 13.31 narrowed it ------------

	@Test("ACCESSIBILITY AND A PRESSABLE MODIFIER ARE THE WHOLE REQUIREMENT")
	func keysAloneEstablish() throws {
		// 13.26's point, arrived at from the other side. That entry widened this rung
		// so a machine with no AppleScript control could still get a session, because
		// "Allow VoiceOver to be controlled with AppleScript" lets any process drive
		// a blind person's screen reader and requiring it was asking them to hold a
		// door open for everyone. 13.31 deleted the other route entirely, so what was
		// then one of two acceptable answers is now the only one.
		let permissions = FakePermissionBroker(state: .granted)
		let (setup, _, _) = machine(permissions: permissions)
		try setup.establish()
		#expect(permissions.requests.isEmpty)
	}

	@Test("A CAPS LOCK MACHINE IS REFUSED, and the refusal says what to change")
	func aCapsLockMachineIsRefused() {
		// THE ONE MACHINE 13.31 MAKES STRICTLY WORSE, and it is named rather than
		// hidden: a synthesized Caps Lock is invisible to the reader (measured
		// 2026-09-02), so a machine bound to it cannot be driven by keys -- and until
		// this entry it could still be driven by name. It is board entry 13.28.
		let (setup, _, _) = machine(modifier: FakeReaderModifierSetting(.capsLock))
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.permissions.rawValue) == true)
		#expect(message?.contains("capsLock") == true)
		#expect(message?.contains("Control-Option") == true)
	}

	@Test("an UNREADABLE modifier is refused too, because pressing it would be a guess")
	func anUnreadableModifierIsRefused() {
		// What 13.19 refused was GUESSING, and guessing is still refused. "I could
		// not look" is not "it is at its default".
		let (setup, _, _) = machine(modifier: FakeReaderModifierSetting(.unknown))
		#expect(failure { try setup.establish() } != nil)
	}

	@Test("the grant is read ONCE, and never requested")
	func eachGrantIsReadOnce() throws {
		// The modifier is read once at rung 1 and CARRIED to rung 5 rather than
		// asked for again, so a handshake cannot read the machine twice and get two
		// answers -- and so "nothing here requests anything" stays checkable.
		let permissions = FakePermissionBroker()
		let modifier = FakeReaderModifierSetting()
		let (setup, _, _) = machine(permissions: permissions, modifier: modifier)
		try setup.establish()
		#expect(permissions.statusReads == [.accessibility])
		#expect(permissions.requests.isEmpty)
		#expect(modifier.reads == 1)
	}

	// -- rung 2: a reader to talk to -------------------------------------------

	@Test("A READER THAT IS NOT ANSWERING IS STARTED, and then asked again")
	func theReaderIsStarted() throws {
		let liveness = FakeReaderLiveness(isRunning: false)
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
		let liveness = FakeReaderLiveness(isRunning: false)
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
		// `vo+f7` speaks the time and date and MOVES NOTHING. A probe that navigated
		// would make every connect a small invisible edit to where the person was
		// standing -- which is why `go to dock`, also guaranteed to speak, was
		// declined for it.
		//
		// IT IS PRESSED RATHER THAN DISPATCHED SINCE 13.31. The rung used to choose
		// the command name where the machine offered it, on the reasoning that a
		// probe is not a user act and a name sends no key into whatever window
		// somebody is sitting in. That route is gone, so the choice went with it.
		let keys = FakeKeyPresser()
		let (setup, _, speech) = machine(keys: keys)
		try setup.establish()
		#expect(keys.describedPresses == ["control+option+f7"])
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

	@Test("a probe that cannot be PRESSED is reported as that, not as silence")
	func aRefusedProbeIsItsOwnFailure() {
		// A bridge that could not press the probe never learned anything about
		// capture, so reporting "nothing was captured" would be blaming the voice
		// for a keyboard.
		let keys = FakeKeyPresser()
		keys.failures["control+option+f7"] = KeyPressFailure("the event could not be posted")
		let (setup, _, _) = machine(keys: keys)
		let message = failure { try setup.establish() }
		#expect(message?.contains(SetupRung.captureProof.rawValue) == true)
		#expect(message?.contains("could not be pressed") == true)
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
		let keys = FakeKeyPresser()
		var suppressedWhenPressed = false
		keys.onPress = { _ in suppressedWhenPressed = silence.isSuppressing }
		let (setup, _, _) = machine(mode: .silent, keys: keys, silence: silence)
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
		// AND IT WILL NOT PUBLISH EITHER, which is what makes this the dead end. Until
		// 13.26 those were one step; publishing is its own act now, and a machine that
		// registers and never publishes is the state the first live connect hit.
		lifecycle.stateAfterPublishing = .registered
		for mode in [CaptureMode.silent, .live] {
			let (setup, _, _) = machine(mode: mode, lifecycle: lifecycle, silence: silence)
			_ = failure { try setup.establish() }
			#expect(!silence.isSuppressing)
		}
	}
}
