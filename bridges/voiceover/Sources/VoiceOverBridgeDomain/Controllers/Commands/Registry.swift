// ROLE: controller, the explicit command-to-handler map and the one place this bridge states who
// it is.
// BUILT BY: Wiring, once per process.
// USED BY: the Session, which looks a command up and calls `execute`.
// Announce a capability only beside the handlers that serve it, or the agent sees a tool that
// answers nothing.
import ScreenReaderWire

public enum Registry {
	public static let capabilities: [Capability] = [
		.speech, .gestures, .typing, .focus, .interact, .guidance,
	]

	/// `version` is VoiceOver's own, never the bridge's, which travels as `bridgeVersion`.
	public static func reader(version: String) -> ReaderInfo {
		ReaderInfo(name: "voiceover", version: version)
	}

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
			Command.getSpeech.rawValue: GetSpeechHandler(),
			Command.getLastSpeech.rawValue: GetLastSpeechHandler(),
			Command.getNextSpeechIndex.rawValue: GetNextSpeechIndexHandler(),
			Command.waitForSpeech.rawValue: WaitForSpeechHandler(),
			Command.waitForSpeechToFinish.rawValue: WaitForSpeechToFinishHandler(),
			Command.pressGesture.rawValue: PressGestureHandler(),
			Command.typeText.rawValue: TypeTextHandler(),
			Command.getFocusInfo.rawValue: GetFocusInfoHandler(),
			Command.announce.rawValue: AnnounceHandler(),
			Command.askUser.rawValue: AskUserHandler(),
			Command.waitForUserReply.rawValue: WaitForUserReplyHandler(),
			Command.getGuidance.rawValue: GetGuidanceHandler(),
		]
	}
}
