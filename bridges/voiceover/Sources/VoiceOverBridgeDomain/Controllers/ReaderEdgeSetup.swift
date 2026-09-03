// ROLE: controller -- the handshake's own setup. It PREPARES the reader rather
// than inspecting it, and fails by named rung where it cannot.
//
// HOLDS: the AdapterSet built by the factory moments ago (the permission broker,
// the reader liveness, the provider lifecycle, the gesture sender and the
// silence control), the SessionContext, and this session's SpeechBuffer.
// BUILT BY: the Hello handler, once per session. CALLED BY: nothing else.
//
// BUILT BY A CONTROLLER RATHER THAN BY WIRING, and that is a deliberate layout
// decision with the same why the SpeechBuffer has: its collaborators DO NOT
// EXIST until `hello` has read the capture mode and the AdapterFactory has built
// the reader edge from it. A composition root cannot hand over what it cannot
// yet construct, which is the whole argument the factory itself rests on.
//
// ============================================================================
// WHY IT EXISTS -- AND IT COST AN HOUR OF A LIVE CHECKLIST TO LEARN (spec 0050)
// ============================================================================
//
// `poe build` deletes and reassembles the bundle, so the system forgets the
// extension. Every session afterwards answered `speech: []`, which is
// indistinguishable from "the reader said nothing" -- the one answer
// ReaderCondition's header says a bridge on this route must never give. And the
// bridge KNEW: the launcher printed `providerNotRunning` at startup and the
// handshake established the session anyway.
//
// Nothing in that state needed a human. Registering is two subprocesses,
// selecting the voice has been the bridge's job since 13.6, and starting the
// reader is one more. What was missing was a decision about who does it.
//
// FIVE RUNGS, ALL EAGER, IN ORDER -- see SetupRung, which owns the vocabulary
// and composes every failure sentence:
//
//   1. permissions   -- READ, never asked for; and it wants ONE ROUTE, not every
//                       grant (13.26)
//   2. readerRunning -- ask, activate, ask again
//   3. registration  -- lsregister then pluginkit, only when unregistered, then a
//                       RESTART: only a restart publishes a newly registered
//                       voice, which is the rung 13.20 could not climb
//   4. voiceSelection-- record the user's voice, then write ours
//   5. captureProof  -- make the reader speak and require it to arrive
//
// AND 13.26 CHANGED WHAT A RUNG IS. 13.20 turned reporting into climbing; spec
// 0053 §3.1 turns climbing into PREPARING -- these are things made true, not
// checks that may fail, and two of them now WRITE to somebody's machine.
//
// THE HANDSHAKE NEVER CALLS `PermissionBroker.request`, and that is what keeps
// 13.8's lever intact word for word. `request` still has exactly TWO callers in
// this repository, both command handlers about to post a system event, both
// through AccessibilityGrant -- so "a session that presses only the reader's
// COMMAND NAMES and reads speech never triggers an Accessibility request" is
// unchanged. Reading a grant shows no dialog; asking for one raises a modal
// somebody may not be there to answer, and a handshake that waits on that is a
// handshake that hangs.
//
// IT IS FATAL IN BOTH MODES, which is NOT the asymmetry 13.6 drew. 13.6's rule
// is about a promise concerning a human's EARS, which only `silent` makes, and
// it stands. This is about a different promise: that `getSpeech` means anything
// at all -- and a live session announces the `speech` capability exactly as
// loudly. The old "a live session may become healthy while it runs" was a
// reasonable thing to say about a state nobody was repairing, and an
// unreasonable one about a state this handshake has just tried to repair and
// failed. See spec 0050 §2.7.
//
// ============================================================================
// IT MAY RESTART THE READER NOW, AND THAT REVERSES A RULE MARKED DECIDED.
// ============================================================================
//
// 13.20's sentence was *"no handshake in this bridge may decide on a restart --
// it takes the reader away from somebody who is using it."* Marlon reversed it on
// 2026-09-02: *"restarting vo is not a problem for capturing as a bridge
// handshake, if needed."* Spec 0053 §3.2. The bounds are what make it safe:
//
//   * ONLY FOR A NAMED REASON -- today, exactly one: a capture voice the system
//     has just been told about, which macOS publishes only after the reader
//     restarts. Never speculatively, and never as a way past a failure it cannot
//     explain.
//   * ANNOUNCED FIRST, through the bridge's own synthesizer, which is audible
//     even in a silent session because it goes around the reader entirely.
//   * QUIT, WAIT FOR THE PROCESS TO BE GONE, THEN OPEN. `killall` alone does not
//     bring the reader back and the `&&` one-liner races -- see `ReaderRestart`,
//     which carries both measurements.
//
// It also unblocks the one rung 13.20 could not climb: a newly registered capture
// voice is published only after a reader restart, so what used to be a failure
// naming a command for a human is now a step this handshake can take.
//
// WHAT IT STILL MUST NEVER DO: deregister anything (see ProviderLifecycle), or
// ask a human for a grant. SESSION state is restored at teardown -- the voice,
// then the modifier -- and MACHINE state is not.
//
// AND EVERYTHING IT CHANGES GOES IN THE JOURNAL, which is the 2026-09-02 field
// report's ask: a handshake that failed left the capture voice selected, nothing
// could say so, and the hand recovery that followed destroyed the person's pitch,
// rate and volume. See `ChangeJournal`.

