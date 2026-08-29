// ROLE: adapter -- implements CaptureModeSource by looking for a marker file.
//
// The file is written and deleted by the bridge (entry 13.6); this side only
// reads it, once per utterance, because a lift must take effect on the very next
// thing VoiceOver says.
//
// SILENCE IS OPT-IN AND THE ABSENCE OF THE MARKER IS THE SAFE ANSWER. On this
// route the provider IS the voice: unlike NVDA, where silent capture intercepts
// BEFORE the synthesizer and the user's own one stays loaded (spec 0008), here
// rendering silence leaves the machine's owner unable to hear their own computer.
// So the default -- and the answer when the question cannot be answered -- is
// "speak".
//
// A leaf in everything but name: one `fileExists` call and no decision. It has no
// test file for that reason.

import Foundation

public final class MarkerFileCaptureModeSource: CaptureModeSource {
	private let path: String

	public init(path: String) {
		self.path = path
	}

	public var isSilent: Bool {
		FileManager.default.fileExists(atPath: path)
	}
}
