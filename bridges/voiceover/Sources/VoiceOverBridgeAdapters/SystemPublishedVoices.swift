// ROLE: LEAF adapter -- IMPLEMENTS the PublishedVoices seam over
// AVSpeechSynthesisVoice.
//
// USED BY: PluginKitProviderLifecycle, through the seam, never directly.
//
// IT DECIDES NOTHING: no filtering, no suffix matching, no interpretation of an
// empty list. Those are the state machine's, one layer up, where they are tested.
// No test file, per the repo's rule about leaves.
//
// THIS LIST, AND NOT `say -v '?'`. The `say` cache went on advertising the voice
// for an hour after the extension was unregistered (spec 0047, finding 18), so it
// answers a question about a cache rather than about the machine.

import AVFoundation

public final class SystemPublishedVoices: PublishedVoices {
	public init() {}

	public func identifiers() -> [String] {
		AVSpeechSynthesisVoice.speechVoices().map(\.identifier)
	}
}
