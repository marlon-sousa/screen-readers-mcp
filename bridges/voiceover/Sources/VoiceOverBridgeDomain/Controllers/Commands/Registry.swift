// ROLE: controller -- the explicit command-to-handler map, read top to bottom,
// and the one place this bridge states who it is.
//
// BUILT BY: Wiring, once per process. USED BY: the Session, which only ever
// looks a command up and calls `execute`.
//
// DELIBERATELY NOT A DI CONTAINER AND NOT DECORATOR AUTO-REGISTRATION (AGENTS.md,
// Decided). The graph is visible in one screen, and a wiring mistake is a
// compile error rather than a surprise discovered inside a screen reader.
//
// Handlers are stateless singletons -- the per-session state is the
// SessionContext handed to `execute` -- so one map serves every session. `hello`
// is the exception, because it needs the factory and the identity below.
//
// THE CAPABILITY LIST IS COMPLETE AT SIX ENTRIES, AND THAT IS THE LANE FINISHING
// AS DESIGNED. Spec 0046 settles this bridge's six capabilities -- speech,
// gestures, typing, focus, interact, guidance -- and says they are announced ONE
// ENTRY AT A TIME, so the gate always describes what works. At 13.5 the capture
// feed arrived, so `speech` was announced beside the five handlers that serve
// it; 13.7 added `gestures` beside the one that presses them, 13.8 added
// `typing` beside the one that types, 13.9 added `focus` beside the one that
// answers where the agent is, 13.10 added `interact` beside the three that
// reach the human, and 13.11 adds the last one. Each entry added its own:
//
// | Capability | Entry |
// |---|---|
// | speech | 13.5, the capture feed |
// | gestures | 13.7, input: commands |
// | typing | 13.8, input: typing |
// | focus | 13.9, focus |
// | interact | 13.10, the human channel |
// | guidance | 13.11, packaging and the live run -- here |
//
// Announcing a capability before the entry that implements it would produce the
// one failure the capability gate exists to prevent: a tool the agent can see
// and call, that answers nothing. The converse is a real cost too, and it is why
// `speech` goes in HERE rather than being held back to 13.6: a capture feed the
// server gates away is a tool nobody can call.
//
// `guidance` COMES LAST FOR A REASON THAT IS NOT SEQUENCING. Spec 0046 amended
// 13.1 to put it here because the document can only be written against a
// vocabulary that ALREADY WORKS: every concrete claim it makes -- that a gesture
// is a command name, that the modifiers do not compose, that the VoiceOver
// cursor's answer is localized where the tree's is not -- is a measurement some
// earlier entry paid for. Written any sooner it would have been this repo's guess
// about VoiceOver, which is precisely what protocol.md §4 says a bridge document
// exists to replace.
//
// AND IT IS THE FIRST CAPABILITY HERE THAT GATES SOMETHING OTHER THAN A TOOL:
// the server turns it into the `screenreader://reader-guidance` RESOURCE, so
// announcing it changes what an agent can READ rather than what it can call.

import ScreenReaderWire

public enum Registry {
	/// What this build serves -- all six of them, as of 13.11.
	public static let capabilities: [Capability] = [
		.speech, .gestures, .typing, .focus, .interact, .guidance,
	]

	/// This bridge's reader identity. `name` is the value protocol.md §1's
	/// endpoint convention is built from (`voiceoverMcpBridge`), and the version
	/// is VoiceOver's -- the READER's, never the bridge's, which travels
	/// separately as `bridgeVersion`.
	public static func reader(version: String) -> ReaderInfo {
		ReaderInfo(name: "voiceover", version: version)
	}

	/// The command map. Sixteen commands -- the four a session needs, the five
	/// `speech` promises, the one `gestures` does, the one `typing` does, the one
	/// `focus` does, the three `interact` does and the one `guidance` does. Each
	/// entry added its own handlers here, beside the capability it announced.
	public static func build(
		factory: any AdapterFactory,
		readerVersion: String,
		bridgeVersion: String
	) -> [String: any CommandHandler] {
		[
			Command.hello.rawValue: HelloHandler(
				factory: factory,
				reader: reader(version: readerVersion),
				capabilities: capabilities,
				bridgeVersion: bridgeVersion
			),
			Command.ping.rawValue: PingHandler(),
			Command.echo.rawValue: EchoHandler(),
			Command.bye.rawValue: ByeHandler(),
			// The five `speech` announces. One handler per command, in the order
			// protocol.md §7 lists them: read a range, read the last, take a
			// bookmark, wait for words, wait for quiet.
			Command.getSpeech.rawValue: GetSpeechHandler(),
			Command.getLastSpeech.rawValue: GetLastSpeechHandler(),
			Command.getNextSpeechIndex.rawValue: GetNextSpeechIndexHandler(),
			Command.waitForSpeech.rawValue: WaitForSpeechHandler(),
			Command.waitForSpeechToFinish.rawValue: WaitForSpeechToFinishHandler(),
			// What `gestures` announces, and the FIRST handler in this bridge that
			// moves the user's machine -- see its `mutatesReader`.
			Command.pressGesture.rawValue: PressGestureHandler(),
			// What `typing` announces, and the OTHER half of input -- a separate
			// capability from `gestures` because it costs a separate permission on
			// this platform, which is what lets an agent be told that one of them
			// works here and the other does not.
			Command.typeText.rawValue: TypeTextHandler(),
			// What `focus` announces. IT DOES NOT MUTATE THE READER and it asks for
			// no permission: it answers richer where typing's grant is already held
			// and thinner where it is not, which is what lets an observe-only session
			// ask where it is.
			Command.getFocusInfo.rawValue: GetFocusInfoHandler(),
			// What `interact` announces: the three commands that talk to the PERSON
			// rather than to the reader. `announce` is the channel the other two are
			// built on -- `askUser` speaks its question through it, and
			// `pressGesture` and `typeText` reach it through `HumanWarning` -- and it
			// is audible in a silent session because it goes around the reader
			// entirely.
			Command.announce.rawValue: AnnounceHandler(),
			Command.askUser.rawValue: AskUserHandler(),
			Command.waitForUserReply.rawValue: WaitForUserReplyHandler(),
			// What `guidance` announces: this reader's own account of the stance the
			// session declared. It reads files and touches no port, which is why it
			// is the only handler here whose failure mode is about the BUILD rather
			// than about the machine.
			Command.getGuidance.rawValue: GetGuidanceHandler(),
		]
	}
}
