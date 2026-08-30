// ROLE: controller -- `pressGesture`: press the reader's own commands in order,
// then report what it said.
//
// BUILT BY: Registry. DRIVES: the GestureSender port (dispatch), the
// CommandVocabulary entity (what may be sent at all), the session's SpeechBuffer
// (the grace window), and -- only on a failure -- the ReaderLiveness port.
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

		// Every id, checked before the first one goes out. See the header.
		let commands = try params.gestures.map { gesture -> String in
			do {
				return try CommandVocabulary.accept(gesture)
			} catch let refusal as GestureIdRefused {
				throw CommandError(refusal.description)
			}
		}

		let startIndex = buffer.nextIndex()
		var pressed: [GesturePress] = []
		for command in commands {
			// BEFORE dispatch: the coordinate the ring stood at when this command
			// went out. See the header on why that is not the same as reading
			// afterwards and subtracting.
			let pressFrom = buffer.nextIndex()
			context.transcript.gesture(command)
			do {
				try adapters.gestureSender.press(command)
			} catch let failure as GestureError {
				throw CommandError(explain(failure, command, adapters.readerLiveness))
			}
			_ = buffer.collectSince(pressFrom, grace: grace)
			pressed.append(
				GesturePress(gesture: command, speechFrom: pressFrom, speechTo: buffer.nextIndex())
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
