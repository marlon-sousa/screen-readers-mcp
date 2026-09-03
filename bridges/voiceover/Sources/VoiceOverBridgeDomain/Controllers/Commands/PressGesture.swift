// ROLE: controller -- `pressGesture`: press the given gestures in order, then
// report what the reader said.
//
// BUILT BY: Registry. DRIVES: the CommandVocabulary entity (what may be sent at
// all), the KeyPresser port (the keystroke), the PermissionBroker port (the grant
// a keystroke costs), the session's SpeechBuffer (the grace window), and -- only
// on a failure -- the ReaderLiveness port, which names the condition a press
// cannot report for itself.
//
// ============================================================================
// ONE COMMAND, ONE ROUTE -- 13.31. IT HAD TWO UNTIL THIS ENTRY.
// ============================================================================
//
// A gesture id is a keystroke, and nothing else:
//
//   press_gesture { gestures: ["vo+m"] }        -> the menu bar, the way a person
//   press_gesture { gestures: ["command+l"] }      reaches either of them
//
// The second route was VoiceOver's own English command names, dispatched inside
// the reader over an AppleEvent. It is deleted, and the argument is one sentence:
// NO VOICEOVER USER CAN TYPE A COMMAND NAME. A person presses the key; for an act
// with no key they open the Commands menu, type the name and press Enter, which is
// this command plus `typeText`. A route no human has is a route that cannot find
// the defects a human hits -- 13.25 measured exactly that, a dispatch reporting
// success on chords a real user was stuck on -- and it was bought by asking a
// blind person to leave "Allow VoiceOver to be controlled with AppleScript" on,
// which lets any process on the machine drive their screen reader. Spec 0055.
//
// WHAT THAT COSTS AN AGENT IS ONE REFUSAL IT MUST NOT MISREAD, which is why
// `CommandVocabulary.reasonNotAKeystroke` teaches the Commands-menu route rather
// than saying "unknown gesture". An agent carrying guidance from any earlier build
// will send a phrase here.
//
// EVERY GESTURE NOW COSTS THE ACCESSIBILITY GRANT, and it is asked for ONCE,
// BEFORE THE FIRST OF A BATCH. Not per keystroke, and not lazily inside the loop:
// a batch is checked before any of it moves the machine (see below), and a grant
// that failed in position three would leave the reader somewhere neither side
// asked for. `AccessibilityGrant` carries the rest of that argument, and is shared
// with `typeText` so the two commands cannot come to differ about when somebody's
// machine raises a consent dialog.
//
// 13.8'S LEVER IS GONE, AND 13.25 SPENT IT DELIBERATELY. The sentence used to be
// "a session that presses only the reader's command names and reads speech is
// never asked for Accessibility". It described a reading-only session by then, and
// it now describes nothing: a faithful user-persona session presses keys, and keys
// cost the grant. A lever bought by driving the reader in a way no user does is
// bought with the fidelity this tool sells.
//
// `mutatesReader = true`. Pressing a key moves the user's machine, so an
// observe-only session (spec 0017) refuses it. The flag defaults to `false` and
// the failure mode of forgetting is "allowed", which is why the registry's
// enumeration test asserts the set of mutating handlers rather than trusting each
// one.
//
// THE WHOLE BATCH IS CHECKED BEFORE ANY OF IT IS DISPATCHED, and that ordering is
// deliberate for a mutating command: an id the vocabulary refuses is the agent's
// own mistake, costs nothing to catch, and catching it in position three after two
// keys have already moved the machine would leave the reader somewhere neither
// side asked for.
//
// THE GRACE WINDOW IS PER GESTURE, AND THE BOOKMARK IS TAKEN BEFORE DISPATCH.
// The span reported for each press is where the ring stood either side of THAT
// key going out, which is what makes an empty span mean "this key said nothing"
// rather than "we looked too late". Attribution is by dispatch-time coordinate
// and not by causation (protocol.md §5): speech caused by gesture n can land after
// gesture n+1 went out, and is then credited to n+1.
//
// AND THE RESULT NEVER CLAIMS TO BE COMPLETE. protocol.md §7.3 in one sentence:
// a result says what had arrived by a stated instant, and where to resume; it
// never says that is all there is. So nothing here computes a `complete` flag,
// and `state` stays nil because this bridge announces no `state` capability.
//
// `announce` IS REFUSED IN A SILENT SESSION AND NOTED IN A LIVE ONE -- see
// `HumanWarning`, which carries that argument and is SHARED WITH `typeText`.
// 13.7 held it as a private method here; 13.8 made the second caller, and two
// commands that must not differ about a human's ears are two commands that
// should not be able to.

import Foundation
import ScreenReaderWire