import ScreenReaderWire

public struct ReaderEdgeSetup {
	/// How long the capture proof waits for an utterance to arrive.
	///
	/// Wide on purpose: three processes stand between the reader and this buffer,
	/// and `FileLineTailer` polls the feed every 50 ms, so the floor is the
	/// pipe's and not ours. A wait that was too tight would report a healthy
	/// machine as broken, which is the failure this whole entry exists to remove
	/// rather than to reintroduce from the other side.
	public static let captureProofSeconds: Double = 5.0

	/// How long rung 2 waits for a reader it has just activated.
	///
	/// `open` hands the launch to the system and returns, so an immediate
	/// re-check would fail on a reader that is coming up. Same shape as the
	/// registration poll, same reason.
	public static let readerActivationSeconds: Double = 5.0

	/// How often the two polling rungs re-ask. Injected clock, so a test pays
	/// none of it.
	static let pollInterval: Double = 0.25

	/// The command the capture proof performs, whichever route it takes.
	///
	/// IT MOVES NOTHING AND IT ALWAYS SPEAKS, which are the two properties a probe
	/// needs and which the previous one only half had. `describe item in voiceover
	/// cursor` moves nothing either, but what it says depends on where the cursor
	/// happens to be -- and a rung whose evidence is "the reader said something
	/// about whatever you were standing on" is a rung that can be starved by an
	/// element with a thin description. The time and date is always there, always
	/// spoken, and belongs to no application.
	///
	/// CHOSEN BY MARLON, 2026-09-02, over `go to dock`, which is also guaranteed to
	/// speak and which MOVES the VoiceOver cursor: a connect that quietly walked
	/// somebody's cursor to the dock would be a small invisible edit to where they
	/// were standing, every time.
	public static let captureProbeCommand = "speak the time and date"

	/// The same command as a KEYSTROKE, for a machine with no AppleScript control
	/// -- 13.26.
	///
	/// Read off the reader's own factory configuration
	/// (`scripts/voiceover_default_bindings.py`), not recalled, and measured to
	/// reach the reader as a synthesized event on 2026-09-02.
	///
	/// WHAT THIS RUNG MUST NOT DO IS ASSERT ON *WHICH* ANSWER COMES BACK. `vo+f7`
	/// is three commands -- the time and date, the battery status, the wifi status
	/// -- and the reader picks between them with a RING that each press advances
	/// and only a different key resets (see the guidance document). So a healthy
	/// machine can answer this probe with a battery percentage, and that is a pass:
	/// the rung's question is whether an utterance ARRIVED, never what it said.
	public static let captureProbeKeystroke = "vo+f7"

