// ROLE: LEAF adapter -- IMPLEMENTS the Tones seam over AVFoundation. It makes
// the sound and decides nothing about what it means.
//
// BUILT BY: Wiring, once per process. USED BY: AudibleSessionSignals, which owns
// the vocabulary of cues and the preference that silences them.
//
// NO TEST FILE, AND HERE THAT IS A HARD RULE RATHER THAN THE USUAL LEAF
// ARGUMENT: a test that built this would play sounds on the developer's machine,
// which is the same class of mistake as speaking over them.
//
// ONE ENGINE, STARTED LAZILY AND KEPT. Starting an AVAudioEngine is the part
// that can fail -- no output device, an audio server that has gone away -- so it
// happens on the first cue and its failure is thrown to a caller who is already
// prepared to survive one. Building the engine at construction would move that
// failure to start-up, where the bridge has nobody to tell.
//
// THE TONES ARE SHAPED RATHER THAN SQUARE, and that is not decoration: a sine
// that starts and stops at full amplitude clicks, and two clicks are what a cue
// would be remembered as. The short fade at each end is arithmetic, not a
// decision about what the cue means.

import AVFoundation

public final class CoreAudioTones: Tones {
	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private let sampleRate: Double = 44100
	private var wired = false

	public init() {}

	public func play(_ frequencies: [Double], seconds: Double) throws {
		guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
			throw ToneError("this machine offers no audio format the cues can be rendered in")
		}
		try startIfNeeded(format: format)
		for frequency in frequencies {
			guard let buffer = CoreAudioTones.tone(frequency, seconds: seconds, format: format) else {
				throw ToneError("a cue at \(frequency) Hz could not be rendered")
			}
			player.scheduleBuffer(buffer, completionHandler: nil)
		}
		player.play()
	}

	private func startIfNeeded(format: AVAudioFormat) throws {
		if !wired {
			engine.attach(player)
			engine.connect(player, to: engine.mainMixerNode, format: format)
			wired = true
		}
		guard !engine.isRunning else { return }
		do {
			try engine.start()
		} catch {
			throw ToneError("the audio engine would not start: \(error.localizedDescription)")
		}
	}

	/// One tone as samples: a sine, with a five-millisecond fade at each end.
	private static func tone(_ frequency: Double, seconds: Double, format: AVAudioFormat)
		-> AVAudioPCMBuffer?
	{
		let rate = format.sampleRate
		let frames = AVAudioFrameCount(max(1, seconds * rate))
		guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
			let samples = buffer.floatChannelData?[0]
		else {
			return nil
		}
		buffer.frameLength = frames
		let fade = max(1.0, 0.005 * rate)
		for frame in 0..<Int(frames) {
			let position = Double(frame)
			let envelope = min(1.0, min(position, Double(frames) - position) / fade)
			samples[frame] = Float(sin(2 * .pi * frequency * position / rate) * envelope * 0.2)
		}
		return buffer
	}
}

/// Why a cue could not be played. Its own type so the session's guard reports
/// something a human can act on rather than a Core Audio status code.
public struct ToneError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}
