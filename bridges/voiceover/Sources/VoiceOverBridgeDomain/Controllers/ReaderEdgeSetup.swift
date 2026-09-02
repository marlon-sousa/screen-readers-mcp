// ROLE: controller -- the handshake's own setup. It CLIMBS the ProviderState
// ladder instead of reporting where it stopped, and fails by name at the one
// rung it cannot climb.
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
//   1. permissions   -- READ, never asked for
//   2. readerRunning -- ask, activate, ask again
//   3. registration  -- lsregister then pluginkit, only when unregistered
//   4. voiceSelection-- record the user's voice, then write ours
//   5. captureProof  -- make the reader speak and require it to arrive
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
// WHAT IT MUST NEVER DO: restart the reader (see ReaderLiveness.activate),
// deregister anything (see ProviderLifecycle), or ask a human for a grant.
// SESSION state is restored at teardown; MACHINE state is not.

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

	/// The command the capture proof presses.
	///
	/// THE SAFE PROBE, and the guidance document already calls it that: it
	/// describes what the VoiceOver cursor is on and MOVES NOTHING. A probe that
	/// navigated would make every `connect_reader` a small invisible edit to
	/// where the person was standing.
	public static let captureProbeCommand = "describe item in voiceover cursor"

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
		try confirmPermissions()
		try confirmReaderIsRunning()
		try registerProvider()
		try selectCaptureVoice()
		try openSilenceChannel()
		try proveCapture()
	}

	// -- rung 1: permissions ---------------------------------------------------

	/// READ both grants. Neither is requested, and nothing here can request one.
	///
	/// EVERY CASE, rather than two named reads: a permission added to the enum
	/// later is one a session cannot work without either, and a loop is what
	/// makes that true by construction instead of by somebody remembering.
	private func confirmPermissions() throws {
		for permission in Permission.allCases {
			let state = adapters.permissions.status(of: permission)
			guard state != .granted else { continue }
			let because =
				state == .cannotTell
				? "this bridge could not determine whether it holds it: the channel that answers it did "
					+ "not reply, which is not itself a permission failure -- VoiceOver may not be "
					+ "running. \(permission.described)"
				: permission.described
			context.transcript.note("setup: \(permission.rawValue) is \(state.rawValue)")
			throw CommandError(
				SetupRung.permissions.failed(
					because,
					agentMustDo:
						"ask the human at this machine to grant it, then connect again. This bridge does "
						+ "not raise the consent dialog itself: a handshake that waited for a modal "
						+ "nobody may be looking at is a handshake that hangs."
				))
		}
	}

	// -- rung 2: a reader to talk to -------------------------------------------

	/// Ask, activate, ask again -- and never restart.
	private func confirmReaderIsRunning() throws {
		guard !adapters.readerLiveness.readerAnswersItsOwnName() else { return }
		context.transcript.note("setup: VoiceOver did not answer; starting it")
		adapters.readerLiveness.activate()
		if waitUntil(
			seconds: Self.readerActivationSeconds, adapters.readerLiveness.readerAnswersItsOwnName)
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
	private func proveCapture() throws {
		let bookmark = speech.nextIndex()
		do {
			try adapters.gestureSender.press(Self.captureProbeCommand)
		} catch {
			throw CommandError(
				SetupRung.captureProof.failed(
					"the reader would not take '\(Self.captureProbeCommand)', which this bridge presses "
						+ "to prove it can hear the reader at all: \(describe(error))",
					agentMustDo:
						"tell the human at this machine what that says, and connect again. If VoiceOver "
						+ "has only just started, giving it a moment and reconnecting is often enough."
				))
		}
		let heard = !speech.collectSince(bookmark, grace: Self.captureProofSeconds).entries.isEmpty
		let reached = adapters.providerLifecycle.state().observing(captured: heard)
		guard reached == .capturing else {
			let named = reached.unheardConditions.map(\.described).joined(separator: " ")
			context.transcript.note("setup: nothing was captured -- \(reached.diagnosis)")
			throw CommandError(
				SetupRung.captureProof.failed(
					"the reader was asked to describe what its cursor is on and nothing reached this "
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