	private let adapters: AdapterSet
	private let context: SessionContext
	private let speech: SpeechBuffer

	public init(adapters: AdapterSet, context: SessionContext, speech: SpeechBuffer) {
		self.adapters = adapters
		self.context = context
		self.speech = speech
	}

	/// Climb the ladder, or throw the rung that stopped it.
	///
	/// Every failure is a `CommandError` because this is the controllers layer
	/// and the agent must read ONE vocabulary of failure rather than two --
	/// exactly what the Hello handler already does for `AdapterFactoryError`.
	public func establish() throws {
		let routes = try confirmPermissions()
		try confirmReaderIsRunning()
		try registerProvider()
		try selectCaptureVoice()
		try openSilenceChannel()
		try proveCapture(over: routes)
	}

	/// Which ways this machine offers of making the reader do something -- 13.26.
	///
	/// COMPUTED ONCE, AT RUNG 1, AND CARRIED. Rung 5 chooses its probe route from
	/// this rather than asking the machine again, so one handshake cannot read a
	/// permission twice and get two answers -- and so a test can assert that each
	/// grant is read exactly once, which is how "nothing here requests anything"
	/// stays checkable.
	struct Routes {
		/// Accessibility is granted AND `vo` resolves on this machine, so the
		/// reader's own commands can be PRESSED. Spec 0052's route.
		///
		/// THE SECOND HALF IS NOT PEDANTRY, AND IT WAS MEASURED. On a machine whose
		/// VoiceOver modifier is bound to Caps Lock alone, a synthesized Caps Lock
		/// is invisible to the reader: measured 2026-09-02 on the maintainer's
		/// machine, with him listening -- `caps+d` sent as a real flag transition,
		/// held 150 ms, produced no "dock" and typed a `d` into the text editor that
		/// had focus. So Accessibility alone does not mean the reader can be driven;
		/// it means keys can be pressed AT something, which is a different claim.
		let keys: Bool
		/// The AppleEvents grant AND VoiceOver's own AppleScript switch, so the
		/// reader's own command names can be dispatched.
		let commandNames: Bool
		/// What the person has bound `vo` to, read once at rung 1 and carried, so
		/// rung 1 and the probe cannot read the machine twice and get two answers.
		let modifier: ModifierSetting
	}

	// -- rung 1: permissions ---------------------------------------------------

