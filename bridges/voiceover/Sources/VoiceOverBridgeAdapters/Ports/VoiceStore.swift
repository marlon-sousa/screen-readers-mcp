// ROLE: adapter seam that reads and writes the voice the reader speaks with.
// USED BY: PluginKitProviderLifecycle.
// IMPLEMENTED BY: SpeakSelectionVoiceStore and FakeVoiceStore.

/// The store could not be read or written; a different selected voice is an answer, not this error.
public struct VoiceStoreError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol VoiceStore: AnyObject {
	/// The identifier VoiceOver is set to speak with, or nil if it cannot be read.
	func selectedVoice() -> String?

	/// Applies live, in both directions, with no reader restart on VoiceOver on macOS 15.
	func select(_ identifier: String) throws
}