public final class PressGestureHandler: CommandHandler {
	public let mutatesReader = true

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: PressGestureParams.self)
		let adapters = try readerEdge(context)
		let buffer = try context.speechBuffer()
		let grace = Double(max(0, params.graceMs)) / 1000.0

		// Refused or noted BEFORE the vocabulary check and before any dispatch:
		// if this session cannot tell the human what is about to happen to their
		// machine, nothing should happen to it.
		try HumanWarning.honour(context, params.announce)

		// WHAT `vo` MEANS ON THIS MACHINE, READ ONCE FOR THE BATCH -- 13.25. It is
		// read here rather than cached for the session, for the reason the keyboard
		// layout is: somebody who changes it mid-session gets the right keys on the
		// very next press. Once per CALL and not once per gesture, so that every id
		// in one batch is resolved against one answer -- a batch that pressed half
		// its keys against one binding and half against another would be a race
		// nobody could reproduce.
		let readerModifier = adapters.readerModifier.modifier()

		// Every id, classified before the first one goes out. See the header. A
		// `vo` this machine cannot resolve is refused HERE, so nothing is pressed
		// at all -- which is what makes the Caps Lock refusal safe rather than
		// half-done.
		let gestures = try params.gestures.map { gesture -> Keystroke in
			do {
				return try CommandVocabulary.classify(gesture, readerModifier: readerModifier)
			} catch let refusal as GestureIdRefused {
				throw CommandError(refusal.description)
			}
		}

		// ONCE, FOR THE WHOLE BATCH. Every gesture is a keystroke now (13.31), so
		// the only question left is whether there is one at all -- an empty batch
		// asks for nothing, which keeps `press_gesture []` a no-op rather than a
		// consent dialog. Asking here rather than inside the loop is the same
		// argument as the vocabulary check above: nothing should move the machine
		// before everything that can be settled up front has been.
		if !gestures.isEmpty {
			try AccessibilityGrant.ensure(adapters.permissions, orElse: "nothing was pressed")
		}

		let startIndex = buffer.nextIndex()
		var pressed: [GesturePress] = []
		for gesture in gestures {
			// BEFORE dispatch: the coordinate the ring stood at when this gesture
			// went out. See the header on why that is not the same as reading
			// afterwards and subtracting.
			let pressFrom = buffer.nextIndex()
			// WHAT THE BRIDGE UNDERSTOOD, NOT WHAT IT WAS HANDED: the keystroke's
			// canonical spelling, so `Command+L` is recorded and reported as
			// `command+l` and a reader of either can see which keys went out.
			let identifier = CommandVocabulary.identifier(for: gesture)
			context.transcript.gesture(identifier)
			try dispatch(gesture, identifier, adapters)
			_ = buffer.collectSince(pressFrom, grace: grace)
			pressed.append(
				GesturePress(gesture: identifier, speechFrom: pressFrom, speechTo: buffer.nextIndex())
			)
		}

		// The whole window is re-read rather than the per-command collections
		// being concatenated: the ring is the single source of what was said, and
		// one read of it cannot disagree with itself the way several appended
		// slices could.
		let read = buffer.entriesSince(startIndex)
		return GestureResult(
			pressed: pressed,
			speech: Observation.speechEntries(read.entries),
			speechFrom: read.fromIndex,
			speechTo: read.toIndex,
			// Never sampled: this bridge announces no `state` capability, because
			// VoiceOver's toggles are richly drivable and almost none is readable
			// (spec 0046 part 2). Nil is the honest answer, not a gap.
			state: nil
		)
	}

	// -- the pieces ------------------------------------------------------------

	private func readerEdge(_ context: SessionContext) throws -> AdapterSet {
		guard let adapters = context.adapters else {
			throw CommandError("a gesture was pressed before `hello` built the reader edge")
		}
		return adapters
	}

	/// Press one gesture, and name what went wrong if it would not go.
	///
	/// ============================================================================
	/// TWO CONDITIONS, WHERE THERE WERE THREE -- AND THE THIRD DELETED WITH ITS
	/// CHANNEL.
	/// ============================================================================
	///
	/// Until 13.31 a failure here could also mean "VoiceOver answers its own name
	/// but not its own state" -- the scripting object model dead while the process
	/// ran, which spec 0041 measured and required be reported as a named condition.
	/// There is no scripting object model in this bridge any more, so that condition
	/// is gone from the vocabulary rather than left as a case nothing can reach.
	///
	/// WHAT IS LEFT IS THE READ THAT A PRESS CANNOT MAKE FOR ITSELF. A `CGEvent`
	/// that posts successfully tells us nothing about whether anything was there to
	/// receive it, so the ONE thing worth adding to a failure is whether the reader
	/// exists at all -- a running-application lookup, at no permission cost (13.26),
	/// on the failure path only.
	///
	/// A PRESS THAT SUCCEEDS AND IS HEARD BY NOBODY IS NOT AN ERROR HERE, and that
	/// is deliberate: the speech span is empty, the result says so, and protocol.md
	/// §7.3 is explicit that a result reports what arrived rather than claiming
	/// completeness. Guessing a fault from silence is what an agent must not do and
	/// what this handler must not model for it.
	private func dispatch(
		_ keystroke: Keystroke, _ identifier: String, _ adapters: AdapterSet
	) throws {
		do {
			try adapters.keyPresser.press(keystroke)
		} catch let failure as KeyPressFailure {
			throw CommandError(explain(failure, identifier, adapters))
		}
	}

	/// Turn a press failure into something an agent can act on.
	private func explain(
		_ failure: KeyPressFailure, _ identifier: String, _ adapters: AdapterSet
	) -> String {
		guard adapters.readerLiveness.readerIsRunning() else {
			return
				"'\(identifier)' could not be pressed: \(failure.description). VoiceOver is also not "
				+ "running at all, which is very probably the whole story. Recovery: ask the human at "
				+ "this machine to start VoiceOver -- Command-F5 is what a person presses -- and try "
				+ "again."
		}
		return "'\(identifier)' could not be pressed: \(failure.description)"
	}
}
