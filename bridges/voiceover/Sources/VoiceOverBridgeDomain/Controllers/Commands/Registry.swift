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
// THE CAPABILITY LIST IS EMPTY, AND THAT IS THE ENTRY WORKING AS DESIGNED.
// Spec 0046 settles this bridge's six capabilities -- speech, gestures, typing,
// focus, interact, guidance -- and says they are announced ONE ENTRY AT A TIME,
// so the gate always describes what works. At 13.4 the session exists and no
// reader edge does, so it advertises nothing and the server gates every tool but
// the four ungated ones. Each entry below adds its own:
//
// | Capability | Entry |
// |---|---|
// | speech | 13.5, the capture feed |
// | gestures | 13.7 |
// | typing | 13.8 |
// | focus | 13.9 |
// | interact | 13.10, with the human channel |
// | guidance | 13.11, whose document can only be written against a vocabulary
// |           | that already works |
//
// Announcing a capability before the entry that implements it would produce the
// one failure the capability gate exists to prevent: a tool the agent can see
// and call, that answers nothing.

import ScreenReaderWire

public enum Registry {
	/// What this build serves. See the header for why it is empty and what fills
	/// it.
	public static let capabilities: [Capability] = []

	/// This bridge's reader identity. `name` is the value protocol.md §1's
	/// endpoint convention is built from (`voiceoverMcpBridge`), and the version
	/// is VoiceOver's -- the READER's, never the bridge's, which travels
	/// separately as `bridgeVersion`.
	public static func reader(version: String) -> ReaderInfo {
		ReaderInfo(name: "voiceover", version: version)
	}

	/// The command map. Four commands today; each later entry adds its own
	/// handlers here, beside the capability it announces.
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
		]
	}
}
