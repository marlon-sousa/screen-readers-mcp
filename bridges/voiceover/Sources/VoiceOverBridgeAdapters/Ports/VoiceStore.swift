// ROLE: adapter seam -- read and write the voice the reader speaks with.
//
// NOT A DOMAIN PORT: the domain asks for "the capture voice, selected", and has
// no idea that the answer lives in a preference domain belonging to the system's
// speech subsystem. This is the seam PluginKitProviderLifecycle depends on, which
// is the only way one adapter may depend on another (AGENTS.md).
//
// IMPLEMENTED BY: SpeakSelectionVoiceStore (the real preference) and
// FakeVoiceStore (Tests/Fakes).
//
// WHY THE SEAM EXISTS AT ALL, rather than the lifecycle reading the preference
// itself: the state machine's rules -- what pluginkit's answer means, what
// counts as "ours", whether a write took -- are decisions worth testing, and
// every one of them would otherwise need the maintainer's own machine, with its
// own voice selected, to exercise. Below this line is a preference domain; above
// it is a state machine.

/// The store could not be read or written. Distinct from "the store says the
/// voice is something else", which is an answer rather than a failure.
public struct VoiceStoreError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol VoiceStore: AnyObject {
	/// The identifier VoiceOver is set to speak with, or nil if it cannot be read.
	func selectedVoice() -> String?

	/// Point the reader at `identifier`. Applies live, in both directions, with
	/// no reader restart (spec 0047, finding 17).
	func select(_ identifier: String) throws
}