	/// READ what this machine allows, and require ONE WORKABLE ROUTE to the reader
	/// -- not every permission. Nothing is requested, and nothing here can request
	/// anything.
	///
	/// ============================================================================
	/// IT USED TO DEMAND BOTH GRANTS, AND 13.26 IS WHY THAT WAS WRONG.
	/// ============================================================================
	///
	/// The old rule looped over `Permission.allCases` and refused a session unless
	/// every one was granted, on the reasoning that "a permission a session cannot
	/// work without" is what the enum holds. That reasoning was sound and the
	/// premise had stopped being true: since 13.25 this reader can be driven
	/// entirely by KEYSTROKES, which need Accessibility and no AppleEvents at all.
	///
	/// And the requirement behind 13.26 is not convenience. "Allow VoiceOver to be
	/// controlled with AppleScript" lets ANY process drive the screen reader a blind
	/// person depends on; a bridge that makes them leave it on in order to be tested
	/// is asking them to hold a door open for everyone. So the question this rung
	/// asks is the honest one: IS THERE A WAY TO DRIVE THIS READER AT ALL?
	///
	///   * Accessibility granted        -> keys. The route 13.25 recommends.
	///   * Automation granted AND the
	///     AppleScript switch on        -> the reader's own command names.
	///
	/// Neither, and the session is refused HERE, before anything is touched, naming
	/// BOTH fixes -- because an agent told about only one of them will send a human
	/// to grant the wrong thing.
	///
	/// A `cannotTell` on the automation grant is NOT a route. It is read through a
	/// channel that may itself be off, which is exactly the state this entry
	/// expects to be ordinary now, and a route this bridge is unsure of is not one
	/// it may build a handshake on.
	private func confirmPermissions() throws -> Routes {
		let accessibility = adapters.permissions.status(of: .accessibility)
		let automation = adapters.permissions.status(of: .automationVoiceOver)
		let scripting = adapters.readerScripting.scripting()
		// `vo` has to RESOLVE for the key route to reach the reader -- see `Routes`.
		//
		// PRESSABLE NOW, and 13.26 tried to widen this and had to put it back. The
		// entry briefly asked only that the modifier be READABLE, on the reasoning
		// that a Caps-Lock machine could be repaired: write Control-Option, restart,
		// write the person's own choice straight back. THE LIVE RUN KILLED IT --
		// writing that key under a running reader makes VoiceOver put a modal
		// question on screen asking the person whether they wanted Control-Option,
		// which blocks the reader from quitting and changes a setting nobody chose
		// (measured 2026-09-02). So the question is the narrow one again: can this
		// bridge press `vo` as the machine stands?
		let modifier = adapters.readerModifier.modifier()
		let modifierPressable = modifier == .controlOption || modifier == .controlOptionOrCapsLock
		let routes = Routes(
			keys: accessibility == .granted && modifierPressable,
			commandNames: automation == .granted && scripting == .enabled,
			modifier: modifier)
		context.transcript.note(
			"setup: routes -- keys \(routes.keys ? "yes" : "no"), "
				+ "command names \(routes.commandNames ? "yes" : "no"), "
				+ "vo is \(modifier.rawValue)")
		guard !routes.keys, !routes.commandNames else { return routes }
		throw CommandError(
			SetupRung.permissions.failed(
				"this bridge has no way to drive VoiceOver on this machine, and it needs only ONE of "
					+ "the two. Pressing the reader's own commands as KEYS needs the Accessibility "
					+ "grant, which is \(described(accessibility)), AND a VoiceOver modifier this "
					+ "bridge can synthesize -- it is set to \(modifier.rawValue) here, and a "
					+ "synthesized Caps Lock is invisible to the reader (measured 2026-09-02). Sending "
					+ "the reader's own COMMAND NAMES needs the AppleEvents grant, which is "
					+ "\(described(automation)), together with VoiceOver's own AppleScript switch, "
					+ "which is \(scripting.rawValue).",
				agentMustDo:
					"ask the human at this machine for EITHER: Accessibility, under System Settings > "
					+ "Privacy & Security > Accessibility -- which is the route to prefer, since it is "
					+ "what a person's own keystrokes use and it leaves VoiceOver closed to every other "
					+ "process on the machine, and with the VoiceOver modifier set to Control-Option "
					+ "under VoiceOver Utility > Commands -- OR VoiceOver Utility > General > \"Allow "
					+ "VoiceOver to be controlled with AppleScript\" together with the Automation "
					+ "grant. Then "
					+ "connect again. This bridge does not raise a consent dialog itself: a handshake "
					+ "that waited for a modal nobody may be looking at is a handshake that hangs."
			))
	}

	/// One permission state, in words, keeping `cannotTell` distinguishable.
	///
	/// A READ THAT DID NOT COME BACK IS NOT A "NO", and it must not read as one:
	/// the automation grant is answered through a channel that may itself be off,
	/// which is the ordinary state this entry expects now. An agent told "the grant
	/// is missing" would send a human to a settings pane that may already be right.
	private func described(_ state: PermissionState) -> String {
		switch state {
		case .granted: return "granted"
		case .notGranted: return "not granted"
		case .cannotTell:
			return "one this bridge could not determine -- the channel that answers it did not "
				+ "reply, which is not itself a permission failure"
		}
	}

