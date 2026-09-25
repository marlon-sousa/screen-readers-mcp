// ROLE: port -- the bridge's channel TO the human sitting at the reader.
// IMPLEMENTED BY: SynthesizerAnnouncer, over the SpeechOut seam; FakeAnnouncer.
// BUILT BY: Wiring, once per process, and handed to the session in the AdapterSet.
// USED BY: the Announce controller and HumanWarning.
// Speaks with the bridge's own synthesizer outside VoiceOver, so it is audible in a silent session.
// A failure to speak is reported as a failed command, never swallowed.
public protocol Announcer: AnyObject {
	/// Acknowledges that the bridge spoke, never that anyone listened.
	func announce(_ text: String) throws
}

/// Why nothing could be said out loud.
public struct AnnouncerError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}
