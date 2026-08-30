// ROLE: port -- is the reader still there at all?
//
// IMPLEMENTED BY: VoiceOverLiveness (adapters), over the AppleScriptRunner seam;
// FakeReaderLiveness (Tests/Fakes).
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, and ONLY
// after a dispatch has already failed -- see below, because when it is asked is
// as much of the design as what it answers.
//
// IT EXISTS TO SEPARATE TWO FAILURES THAT LOOK IDENTICAL. Spec 0041 measured
// VoiceOver's scripting object model dying WITHOUT VoiceOver dying: after six
// consecutive `open next speech attribute guide` commands every VoiceOver call
// began failing, silently, with nothing wrong until the next one -- while
// `tell application "VoiceOver" to return name` still answered and the process
// was still running. A bridge that could not tell that from "the reader is gone"
// would report the wrong recovery for both.
//
// SO THE QUESTION IS DELIBERATELY THE NARROWEST ONE THAT SEPARATES THEM: does
// the reader answer its OWN name -- an application-level property that needs no
// scripting object model behind it? Yes plus a failed dispatch is
// `ReaderCondition.scriptingChannelDead`, and the recovery is a reader restart.
// No is a reader that is gone or wedged, and the recovery is different.
//
// IT IS ASKED ONLY ON A FAILURE, WHICH IS WHAT MAKES IT AFFORDABLE. Every call
// here is a subprocess; asking before each gesture would double the cost of the
// commonest command in the protocol to answer a question that is almost always
// "yes". The handler asks once, after a dispatch has already failed in the way
// that makes the answer meaningful.
//
// WHAT IT MUST NOT BE READ AS -- MEASURED 2026-08-30, AND IT COST AN EVENING.
// There is a THIRD condition that looks like both of the above from the outside:
// the APPLICATION UNDER TEST is wedged while the reader is entirely healthy. On
// the maintainer's machine Finder stopped responding, every cursor read answered
// `missing value`, dispatches appeared to do nothing -- and VoiceOver was fine,
// saying so out loud in the user's own language. `killall Finder` fixed it.
// Nothing on this port can detect that, and nothing here should pretend to: it
// answers one narrow question about the READER, and a healthy answer from it is
// not a claim that the machine under test is healthy. Spec 0047's finding 5 is
// the same confound approached from the other end.
public protocol ReaderLiveness: AnyObject {
	/// Whether the reader answers its own name.
	///
	/// NEVER THROWS. "It did not answer" IS the answer, and an error here would
	/// force the one caller -- itself already handling a failure -- to handle a
	/// second one in order to learn a boolean.
	func readerAnswersItsOwnName() -> Bool
}
