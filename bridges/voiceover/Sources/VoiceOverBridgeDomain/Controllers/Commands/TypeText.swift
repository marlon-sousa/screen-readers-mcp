// ROLE: controller -- `typeText`: insert literal text where the focus is, then
// report what the reader said about it.
//
// BUILT BY: Registry. DRIVES: the PermissionBroker port (the lazy grant), the
// TextTyper port (the injection), and the session's SpeechBuffer (the grace
// window, shared with `pressGesture` since 13.7).
//
// `mutatesReader = true`, the second handler in this bridge to say so. Typing
// moves the user's machine as surely as a keypress does, so an observe-only
// session (spec 0017) refuses it.
//
// ============================================================================
// THE ACCESSIBILITY GRANT IS REQUESTED HERE, ON THE FIRST typeText -- AND SINCE
// 13.17 FROM ONE OTHER PLACE, WHICH IS A KEYSTROKE `pressGesture`.
// ============================================================================
//
// That is 13.8's whole point rather than a detail of it. The two halves of input
// cost different permissions (spec 0041): pressing one of the reader's own
// COMMAND NAMES is an AppleEvent, typing is `kTCCServiceAccessibility`. Windows
// has no equivalent gate, so lane 1 has no analogue and there is nothing to copy
// -- this is the one design lever lane 3 has that lane 1 cannot have. Keeping
// them apart is what makes
//
//     a session that presses only the reader's COMMAND NAMES and reads speech
//     never triggers an Accessibility request
//
// a CHECKABLE statement rather than an intention. 13.17 narrowed that sentence
// by one word and did not spend it: `pressGesture` also takes keystrokes now,
// and a keystroke is a system event costing the same grant, so there are exactly
// TWO callers of `PermissionBroker.request` in this repository -- this command
// and that one, both handlers, both on the first act of a session that needs it.
// Not at construction, not in Wiring, not in the adapter factory, not in the
// doctor, not in a probe, and not in a test.
//
// THE CHECK ITSELF LIVES IN `AccessibilityGrant`, shared between the two, for
// the reason `HumanWarning` is shared: two commands that must not differ about
// whether somebody's machine raises a consent dialog should not be able to.
//
// THE CHECK COMES BEFORE THE INJECTION BECAUSE THE INJECTION CANNOT FAIL
// VISIBLY. An event posted by an untrusted process is dropped by the window
// server and `CGEvent.post` returns nothing, so without this check a session
// with no grant would report a perfectly successful `typeText` that typed
// nothing anywhere. See TextTyper's header.
//
// AND THE RESULT NEVER CLAIMS TO BE COMPLETE, exactly as `pressGesture`'s does
// not (protocol.md §7.3): what it says is what had arrived by a stated instant
// and where to resume. `state` stays nil because this bridge announces no
// `state` capability.

import Foundation
import ScreenReaderWire

public final class TypeTextHandler: CommandHandler {
	public let mutatesReader = true

	public init() {}

	public func execute(_ context: SessionContext, _ request: Request) throws -> any Encodable {
		let params = try request.params(as: TypeParams.self)
		let adapters = try readerEdge(context)
		let buffer = try context.speechBuffer()
		// `graceMs` DEFAULTS TO 0 HERE AND TO 100 FOR A GESTURE, and that is not an
		// oversight: a gesture produces one announcement worth reading, while
		// typing with "speak typed characters" on produces one utterance per
		// character and none of them is worth waiting for. Matching the two would
		// be consistency in the wrong dimension.
		let grace = Double(max(0, params.graceMs)) / 1000.0

		// Refused or noted BEFORE the grant is asked for and before anything is
		// typed, on the same terms `pressGesture` uses -- one shared function, so
		// the two commands cannot come to differ about a human's ears.
		try HumanWarning.honour(context, params.announce)

		try AccessibilityGrant.ensure(adapters.permissions, orElse: "nothing was typed")

		let startIndex = buffer.nextIndex()
		// Recorded BEFORE the injection, mirroring `pressGesture`: the attempt is
		// in the record even if the typer then fails, because the call anyone
		// reading a transcript is looking for is the one that went wrong. THE
		// LENGTH, NEVER THE TEXT -- see `count`.
		context.transcript.typed(Self.count(params.text))
		do {
			try adapters.textTyper.type(params.text)
		} catch let failure as TypingError {
			throw CommandError("the text could not be typed: \(failure.description)")
		}
		let read = buffer.collectSince(startIndex, grace: grace)

		return TypeResult(
			// The LENGTH of what was sent, never the text: this is exactly how a
			// secret is entered (protocol.md §5), and echoing it back would put the
			// secret in the result.
			typed: Self.count(params.text),
			speech: Observation.speechEntries(read.entries),
			speechFrom: read.fromIndex,
			speechTo: read.toIndex,
			// Never sampled: this bridge announces no `state` capability. Lane 1
			// DOES return one here; the difference is the reader's, not the
			// command's (spec 0046 part 2).
			state: nil
		)
	}

	// -- the pieces ------------------------------------------------------------

	/// How many characters `typed` reports.
	///
	/// UNICODE SCALARS, NOT SWIFT `Character`s, AND THE DIFFERENCE IS THE
	/// CONTRACT'S RATHER THAN A PREFERENCE. `typed` means the same number in all
	/// three bindings of this wire protocol or it means nothing: lane 1 reports
	/// Python's `len`, a code-point count, and the server's conformance scenario
	/// asserts the rune count of what it sent. Swift's `count` counts GRAPHEME
	/// CLUSTERS, so a decomposed "e" plus a combining acute would be 1 here and 2
	/// there -- a silent disagreement about a field whose whole job is to be
	/// comparable.
	static func count(_ text: String) -> Int {
		text.unicodeScalars.count
	}

	private func readerEdge(_ context: SessionContext) throws -> AdapterSet {
		guard let adapters = context.adapters else {
			throw CommandError("text was typed before `hello` built the reader edge")
		}
		return adapters
	}
}