	// -- rung 2: a reader to talk to -------------------------------------------

	/// Ask, activate, ask again -- and never restart.
	private func confirmReaderIsRunning() throws {
		guard !adapters.readerLiveness.readerIsRunning() else { return }
		context.transcript.note("setup: VoiceOver did not answer; starting it")
		adapters.readerLiveness.activate()
		if waitUntil(
			seconds: Self.readerActivationSeconds, adapters.readerLiveness.readerIsRunning)
		{
			return
		}
		throw CommandError(
			SetupRung.readerRunning.failed(
				ReaderCondition.readerNotRunning.described,
				agentMustDo:
					"tell the human at this machine that VoiceOver would not start, and connect again "
					+ "once it is running. It may be waiting on a dialog only somebody at the screen "
					+ "can see."
			))
	}

	// -- rung 3: registration, which is machine state --------------------------

	/// Register the extension when the system has forgotten it, and never undo it.
	///
	/// ONLY FROM `notRegistered`. Re-registering something already registered
	/// publishes nothing new and costs two subprocesses and a poll, so the
	/// ordinary handshake pays one cheap read here.
	private func registerProvider() throws {
		guard adapters.providerLifecycle.state() == .notRegistered else { return }
		context.transcript.note("setup: the capture voice is not registered; registering it")
		do {
			try adapters.providerLifecycle.register()
		} catch {
			throw CommandError(
				SetupRung.registration.failed(
					describe(error),
					agentMustDo:
						"ask the human at this machine to run the two commands named above by hand, then "
						+ "connect again."
				))
		}
		context.transcript.note("setup: registered -- \(adapters.providerLifecycle.state().rawValue)")
		try publishTheVoice()
	}

