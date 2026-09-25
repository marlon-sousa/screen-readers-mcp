// ROLE: adapter that implements the SessionSignals port: what the five cues sound like, and which carry words.
// BUILT BY: Wiring, once per process.
// USED BY: the Session controller, through the port.
// Tones go straight to the audio device and words through the bridge's own synthesizer, because a cue
// routed through the reader cannot be heard during a silent session.
// `cuesEnabled` is read on every cue, so it applies to the running session; it silences all five cues,
// but the silence cap's lift still happens on time.

import VoiceOverBridgeDomain

public final class AudibleSessionSignals: SessionSignals {
	enum Cue {
		static let taken: [Double] = [660, 880]
		static let released: [Double] = [880, 660]
		static let warning: [Double] = [440, 440]
		static let lifted: [Double] = [660, 990]
		static let resuppressed: [Double] = [990, 660]
		/// 180 ms tones with 120 ms between them match the NVDA bridge's cue; 90 ms with no gap was heard
		/// as one sound.
		static let seconds: Double = 0.18
		static let gapSeconds: Double = 0.12
	}

	private let tones: any Tones
	private let announcer: any Announcer
	private let config: any BridgeConfig

	public init(tones: any Tones, announcer: any Announcer, config: any BridgeConfig) {
		self.tones = tones
		self.announcer = announcer
		self.config = config
	}

	public func sessionStarted(persona: String) throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.taken, seconds: Cue.seconds, gapSeconds: Cue.gapSeconds)
		let stance = persona.trimmingCharacters(in: .whitespacesAndNewlines)
		try announcer.announce(
			stance.isEmpty
				? "screen reader testing session started"
				: "screen reader testing session started, as \(stance)")
	}

	public func sessionEnded() throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.released, seconds: Cue.seconds, gapSeconds: Cue.gapSeconds)
	}

	public func silenceWarning() throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.warning, seconds: Cue.seconds, gapSeconds: Cue.gapSeconds)
		try announcer.announce("your machine has been quiet for a while, and is about to speak again")
	}

	public func silenceLifted() throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.lifted, seconds: Cue.seconds, gapSeconds: Cue.gapSeconds)
	}

	public func silenceResuppressed() throws {
		guard config.cuesEnabled else { return }
		try tones.play(Cue.resuppressed, seconds: Cue.seconds, gapSeconds: Cue.gapSeconds)
		try announcer.announce("speech is suppressed again, on a fresh window")
	}
}
