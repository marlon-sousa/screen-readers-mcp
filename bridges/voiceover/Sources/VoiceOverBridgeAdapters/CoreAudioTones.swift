// ROLE: leaf adapter implementing the Tones seam over AVFoundation; it makes the sound and decides nothing.
// BUILT BY: Wiring, once per process.
// USED BY: AudibleSessionSignals, which owns the cue vocabulary.
// Do not unit-test this: building it plays sound on the developer's machine.
// The engine starts on the first cue, not at construction, so a start failure reaches a caller prepared to survive it.

import AVFoundation

public final class CoreAudioTones: Tones {
	/// Half scale, matching NVDA's `tones.beep` default volume of 50 that the NVDA bridge's cues use; taken from its documented signature, not read in NVDA's source.
	private static let amplitude: Float = 0.5

	private let engine = AVAudioEngine()
	private let player = AVAudioPlayerNode()
	private let sampleRate: Double = 44100
	private var wired = false

	public init() {}

	public func play(_ frequencies: [Double], seconds: Double, gapSeconds: Double) throws {
		guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
			throw ToneError("this machine offers no audio format the cues can be rendered in")
		}
		try startIfNeeded(format: format)
		for (index, frequency) in frequencies.enumerated() {
			if index > 0, gapSeconds > 0 {
				guard let silence = CoreAudioTones.tone(0, seconds: gapSeconds, format: format) else {
					throw ToneError("the silence between two cue tones could not be rendered")
				}
				player.scheduleBuffer(silence, completionHandler: nil)
			}
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

	/// A sine with a five-millisecond fade at each end, without which it clicks; frequency 0 renders the silence between tones.
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
			samples[frame] = Float(sin(2 * .pi * frequency * position / rate) * envelope) * amplitude
		}
		return buffer
	}
}

public struct ToneError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}
