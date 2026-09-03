// ROLE: controller -- `pressGesture`: press the given gestures in order, then
// report what the reader said.
//
// BUILT BY: Registry. DRIVES: the CommandVocabulary entity (what may be sent at
// all, and WHICH ROUTE it takes), the GestureSender port (a command name), the
// KeyPresser port (a keystroke), the PermissionBroker port (the grant a
// keystroke costs), the session's SpeechBuffer (the grace window), and -- only
// on a failure -- the ReaderLiveness and ReaderScriptingSetting ports, which
// together separate THREE conditions that fail with identical error numbers
// (13.26; see `explain`, which carries the measurement).
//
// ============================================================================
// ONE COMMAND, TWO ROUTES, AND THE AGENT DOES NOT HAVE TO CHOOSE.
// ============================================================================
//
// A gesture id here is either one of VoiceOver's own English command names or a
// keystroke, and this handler decides which by asking `CommandVocabulary`:
//
//   press_gesture { gestures: ["describe item in voiceover cursor"] }  -> reader
//   press_gesture { gestures: ["command+l"] }                          -> system
//
// protocol.md §5 calls a gesture id "the reader's own user-facing command
// notation", and on NVDA that notation IS keystrokes -- so taking both here is
// consistent with the contract rather than a stretch, and a new wire command was
// declined for exactly that reason (spec 0048 §2.1). The agent picks an id by
// what it wants to HAPPEN; which of this bridge's two routes carries it is the
// bridge's business, which is the whole point of an opaque gesture id.
//
// THE KEYSTROKE HALF COSTS THE ACCESSIBILITY GRANT, and it is asked for ONCE,
// BEFORE THE FIRST GESTURE OF A BATCH THAT CONTAINS ONE. Not per keystroke, and
// not lazily inside the loop: a batch is checked before any of it moves the
// machine (see below), and a grant that failed in position three would leave the
// reader somewhere neither side asked for. `AccessibilityGrant` carries the rest
// of that argument, and is shared with `typeText` so the two commands cannot
// come to differ about when somebody's machine raises a consent dialog.
//
// `mutatesReader = true`, AND THIS IS THE FIRST HANDLER IN THE BRIDGE THAT SETS
// IT. Pressing a command moves the user's machine, so an observe-only session
// (spec 0017) refuses it. The flag defaults to `false` and the failure mode of
// forgetting is "allowed", which is why the registry's enumeration test asserts
// the set of mutating handlers rather than trusting each one.
//
// THE WHOLE BATCH IS CHECKED BEFORE ANY OF IT IS DISPATCHED, and that ordering
// is deliberate for a mutating command: an id the vocabulary refuses is the
// agent's own mistake, costs nothing to catch, and catching it in position three
// after two commands have already moved the machine would leave the reader
// somewhere neither side asked for. What CANNOT be checked up front is whether
// the reader knows a name -- only the reader knows that -- so an unknown command
// aborts the remainder mid-batch, exactly as lane 1 does, and the transcript
// carries the record of what did go out.
//
// THE GRACE WINDOW IS PER GESTURE, AND THE BOOKMARK IS TAKEN BEFORE DISPATCH.
// The span reported for each press is where the ring stood either side of THAT
// command going out, which is what makes an empty span mean "this command said
// nothing" rather than "we looked too late". Attribution is by dispatch-time
// coordinate and not by causation (protocol.md §5): speech caused by command n
// can land after command n+1 went out, and is then credited to n+1.
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
		let gestures = try params.gestures.map { gesture -> Gesture in
			do {
				return try CommandVocabulary.classify(gesture, readerModifier: readerModifier)
			} catch let refusal as GestureIdRefused {
				throw CommandError(refusal.description)
			}
		}

		// ONCE, FOR THE WHOLE BATCH, AND ONLY IF IT CONTAINS A KEYSTROKE. A batch
		// of command names goes past here without the broker being asked anything
		// at all, which is 13.8's lever as 13.17 narrowed it -- and asking here
		// rather than inside the loop is the same argument as the vocabulary check
		// above: nothing should move the machine before everything that can be
		// settled up front has been.
		if gestures.contains(where: \.isKeystroke) {
			try AccessibilityGrant.ensure(adapters.permissions, orElse: "nothing was pressed")
		}

		let startIndex = buffer.nextIndex()
		var pressed: [GesturePress] = []
		for gesture in gestures {
			// BEFORE dispatch: the coordinate the ring stood at when this gesture
			// went out. See the header on why that is not the same as reading
			// afterwards and subtracting.
			let pressFrom = buffer.nextIndex()
			// WHAT THE BRIDGE UNDERSTOOD, NOT WHAT IT WAS HANDED. A command name is
			// the trimmed id; a keystroke is its canonical spelling, so `Command+L`
			// is recorded and reported as `command+l` and a reader of either can see
			// which keys went out.
			let identifier = gesture.described
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

	/// Send one gesture down whichever of the two routes it belongs to.
	///
	/// THE ONLY PLACE THE ROUTING HAPPENS, and the two failures stay in their own
	/// vocabularies until here: an unknown command name is the reader's answer and
	/// may mean the scripting channel died, while an unpressable keystroke is this
	/// machine's keyboard layout answering and means nothing of the kind.
	private func dispatch(_ gesture: Gesture, _ identifier: String, _ adapters: AdapterSet) throws {
		switch gesture {
		case .readerCommand(let command):
			do {
				try adapters.gestureSender.press(command)
			} catch let failure as GestureError {
				throw CommandError(explain(failure, command, adapters))
			}
		case .keystroke(let keystroke):
			do {
				try adapters.keyPresser.press(keystroke)
			} catch let failure as KeyPressFailure {
				throw CommandError("'\(identifier)' could not be pressed: \(failure.description)")
			}
		}
	}

	/// Turn a dispatch failure into something an agent can act on.
	///
	/// THE ONE PLACE THE PORTS ARE COMBINED, and the reason `ReaderLiveness` is a
	/// port of its own rather than a boolean the sender returns: "the reader is
	/// there but its object model is not" is a claim about TWO channels, and only
	/// a caller holding both can make it. Spec 0041 measured exactly that state --
	/// the object model dead while the process ran -- and required that a bridge
	/// report it as a distinct, named condition rather than as an empty result.
	///
	/// ============================================================================
	/// THREE CONDITIONS, NOT TWO -- AND THE MIDDLE ONE WAS A SHIPPED DEFECT.
	/// ============================================================================
	///
	/// Until 13.26 this method asked one question, and on the machine 13.26 exists
	/// to support it gave a true sentence with a useless recovery. MEASURED LIVE,
	/// 2026-09-02, with "Allow VoiceOver to be controlled with AppleScript" OFF:
	///
	///     press_gesture ["go to menu bar"]
	///       -> "scriptingChannelDead: VoiceOver answers its own name but not its
	///           own state. Recovery: restart the reader ..."
	///
	/// Every clause of that is true. No restart brings back a switch the person
	/// deliberately turned off, so the recovery sent a human -- a blind human, at
	/// their own machine -- to take their screen reader away for nothing.
	///
	/// The cause is that the switch REMOVES THE SCRIPTING OBJECT MODEL and leaves
	/// the application answering its own properties, so it fails with **exactly**
	/// the numbers a wedged reader fails with: `-1728` to `return commander` and
	/// `-1708` to `perform command`, which is the pair `VoiceOverGestureSender`
	/// maps to `scriptingChannelDead`. The two states are NOT distinguishable by
	/// error number, ever. What separates them is the PREFERENCE, which this
	/// bridge already reads and until now never consulted here. Spec 0053 §2.1.
	///
	/// So: the reader is gone; or the route is switched off on this machine and
	/// the agent should PRESS THE KEY; or the route is on and the object model is
	/// genuinely dead, which is the one case a restart repairs.
	///
	/// BOTH READS ARE CHEAP AND BOTH HAPPEN ONLY ON A FAILURE. Liveness is now a
	/// running-application lookup rather than an AppleEvent (13.26), and the
	/// scripting setting is two file reads; asking either before every gesture
	/// would still be paying for an answer that is almost always the dull one.
	private func explain(
		_ failure: GestureError, _ command: String, _ adapters: AdapterSet
	) -> String {
		guard case .scriptingChannelDead = failure else {
			return failure.description
		}
		guard adapters.readerLiveness.readerIsRunning() else {
			// NOTHING IS THERE TO ANSWER, and that is the distinction the port
			// exists for: the reader is gone or wedged rather than half-alive, and
			// the recovery is a different one.
			return
				"'\(command)' could not be dispatched, and VoiceOver is not running at all. "
				+ "Recovery: ask the human at this machine to start VoiceOver -- Command-F5 is "
				+ "what a person presses -- and try again."
		}
		let scripting = adapters.readerScripting.scripting()
		guard scripting == .enabled else {
			// THE MIDDLE CONDITION. Not a fault, not a wedge: a deliberate setting,
			// and the agent has another route to the same act.
			return
				"'\(command)' is a COMMAND NAME, and this machine does not offer that route: "
				+ "VoiceOver Utility > General > \"Allow VoiceOver to be controlled with "
				+ "AppleScript\" is \(scripting == .disabled ? "switched off" : "not readable from here"). "
				+ "VoiceOver itself is running and healthy -- nothing needs restarting. WHAT YOU MUST "
				+ "DO: press the KEY for this act instead, which is what a person at this machine "
				+ "does and needs no AppleScript at all (`screenreader://reader-guidance` names the "
				+ "keys). An act with no key of its own is reached through the Commands menu -- "
				+ "`vo+h` twice, type its name, Enter. If you are the `expert` stance and you "
				+ "genuinely need the command-name route as an instrument, ask the human for it with "
				+ "`ask_user` -- that switch is theirs to give, and it lives in VoiceOver Utility > "
				+ "General. It takes effect at once, with no reader restart (measured 2026-09-02), but "
				+ "you must RECONNECT: this bridge decides which routes it has at the handshake and "
				+ "carries that answer for the whole session."
		}
		// THE ROUTE IS ON AND STILL FAILED. This is the one spec 0041 measured, and
		// the one a restart actually repairs.
		return "'\(command)' could not be dispatched. \(ReaderCondition.scriptingChannelDead.described)"
	}
}
