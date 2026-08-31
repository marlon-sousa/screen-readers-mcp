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
	/// How loud a cue is, as a fraction of full scale.
	///
	/// IT WAS 0.2 AND NOBODY HAD SAID WHY -- the one parameter in this file with
	/// no argument behind it, while the fade, the duration and the pitches each
	/// carried one. That gap was found the way such gaps should be: the
	/// maintainer, who is blind and uses NVDA daily, heard the cue and said it was
	/// "light" where NVDA's is "clear", then asked how it had been decided. The
	/// honest answer was that the pattern had been designed and the loudness had
	/// not.
	///
	/// WHAT IS BEING MATCHED IS THE NVDA BRIDGE'S CUE -- lane 1 of this repo, the
	/// sound the maintainer actually hears when a session takes his reader -- and
	/// not NVDA's beeps in general. `nvda_session_signals.py` calls
	/// `tones.beep(hz, ms)` and takes NVDA's default volume, which its signature
	/// puts at `left=50, right=50`: half scale. **Not verified against NVDA's
	/// source here** -- `../nvda` is a stated prerequisite for reading real code
	/// and this machine has no checkout -- so the number is the documented default
	/// rather than a line somebody read. Lane 1's TIMING, which
	/// `AudibleSessionSignals` now matches, is in this repository and was.
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
			// THE SILENCE GOES BEFORE EVERY TONE BUT THE FIRST, so a pair is heard
			// as two beeps rather than as one sound that changes pitch. Scheduled as
			// a buffer rather than timed with a delay: the player queue already
			// guarantees order, and a `DispatchQueue.asyncAfter` would put the cue's
            // rhythm at the mercy of whatever else the session thread is doing.
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

	/// One tone as samples: a sine, with a five-millisecond fade at each end.
	///
	/// A frequency of ZERO renders silence, which is how the gap between two tones
	/// is scheduled -- `sin(0)` is 0 for every sample, so no special case is
	/// needed and the silence carries the same envelope arithmetic as a tone.
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

/// Why a cue could not be played. Its own type so the session's guard reports
/// something a human can act on rather than a Core Audio status code.
public struct ToneError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}
