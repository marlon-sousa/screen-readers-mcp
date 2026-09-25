// ROLE: leaf adapter implementing the PublishedVoices seam over AVSpeechSynthesisVoice.
// USED BY: PluginKitProviderLifecycle, through the seam.
// Not `say -v '?'`: on macOS 15 its cache went on listing the voice for an hour after the extension was unregistered.

import AVFoundation

public final class SystemPublishedVoices: PublishedVoices {
	public init() {}

	public func identifiers() -> [String] {
		AVSpeechSynthesisVoice.speechVoices().map(\.identifier)
	}

	/// The voice list does not update without this; see the PublishedVoices seam.
	public func refresh() {
		AVSpeechSynthesisProviderVoice.updateSpeechVoices()
	}
}
