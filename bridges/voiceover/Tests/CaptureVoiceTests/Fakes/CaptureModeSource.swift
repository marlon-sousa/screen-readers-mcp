// A hand-written stateful fake for the CaptureModeSource port, mirroring
// Sources/CaptureVoice/Domain/Ports/CaptureModeSource.swift.
//
// It counts reads, because "asked once per utterance rather than cached" is a
// requirement: the bridge lifts silence between two utterances and the lift has
// to take effect on the next one. Counting also proves the OTHER half of 13.6's
// amendment -- one read per utterance, not one per question asked of it.

@testable import CaptureVoice

final class FakeCaptureModeSource: CaptureModeSource {
	var silent: Bool
	var preferredVoice: String?
	private(set) var reads = 0

	init(silent: Bool = false, preferredVoice: String? = nil) {
		self.silent = silent
		self.preferredVoice = preferredVoice
	}

	var directive: CaptureDirective {
		reads += 1
		return CaptureDirective(silent: silent, preferredVoice: preferredVoice)
	}
}
