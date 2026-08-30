// A hand-written stateful fake for the Synthesizer port, mirroring
// Sources/CaptureVoice/Domain/Ports/Synthesizer.swift.
//
// This is the fake that makes the controller testable with NO AUDIO DEVICE and no
// VoiceOver: it records what it was asked to speak, in which voice, into which
// ring, and answers with whatever statistics the test wants reported.

@testable import CaptureVoice

final class FakeSynthesizer: Synthesizer {
	struct Spoken: Equatable {
		let utterance: Utterance
		let voice: AvailableVoice
	}

	private(set) var spoken: [Spoken] = []
	private(set) var ringsSpokenInto: [AudioRing] = []
	private(set) var cancelCount = 0
	private(set) var statisticsReads = 0
	/// Every call, in order, so a test can assert that the counters are read
	/// BEFORE the cancel that truncates the ring.
	private(set) var calls: [String] = []
	var onSpeak: (() -> Void)?

	var reported = SynthesisStatistics(
		prebufferMilliseconds: 0,
		callbackCount: 0,
		firstCallbackMilliseconds: -1,
		maxGapMilliseconds: 0,
		totalFrames: 0,
		spanMilliseconds: 0,
		sourceSampleRate: nil,
		sourceChannels: nil,
		converted: nil
	)

	func speak(_ utterance: Utterance, as voice: AvailableVoice, into ring: AudioRing) {
		calls.append("speak")
		spoken.append(Spoken(utterance: utterance, voice: voice))
		ringsSpokenInto.append(ring)
		onSpeak?()
	}

	func cancel() {
		calls.append("cancel")
		cancelCount += 1
	}

	func statistics() -> SynthesisStatistics {
		calls.append("statistics")
		statisticsReads += 1
		return reported
	}
}