	/// Make the system PUBLISH the voice it has just been told about -- 13.26, and
	/// this is the rung 13.20 could not climb.
	///
	/// ============================================================================
	/// ONLY A READER RESTART PUBLISHES A NEWLY REGISTERED VOICE.
	/// ============================================================================
	///
	/// That is a macOS fact, not a bridge limitation, and it is why 13.20's rung 3
	/// could succeed while rung 5 failed: the extension was registered, the system
	/// knew about it, and VoiceOver went on offering the list of voices it had read
	/// at startup. 13.20 could only NAME the restart and ask a human to run it,
	/// because no handshake was allowed to take a screen reader away.
	///
	/// It is allowed now (spec 0053 §3.2), and this is one of exactly two named
	/// reasons in the bridge. IT IS REACHED ONLY FROM `notRegistered`: an ordinary
	/// handshake on a healthy machine does not enter `registerProvider` at all, so
	/// it never restarts anything. What triggers it in practice is `poe build`,
	/// which begins `rm -rf build` and makes the system forget the extension -- so
	/// the developer who has just rebuilt pays one restart, and the blind person
	/// who has not rebuilt anything pays none.
	///
	/// A RESTART THAT FAILS IS NOT FATAL *HERE*, which is the difference from the
	/// modifier rung. There, the restart is the only thing that puts the reader on
	/// keys this bridge can press, so failing it fails the rung. Here the reader may
	/// have published the voice anyway, or may not have needed to, and this rung
	/// cannot tell. So the failure is written down and the climb goes on to the
	/// rungs that CAN tell.
	///
	/// AND ONE OF THEM WILL, WHICH IS THE POINT OF NOT FAILING HERE. If the voice is
	/// genuinely still unpublished, rung 4 refuses to select it and says so by name;
	/// if it selects and nothing is captured, rung 6 says so with evidence. Either
	/// way the session is refused by the rung that actually knows, with a recovery
	/// that fits -- rather than by this one, guessing.
	private func publishTheVoice() throws {
		guard adapters.providerLifecycle.state() < .published else {
			context.transcript.note("setup: the capture voice is already published")
			return
		}

		// ============================================================================
		// PUBLISH FIRST, RESTART SECOND -- AND GETTING THAT BACKWARDS COST 13.26 ITS
		// FIRST LIVE CONNECT.
		// ============================================================================
		//
		// A registered provider's voices do not appear because it registered:
		// something has to ask the system to re-read them. Nothing here was asking,
		// so the first live run registered the extension, restarted VoiceOver to
		// publish the voice, and the voice had never been published at all -- the
		// reader came back up with a voice list that still did not contain it, and
		// the climb failed at `voiceSelection` one rung later. Measured 2026-09-02,
		// transcript 22:31:35-37, and the fix is an ORDER rather than a new step.
		//
		// So: ask the system, wait until the voice is really there, and only then
		// spend somebody's screen reader on a restart. A restart taken before the
		// voice exists is a restart taken for nothing.
		do {
			try adapters.providerLifecycle.publish()
			context.transcript.note("setup: the system now offers the capture voice")
		} catch {
			throw CommandError(
				SetupRung.registration.failed(
					describe(error),
					agentMustDo:
						"tell the human at this machine what the message above says, and connect again. "
						+ "The extension is registered; what has not happened is the system offering its "
						+ "voice, which it does on its own schedule."
				))
		}

		warn(
			"The screen reader bridge has just registered its capture voice with the system, and "
				+ "macOS only offers a newly registered voice after VoiceOver restarts. It is restarting "
				+ "VoiceOver now. VoiceOver will be back in a moment.")
		do {
			try adapters.readerRestart.restart()
			context.transcript.note(
				"setup: restarted the reader to publish the capture voice -- "
					+ "\(adapters.providerLifecycle.state().rawValue)")
		} catch let failure as ReaderRestartError {
			// NOT FATAL. See above: the capture proof is the rung that knows.
			context.transcript.note(
				"setup: the reader could not be restarted to publish the capture voice, and the "
					+ "capture proof will say whether that mattered: \(failure.description)")
		}
	}

	// -- rung 4: the voice -----------------------------------------------------

	/// Record what the user had, then point the reader at ours.
	///
	/// THE ORDER IS LOAD-BEARING AND UNCHANGED FROM 13.6. The user's own voice is
	/// read and recorded BEFORE ours is written, so every teardown path holds
	/// what to put back even if a later rung throws -- and it is recorded only
	/// when it is NOT ours, because a previous session that died without
	/// restoring leaves our own voice looking like the user's, and restoring that
	/// would hand the extension itself as its own pass-through voice.
	private func selectCaptureVoice() throws {
		let previous = adapters.providerLifecycle.selectedVoice()
		if let previous, !previous.isCaptureVoice {
			context.previousVoice = previous.identifier
		}
		guard previous?.isCaptureVoice != true else { return }
		do {
			try adapters.providerLifecycle.selectCaptureVoice()
			// RECORDED AFTER IT SUCCEEDED, so the journal never claims a change that
			// did not happen -- and recorded AT ALL because this is the one change
			// with no expiry: a session that dies here leaves the reader on a voice
			// that renders nothing, and the next reader restart finds it unpublished,
			// falls back to the system default AND PERSISTS THE FALLBACK, destroying
			// the record of the person's own voice (13.23). The 2026-09-02 field
			// report is that failure with a human recovering it by hand, and the hand
			// recovery cost them their pitch, rate and volume.
			adapters.changeJournal.changed(Self.voiceChange(was: context.previousVoice))
		} catch {
			throw CommandError(
				SetupRung.voiceSelection.failed(
					describe(error),
					agentMustDo:
						"tell the human at this machine what the message above says, and connect again "
						+ "once they have done it. Nothing further is in this bridge's hands: it has "
						+ "already registered the extension and tried to write the preference."
				))
		}
	}

