// ROLE: adapter -- IMPLEMENTS the ReaderLiveness domain port, over the
// AppleScriptRunner seam.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: the PressGesture handler, through
// the port, and only after a dispatch has already failed.
//
// IT ASKS THE NARROWEST QUESTION THAT SEPARATES TWO FAILURES. `return name` is
// an APPLICATION-level property: answering it needs the process, the AppleEvents
// grant and nothing else -- no scripting object model, no cursor, no window.
// That is precisely why spec 0041 could measure it still answering while every
// VoiceOver-specific call failed with `-1728`/`-1708`. Any richer probe would
// have failed too, and the two conditions would have looked identical again.
//
// SO THE PROBE MUST NOT BE "IMPROVED". Reading `last phrase`, or the cursor, or
// anything the reader has to consult its own object model for, would turn this
// into a second copy of the failing call rather than a control for it.
//
// IT SWALLOWS EVERY ERROR, WHICH IS THE PORT'S CONTRACT AND NOT LAZINESS: the
// question is a boolean, its one caller is already handling a failure, and every
// way this can fail -- the grant is gone, the reader is not running, the tool
// could not be launched -- is a "no" as far as that caller is concerned. What
// each of those MEANS is the gesture sender's business, and it has already said
// so by the time this is asked.

import VoiceOverBridgeDomain

public final class VoiceOverLiveness: ReaderLiveness {
	/// The probe itself, PUBLIC because a second reader asks the same question of
	/// a different thing and must not ask it in different words.
	///
	/// `TCCPermissionBroker` sends this script to find out whether the automation
	/// grant is in force, because on this bridge that grant is a fact about the
	/// CHANNEL rather than about the calling binary (13.11). It cannot go through
	/// this class: liveness collapses every failure into `false`, and the broker
	/// needs the NUMBER -- `-1743` is the missing grant and everything else is
	/// not. So the two share the script and not the interpretation, which is the
	/// same shape `captureVoiceIdentifierSuffix` already has: read a second time
	/// rather than copied, so a change to what is asked cannot reach one caller
	/// and miss the other.
	public static let readerNameScript = "tell application \"VoiceOver\" to return name"

	private let runner: any AppleScriptRunner

	public init(runner: any AppleScriptRunner) {
		self.runner = runner
	}

	public func readerAnswersItsOwnName() -> Bool {
		guard let name = try? runner.run(Self.readerNameScript) else {
			return false
		}
		// A REPLY IS THE ANSWER, NOT ITS CONTENTS. The name is localized like
		// every other string this reader produces, so comparing it with
		// "VoiceOver" would be a test that passes in English and fails in
		// Portuguese -- which is the lane's own no-reader-strings rule, and the
		// same trap `OSAScriptRunner` records for error messages. That it
		// answered AT ALL is the whole signal.
		return !name.isEmpty
	}
}
