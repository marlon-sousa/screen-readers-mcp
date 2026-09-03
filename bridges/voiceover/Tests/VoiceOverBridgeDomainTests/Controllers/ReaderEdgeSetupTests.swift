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
		scripting: FakeReaderScriptingSetting = FakeReaderScriptingSetting(),
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
			gestureSender: gestures,
			readerLiveness: liveness,
			keyPresser: keys,
			readerModifier: modifier,
			readerScripting: scripting,
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
		let liveness = FakeReaderLiveness(isRunning: true)
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

	@Test("the refusal tells the AGENT what to do, and names BOTH ways out")
	func theRefusalIsAddressedToTheAgent() {
		// The audience is not the person at the machine -- nobody may be there. And
		// since 13.26 there are TWO grants that would each be enough on their own,
		// so a refusal naming one of them would send a human to grant the wrong
		// thing.
		let (setup, _, _) = machine(
			permissions: FakePermissionBroker(state: .notGranted),
			scripting: FakeReaderScriptingSetting(setting: .disabled))
		let message = failure { try setup.establish() }
		#expect(message?.contains("ask the human at this machine") == true)
		#expect(message?.contains("connect again") == true)
		#expect(message?.contains("Accessibility") == true)
		#expect(message?.contains("AppleScript") == true)
		// And it says which route to prefer, and why -- the reason is the person's
		// own security rather than this bridge's convenience.
		#expect(message?.contains("closed to every other") == true)
	}

	@Test("`cannotTell` is not read as a NO, and says which read was inconclusive")
	func anUnreadableGrantStopsIt() {
		// Reporting it as `notGranted` would send a human to System Settings to fix
		// a grant they already hold, which is the false negative 13.11 removed --
		// and it matters more now, since the channel that answers the automation
		// grant is exactly the one 13.26 expects to be switched off.
		let (setup, _, _) = machine(
			permissions: FakePermissionBroker(state: .cannotTell),
			scripting: FakeReaderScriptingSetting(setting: .disabled))
		let message = failure { try setup.establish() }
		#expect(message?.contains("could not determine") == true)
	}

	// -- rung 1 as a ROUTE check, which is 13.26 --------------------------------

	@Test("ACCESSIBILITY ALONE IS ENOUGH: no AppleScript, no Automation, and a session")
	func keysAloneEstablish() throws {
		// The entry's whole point. "Allow VoiceOver to be controlled with
		// AppleScript" lets any process drive a blind person's screen reader, so a
		// bridge that required it to be on would be asking them to hold a door open
		// for everyone. A machine with Accessibility and nothing else can be driven
		// by keys, which is what a person uses.
		let permissions = FakePermissionBroker(state: .granted)
		permissions.states[.automationVoiceOver] = .notGranted
		let (setup, _, _) = machine(
			permissions: permissions,
			scripting: FakeReaderScriptingSetting(setting: .disabled))
		try setup.establish()
		#expect(permissions.requests.isEmpty)
	}

	@Test("THE COMMAND-NAME ROUTE ALONE IS ENOUGH TOO, which is the old machine")
	func commandNamesAloneEstablish() throws {
		// A machine that has never granted Accessibility, with the switch on: it
		// cannot press a key and it can dispatch the reader's own commands, and
		// that is a session. Nothing about this entry takes that away.
		let permissions = FakePermissionBroker(state: .granted)
		permissions.states[.accessibility] = .notGranted
		let (setup, _, _) = machine(permissions: permissions)
		try setup.establish()
		#expect(permissions.requests.isEmpty)
	}

	@Test("the AppleScript SWITCH being off removes that route even with the grant")
	func theSwitchIsPartOfTheRoute() {
		// The grant and the switch are two different things and both are needed for
		// the command-name route: `kTCCServiceAppleEvents` says this process may
		// send events to VoiceOver, and the switch says VoiceOver will act on them.
		let permissions = FakePermissionBroker(state: .granted)
		permissions.states[.accessibility] = .notGranted
		let (setup, _, _) = machine(
			permissions: permissions,
			scripting: FakeReaderScriptingSetting(setting: .disabled))
		#expect(failure { try setup.establish() } != nil)
	}

	@Test("each grant is read ONCE, and neither is ever requested")
	func eachGrantIsReadOnce() throws {
		// The routes are computed at rung 1 and carried to rung 5 rather than being
		// asked for again, so a handshake cannot read a permission twice and get two
		// answers -- and so "nothing here requests anything" stays checkable.
		let permissions = FakePermissionBroker()
		let (setup, _, _) = machine(permissions: permissions)
		try setup.establish()
		#expect(permissions.statusReads == Permission.allCases)
		#expect(permissions.requests.isEmpty)
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
		// `describe item in voiceover cursor` describes what the cursor is on and
		// MOVES NOTHING. A probe that navigated would make every connect a small
		// invisible edit to where the person was standing.
		let gestures = FakeGestureSender()
		let (setup, _, speech) = machine(gestures: gestures)
		try setup.establish()
		#expect(gestures.pressed == ["speak the time and date"])
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