	/// Say something to the human, and never let it stop anything.
	///
	/// GUARDED FOR THE REASON EVERY CUE IN THIS BRIDGE IS: a courtesy is never worth
	/// a session, and the announcer reaches an audio device that may be gone. Its
	/// one caller is the restart, which spec 0053 §3.2 requires to be ANNOUNCED --
	/// through the bridge's own synthesizer, which is audible even in a silent
	/// session because it goes around the reader entirely, so nobody is dropped into
	/// silence unwarned.
	private func warn(_ text: String) {
		do {
			try adapters.announcer.announce(text)
			context.transcript.announced(text)
			context.humanHeard()
		} catch {
			context.transcript.note("setup: the human could not be warned: \(describe(error))")
		}
	}

	// -- what the journal records ----------------------------------------------

	/// The three change descriptions, composed in ONE place so the entries a
	/// session opens and the entries it closes cannot describe the same setting
	/// differently -- which would leave a repair tool with an open change forever.
	static func voiceChange(was previous: String?) -> ReaderChange {
		ReaderChange(
			kind: .voice,
			store: "com.apple.SpeakSelection / VoiceOverDefaultVoiceSelections / voiceId",
			was: previous,
			now: "the screen-readers-mcp capture voice")
	}

	// -- the marker channel ----------------------------------------------------

	/// Open the channel the capture voice reads, and suppress if asked.
	///
	/// NOT A RUNG, and it sits here rather than in `Hello` because it has to
	/// happen BETWEEN rungs 4 and 5: the proof must be inaudible in a silent
	/// session, and it is only inaudible once the marker says so.
	///
	/// OPEN IN BOTH MODES: it carries the user's own voice so pass-through is
	/// acoustically invisible (Rule 0), and it is a LEASE the session renews -- a
	/// bridge that dies un-mutes the machine by doing nothing at all.
	private func openSilenceChannel() throws {
		try adapters.silenceControl.begin(preferredVoice: context.previousVoice)
		guard adapters.mode == .silent else { return }
		try adapters.silenceControl.suppress()
		context.transcript.note("silence: suppressing, on a lease the session renews")
	}

	// -- rung 5: the only rung that is evidence --------------------------------

	/// Make the reader speak, and require the utterance to arrive here.
	///
	/// THE BOOKMARK IS TAKEN BEFORE THE PRESS, so speech that was already in
	/// flight cannot be mistaken for evidence of a probe that never landed.
	///
	/// `ProviderState.capturing` is documented as provable by nothing but an
	/// utterance arriving, and this is the first thing in the bridge that
	/// supplies that evidence rather than inferring around it. The promotion goes
	/// through the entity's own pure rule so there is one definition of it.
	private func proveCapture(over routes: Routes) throws {
		let bookmark = speech.nextIndex()
		try speakTheProbe(over: routes)
		let heard = !speech.collectSince(bookmark, grace: Self.captureProofSeconds).entries.isEmpty
		let reached = adapters.providerLifecycle.state().observing(captured: heard)
		guard reached == .capturing else {
			let named = reached.unheardConditions.map(\.described).joined(separator: " ")
			context.transcript.note("setup: nothing was captured -- \(reached.diagnosis)")
			throw CommandError(
				SetupRung.captureProof.failed(
					"the reader was asked to speak the time and date and nothing reached this "
						+ "bridge within \(Int(Self.captureProofSeconds)) seconds. \(reached.diagnosis). "
						+ named,
					agentMustDo:
						"ask the human at this machine to restart the reader -- \(readerRestartCommand) "
						+ "-- and then connect again. That is the one step this bridge may not take on "
						+ "somebody's behalf, and it is what publishes a newly registered voice."
				))
		}
		context.transcript.note("setup: capturing -- the reader's speech reaches this bridge")
	}

