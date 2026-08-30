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
// THE CAPABILITY LIST IS THREE ENTRIES LONG, AND THAT IS THE ENTRY WORKING AS
// DESIGNED. Spec 0046 settles this bridge's six capabilities -- speech,
// gestures, typing, focus, interact, guidance -- and says they are announced ONE
// ENTRY AT A TIME, so the gate always describes what works. At 13.5 the capture
// feed arrived, so `speech` was announced beside the five handlers that serve
// it; 13.7 added `gestures` beside the one that presses them, and 13.8 adds
// `typing` beside the one that types. Each entry adds its own:
//
// | Capability | Entry |
// |---|---|
// | speech | 13.5, the capture feed |
// | gestures | 13.7, input: commands |
// | typing | 13.8, input: typing -- here |
// | focus | 13.9 |
// | interact | 13.10, with the human channel |
// | guidance | 13.11, whose document can only be written against a vocabulary
// |           | that already works |
//
// Announcing a capability before the entry that implements it would produce the
// one failure the capability gate exists to prevent: a tool the agent can see
// and call, that answers nothing. The converse is a real cost too, and it is why
// `speech` goes in HERE rather than being held back to 13.6: a capture feed the
// server gates away is a tool nobody can call.

import ScreenReaderWire

public enum Registry {
	/// What this build serves. See the header for what fills the rest.
	public static let capabilities: [Capability] = [.speech, .gestures, .typing]

	/// This bridge's reader identity. `name` is the value protocol.md §1's
	/// endpoint convention is built from (`voiceoverMcpBridge`), and the version
	/// is VoiceOver's -- the READER's, never the bridge's, which travels
	/// separately as `bridgeVersion`.
	public static func reader(version: String) -> ReaderInfo {
		ReaderInfo(name: "voiceover", version: version)
	}

	/// The command map. Eleven commands today -- the four a session needs, the
	/// five `speech` promises, the one `gestures` does and the one `typing` does;
	/// each later entry adds its own handlers here, beside the capability it
	/// announces.
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
		]
	}
}
