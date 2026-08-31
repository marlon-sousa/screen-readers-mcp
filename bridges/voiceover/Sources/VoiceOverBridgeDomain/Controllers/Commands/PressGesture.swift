// ROLE: controller -- `pressGesture`: press the given gestures in order, then
// report what the reader said.
//
// BUILT BY: Registry. DRIVES: the CommandVocabulary entity (what may be sent at
// all, and WHICH ROUTE it takes), the GestureSender port (a command name), the
// KeyPresser port (a keystroke), the PermissionBroker port (the grant a
// keystroke costs), the session's SpeechBuffer (the grace window), and -- only
// on a failure -- the ReaderLiveness port.
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

		// Every id, classified before the first one goes out. See the header.
		let gestures = try params.gestures.map { gesture -> Gesture in
			do {
				return try CommandVocabulary.classify(gesture)
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
				throw CommandError(explain(failure, command, adapters.readerLiveness))
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
	/// THE ONE PLACE THE TWO PORTS ARE COMBINED, and the reason `ReaderLiveness`
	/// is a port of its own rather than a boolean the sender returns: "the reader
	/// answers its own name but not its own state" is a claim about TWO channels,
	/// and only a caller holding both can make it. Spec 0041 measured exactly that
	/// state -- the object model dead while the process ran and answered its name
	/// -- and required that a bridge report it as a distinct, named condition
	/// rather than as an empty result.
	///
	/// Liveness is asked ONLY here, on a failure that makes the answer mean
	/// something. Asking before every gesture would double the cost of the
	/// commonest command in the protocol to learn "yes".
	private func explain(
		_ failure: GestureError, _ command: String, _ liveness: any ReaderLiveness
	) -> String {
		guard case .scriptingChannelDead = failure else {
			return failure.description
		}
		guard liveness.readerAnswersItsOwnName() else {
			// A DIFFERENT CONDITION WITH A DIFFERENT RECOVERY, and this is the
			// distinction the port exists for: nothing answered at all, so the
			// reader is gone or wedged rather than half-alive.
			return
				"'\(command)' could not be dispatched and VoiceOver did not answer its own name "
				+ "either, so the reader is not running or is not responding. Recovery: check that "
				+ "VoiceOver is running (Command-F5), and that this bridge is allowed to control it "
				+ "under System Settings > Privacy & Security > Automation"
		}
		return "'\(command)' could not be dispatched. \(ReaderCondition.scriptingChannelDead.described)"
	}
}
