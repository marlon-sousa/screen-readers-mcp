// ROLE: adapter seam -- run one AppleScript, and hand back what it said or the
// NUMBER it failed with.
//
// NOT A DOMAIN PORT: the domain has no idea that pressing a gesture on this
// reader is an AppleEvent at all. This is the seam between two adapters, which
// is the only way one adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: OSAScriptRunner (over the ProcessRunner seam) and
// FakeAppleScriptRunner (Tests/Fakes), which answers from a script of canned
// results.
// USED BY: VoiceOverGestureSender and VoiceOverLiveness.
//
// THE MOST LOAD-BEARING SEAM IN THE LANE, as spec 0046 puts it, and this is what
// that means concretely: EVERY error-code finding in spec 0041 becomes an
// ordinary unit test above this line. `6` for an unknown command, `-1728` and
// `-1708` for a dead object model -- each of those cost a live measurement to
// learn, and none of them needs the maintainer's reader in a particular state to
// exercise ever again.
//
// THE NUMBER IS THE CONTRACT; THE MESSAGE IS NOT. Measured 2026-08-30 on the
// maintainer's machine: `osascript` writes `execution error: <message> (<n>)`,
// and THE MESSAGE IS LOCALIZED -- it came back in Portuguese, because that is
// the machine's language. A caller that branched on message text would work on
// the developer's machine and fail on the user's, in a way no test written in
// English would ever catch. So the number is parsed, carried and matched on, and
// the message is carried only to be shown to a human.

/// An AppleScript that ran and failed.
///
/// `number` is the AppleEvent / OSA error code, which is the only part of a
/// failure this bridge may reason about -- see the header on why the message is
/// not. `0` means the script failed without one, which a caller reports as
/// itself rather than trying to classify.
public struct AppleScriptError: Error, Equatable, CustomStringConvertible {
	public let number: Int
	public let message: String

	public init(number: Int, message: String) {
		self.number = number
		self.message = message
	}

	public var description: String {
		number == 0 ? message : "\(message) (\(number))"
	}
}

public protocol AppleScriptRunner: AnyObject {
	/// Run `script` and return its result, trimmed. Throws `AppleScriptError` on
	/// a failure, and `ProcessFailure` if the tool could not be run at all --
	/// which are different things, and the callers treat them differently.
	func run(_ script: String) throws -> String
}
