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
// THE CAPABILITY LIST IS ONE ENTRY LONG, AND THAT IS THE ENTRY WORKING AS
// DESIGNED. Spec 0046 settles this bridge's six capabilities -- speech,
// gestures, typing, focus, interact, guidance -- and says they are announced ONE
// ENTRY AT A TIME, so the gate always describes what works. At 13.5 the capture
// feed exists, so `speech` is announced beside the five handlers that serve it
// and the server gates every other tool. Each entry below adds its own:
//
// | Capability | Entry |
// |---|---|
// | speech | 13.5, the capture feed -- here |
// | gestures | 13.7 |
// | typing | 13.8 |
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
	public static let capabilities: [Capability] = [.speech]

	/// This bridge's reader identity. `name` is the value protocol.md §1's
	/// endpoint convention is built from (`voiceoverMcpBridge`), and the version
	/// is VoiceOver's -- the READER's, never the bridge's, which travels
	/// separately as `bridgeVersion`.
	public static func reader(version: String) -> ReaderInfo {
		ReaderInfo(name: "voiceover", version: version)
	}

	/// The command map. Nine commands today -- the four a session needs, and the
	/// five `speech` promises; each later entry adds its own handlers here,
	/// beside the capability it announces.
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
		]
	}
}
