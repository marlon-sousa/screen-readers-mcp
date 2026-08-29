// A hand-written stateful fake for the CaptureModeSource port, mirroring
// Sources/CaptureVoice/Domain/Ports/CaptureModeSource.swift.
//
// It counts reads, because "asked once per utterance rather than cached" is a
// requirement: the bridge lifts silence between two utterances and the lift has
// to take effect on the next one.

@testable import CaptureVoice

final class FakeCaptureModeSource: CaptureModeSource {
	var silent: Bool
	private(set) var reads = 0

	init(silent: Bool = false) {
		self.silent = silent
	}

	var isSilent: Bool {
		reads += 1
		return silent
	}
}
