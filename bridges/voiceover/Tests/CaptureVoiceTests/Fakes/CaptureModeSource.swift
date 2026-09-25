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