	/// Make the reader speak, by whichever route this machine offers -- 13.26.
	///
	/// ============================================================================
	/// THE COMMAND NAME IS TRIED FIRST, AND THAT IS THE OPPOSITE OF 13.25's RULE.
	/// ============================================================================
	///
	/// Spec 0052 made the KEYSTROKE the route for driving, because a keystroke
	/// passes the application under test and a command name does not -- which is
	/// the whole fidelity argument. None of that applies here: a probe is not a
	/// user act, it is testing nothing in front of the person, and the cheapest,
	/// least invasive route wins. A command name costs no grant and sends no key
	/// event into whatever window the person is sitting in.
	///
	/// So: the command name where the machine offers it, the key where it does not,
	/// and a named failure where it offers neither -- which rung 1 has already
	/// refused, so reaching the third case here means the machine changed under us
	/// mid-handshake.
	///
	/// THE KEY ROUTE NEEDS `vo` RESOLVED, and on a Caps-Lock machine it cannot be
	/// (spec 0052 §3.3). That failure is reported as itself rather than as "nothing
	/// was captured": a bridge that could not press the probe never learned
	/// anything about capture.
	private func speakTheProbe(over routes: Routes) throws {
		if routes.commandNames {
			do {
				try adapters.gestureSender.press(Self.captureProbeCommand)
				context.transcript.note("setup: probe sent as a command name")
				return
			} catch {
				throw CommandError(
					SetupRung.captureProof.failed(
						"the reader would not take '\(Self.captureProbeCommand)', which this bridge sends "
							+ "to prove it can hear the reader at all: \(describe(error))",
						agentMustDo:
							"tell the human at this machine what that says, and connect again. If VoiceOver "
							+ "has only just started, giving it a moment and reconnecting is often enough."
					))
			}
		}
		do {
			let gesture = try CommandVocabulary.classify(
				Self.captureProbeKeystroke, readerModifier: adapters.readerModifier.modifier())
			guard case .keystroke(let keystroke) = gesture else {
				throw CommandError("the capture probe keystroke is not a keystroke")
			}
			try adapters.keyPresser.press(keystroke)
			context.transcript.note("setup: probe pressed as a key -- \(gesture.described)")
		} catch let refusal as GestureIdRefused {
			throw CommandError(
				SetupRung.captureProof.failed(
					"this machine offers no AppleScript control of VoiceOver, so the probe has to be "
						+ "PRESSED -- and it cannot be: \(refusal.reason)",
					agentMustDo:
						"tell the human at this machine that either VoiceOver's modifier has to be "
						+ "Control-Option (VoiceOver Utility > Commands) or AppleScript control has to "
						+ "be switched on (VoiceOver Utility > General), and connect again."
				))
		} catch let failure as KeyPressFailure {
			throw CommandError(
				SetupRung.captureProof.failed(
					"the probe could not be pressed on this machine: \(failure.description)",
					agentMustDo:
						"tell the human at this machine what that says, and connect again."
				))
		}
	}

	// -- shared ---------------------------------------------------------------

	/// Poll `condition` until it holds, or until `seconds` have passed.
	///
	/// Checked immediately first, and the clock is INJECTED, so a five-second
	/// wait costs microseconds in a test and real seconds on a real machine.
	private func waitUntil(seconds: Double, _ condition: () -> Bool) -> Bool {
		let deadline = context.clock.monotonic() + seconds
		while true {
			if condition() { return true }
			guard context.clock.monotonic() < deadline else { return false }
			context.clock.sleep(Self.pollInterval)
		}
	}

	/// A port's error in the words it chose for itself.
	///
	/// `ProviderError` and `GestureError` both carry a sentence written for this
	/// audience; anything else is described rather than guessed at, because a
	/// failure nobody anticipated is still worth reporting as itself.
	private func describe(_ error: any Error) -> String {
		switch error {
		case let failure as ProviderError: return failure.description
		case let failure as GestureError: return failure.description
		default: return String(describing: error)
		}
	}
}
