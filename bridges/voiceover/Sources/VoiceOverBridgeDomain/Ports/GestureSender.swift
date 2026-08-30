// ROLE: port -- press one of the reader's own commands, and say what went wrong
// in a vocabulary the controller can act on.
//
// IMPLEMENTED BY: VoiceOverGestureSender (adapters), over the AppleScriptRunner
// seam; FakeGestureSender (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, and from
// 13.8 by nothing else -- typing is a different port, because it needs a grant
// this one deliberately never asks for.
//
// A GESTURE ON THIS READER IS AN ENGLISH COMMAND NAME, NOT A KEYSTROKE, and that
// is the whole reason this port takes a `String` and hands it on untouched.
// VoiceOver publishes 415 of them (`SCRStringsToCommandsMap.scrconfig` on macOS
// 15.0) mapping a phrase like "go to desktop" to an internal selector, and it
// dispatches them ITSELF -- so nothing here races with whatever else holds the
// keyboard, and this bridge asks for no Accessibility grant to press one. That
// is what keeps 13.8's laziness checkable: a session that only presses commands
// and reads speech never triggers an Accessibility request.
//
// THE THREE FAILURES ARE DISTINCT BECAUSE THE RECOVERIES ARE. An unknown name is
// the agent's mistake and costs nothing; a dead scripting object model is the
// machine's and costs a reader restart; anything else is a fault to report as
// itself. Collapsing them would put the bridge back to the one answer spec 0041
// says a bridge on this route must never give -- see ReaderCondition.

/// A gesture that could not be pressed.
///
/// Its own type rather than the command layer's `CommandError`, because a port
/// may not depend on a controller. The PressGesture handler translates it, and
/// is the only place that knows what to say about each.
public enum GestureError: Error, Equatable, CustomStringConvertible {
	/// The reader has no command by that name. Measured as `Command does not
	/// exist (6)`, which is exactly the clean failure this route was chosen for:
	/// a bad id costs one round trip and changes nothing on the machine.
	case unknownCommand(String)

	/// The reader answered its own name and nothing else: its scripting object
	/// model died without the reader dying (spec 0041). Nothing short of a reader
	/// restart recovers it, and the handler asks ReaderLiveness before saying so.
	case scriptingChannelDead

	/// Anything else, reported as itself rather than guessed at.
	case failed(String)

	public var description: String {
		switch self {
		case .unknownCommand(let name):
			return "this reader has no command called '\(name)'"
		case .scriptingChannelDead:
			return "VoiceOver's scripting object model is not answering"
		case .failed(let detail):
			return detail
		}
	}
}

public protocol GestureSender: AnyObject {
	/// Dispatch one command by its English name, blocking until the reader has
	/// taken it. What the command CAUSED is observed through the speech buffer,
	/// not returned here: the reader answers the dispatch, never the outcome.
	func press(_ command: String) throws
}
