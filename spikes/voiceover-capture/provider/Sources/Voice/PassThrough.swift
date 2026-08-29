// SPIKE (spec 0041, probe C4). Re-synthesis, so capturing does not mean muting.
//
// The provider route inverts spec 0008: on NVDA we intercept BEFORE the synth so
// the user's real synthesizer stays loaded, and here the swap IS the mechanism --
// VoiceOver has to be pointed at our voice. Hard invariant 3 ("a crashed harness
// must never leave a blind user with a mute screen reader") therefore lands on
// this file: everything VoiceOver says arrives here as SSML, and if we do not
// hand back intelligible audio, the machine's owner cannot hear his own computer.
//
// Silent mode is the easy half and is free -- return silence. This is the other
// half. It re-speaks each utterance with an ORDINARY Apple voice and returns
// those samples, so capture is transparent rather than costly.
//
// Re-entrancy is the obvious hazard: if the re-synthesis picked OUR voice we
// would be asked to synthesize our own output forever. Every voice whose
// identifier ends in ours is excluded, by construction rather than by naming a
// specific Apple voice that may not exist on someone else's machine.

import AVFoundation
import Foundation

/// The identifier the audio unit publishes. The system prefixes it with the
/// extension's bundle id, so anything matching it must match by SUFFIX.
let ourVoiceIdentifier = "org.screen-readers-mcp.spike.capture"

/// A completion backstop.
///
/// `write(_:toBufferCallback:)` signals the end of an utterance by delivering a
/// zero-length buffer -- but if that never arrives, the audio unit never reports
/// the utterance complete, and the host keeps pulling silence from a ring that
/// will never fill. The delegate says the same thing by a second route.
private final class CompletionWatcher: NSObject, AVSpeechSynthesizerDelegate {
	let onEnd: () -> Void
	init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }
	func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { onEnd() }
	func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { onEnd() }
}

final class PassThrough {
	/// ONE SYNTHESIZER PER UTTERANCE, deliberately.
	///
	/// VoiceOver cancels before every new utterance, so a shared instance is asked
	/// to stopSpeaking and then immediately to write again. Measured against a
	/// live reader: that combination stalls for seconds at a time -- one
	/// 191-character utterance starved the audio thread 810 times (about 9.4
	/// seconds of silence) while a longer 289-character one, arriving without a
	/// stop in flight, starved it not at all. A fresh synthesizer costs almost
	/// nothing and has no stop to finish.
	private var synthesizer = AVSpeechSynthesizer()
	/// Re-synthesis runs here rather than on whatever thread the system called us
	/// on. runningboardd parks this extension at PRIO_DARWIN_BG -- a background
	/// process feeding a realtime audio callback -- so the work says out loud that
	/// it is interactive.
	private let synthesisQueue = DispatchQueue(
		label: "org.screen-readers-mcp.spike.synthesis", qos: .userInteractive)
	private let ring: AudioRing
	/// NOT fixed at construction. The audio unit declares a format on its output
	/// bus, and the HOST may then set a different one -- converting to the format
	/// we wished for rather than the one the host will play is heard as glitching
	/// and wrong pitch, not as an error.
	private var outputFormat: AVAudioFormat
	private var converter: AVAudioConverter?
	private var converterInputFormat: AVAudioFormat?
	/// What the chosen voice actually produced, which is not knowable in advance
	/// and decides whether every buffer goes through a converter.
	private(set) var sourceFormat: AVAudioFormat?
	/// Whether this utterance has produced any audio yet, so the very first
	/// samples can be ramped up from silence rather than starting mid-waveform.
	private var startedAudio = false
	private var watcher: CompletionWatcher?
	/// Timing of the synthesizer's own callbacks, which is the only way to tell
	/// "our buffering is wrong" from "the thing producing audio stopped for ten
	/// seconds". Read at the end of each utterance.
	private(set) var callbackCount = 0
	private(set) var firstCallbackMS = -1
	private(set) var maxGapMS = 0
	private(set) var totalFrames = 0
	/// Wall time from the request to the last callback. Divided into the audio
	/// produced, this is the production RATE -- the number that decides whether
	/// feeding a realtime consumer is possible at all.
	private(set) var spanMS = 0
	private var requestedAt = Date()
	private var lastCallbackAt: Date?

	init(ring: AudioRing, outputFormat: AVAudioFormat) {
		self.ring = ring
		self.outputFormat = outputFormat
	}

	func adoptOutputFormat(_ format: AVAudioFormat) {
		guard format != outputFormat else { return }
		outputFormat = format
		converter = nil
		converterInputFormat = nil
	}

	var currentOutputFormat: AVAudioFormat { outputFormat }

	/// Best-effort language of an utterance, read from the SSML the system handed
	/// us. VoiceOver speaks the user's language, which is not necessarily the
	/// language our voice declares first, so trusting our own declaration would
	/// re-speak Portuguese with an English voice.
	static func language(inSSML ssml: String) -> String? {
		guard let range = ssml.range(of: "xml:lang=\"") else { return nil }
		let rest = ssml[range.upperBound...]
		guard let end = rest.firstIndex(of: "\"") else { return nil }
		let value = String(rest[..<end])
		return value.isEmpty ? nil : value
	}

	/// An ordinary system voice to re-speak with -- never ours.
	///
	/// Measured on macOS 15.0, and the reason this is not simply "the first voice
	/// matching the language": `speechVoices()` LISTS voices that then fail to
	/// synthesize. Picking `com.apple.eloquence.pt-BR.Reed` produced audio in a
	/// completely different voice, because CoreSynthesizer logged "Utterance
	/// encountered error, next fallback state: retrySameVoice / retryFallbackVoice"
	/// and quietly substituted the system default. The listener hears speech, so
	/// nothing looks wrong -- but the provider's stated choice was a fiction.
	///
	/// So ask the system for the language's DEFAULT voice first. That is the voice
	/// the machine already uses and is therefore known to work here, and it is
	/// also the one whose sound the user expects.
	static func fallbackVoice(language: String?) -> AVSpeechSynthesisVoice? {
		func isOurs(_ voice: AVSpeechSynthesisVoice) -> Bool {
			voice.identifier.hasSuffix(ourVoiceIdentifier)
		}
		// Measured against a live VoiceOver on macOS 15.0: its SSML carries
		// <prosody> and <break>, and NO xml:lang at all. So "the language of this
		// utterance" is usually unknown here, and falling through to "whatever
		// voice is first" is not a harmless default -- it picked
		// com.apple.voice.compact.ar-001.Maged and read Portuguese aloud in
		// Arabic. The system's CURRENT language is the honest default: it is what
		// the reader is speaking.
		let effective = language ?? AVSpeechSynthesisVoice.currentLanguageCode()
		if let preferred = AVSpeechSynthesisVoice(language: effective), !isOurs(preferred) {
			return preferred
		}
		let candidates = AVSpeechSynthesisVoice.speechVoices().filter { !isOurs($0) }
		if let exact = candidates.first(where: { $0.language == effective }) { return exact }
		let prefix = String(effective.prefix(2))
		return candidates.first { $0.language.hasPrefix(prefix) } ?? candidates.first
	}

	/// Starts re-synthesis. Returns what it decided, so the decision is logged
	/// rather than inferred from how the audio sounds.
	func begin(ssml: String) -> (voice: String, language: String) {
		ring.reset()
		ring.resetCounters()
		sourceFormat = nil
		startedAudio = false
		callbackCount = 0
		firstCallbackMS = -1
		maxGapMS = 0
		totalFrames = 0
		spanMS = 0
		requestedAt = Date()
		lastCallbackAt = nil
		synthesizer = AVSpeechSynthesizer()
		let language = PassThrough.language(inSSML: ssml)
		let voice = PassThrough.fallbackVoice(language: language)

		let utterance: AVSpeechUtterance
		if let fromSSML = AVSpeechUtterance(ssmlRepresentation: ssml) {
			utterance = fromSSML
		} else {
			// A malformed or unsupported SSML string must still be audible.
			utterance = AVSpeechUtterance(string: PassThrough.strippingTags(ssml))
		}
		utterance.voice = voice

		synthesisQueue.async { [weak self] in
			self?.startWriting(utterance)
		}
		return (voice?.identifier ?? "<none>", language ?? "<unknown>")
	}

	private func startWriting(_ utterance: AVSpeechUtterance) {
		let writer = synthesizer
		let watcher = CompletionWatcher { [weak self] in
			self?.ring.fadeOutTail(self?.fadeSamples ?? 0)
			self?.ring.markFinished()
		}
		self.watcher = watcher
		writer.delegate = watcher
		writer.write(utterance) { [weak self] buffer in
			guard let self else { return }
			let now = Date()
			if self.firstCallbackMS < 0 {
				self.firstCallbackMS = Int(now.timeIntervalSince(self.requestedAt) * 1000)
			}
			if let previous = self.lastCallbackAt {
				self.maxGapMS = max(self.maxGapMS, Int(now.timeIntervalSince(previous) * 1000))
			}
			self.lastCallbackAt = now
			self.spanMS = Int(now.timeIntervalSince(self.requestedAt) * 1000)
			self.callbackCount += 1
			guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
				self.ring.fadeOutTail(self.fadeSamples)
				self.ring.markFinished()
				return
			}
			if self.sourceFormat == nil { self.sourceFormat = pcm.format }
			self.append(pcm)
		}
	}

	/// Waits until playback can start without starving, and reports how long that
	/// took. Called by the audio unit after begin(), on the system's own thread.
	///
	/// The host starts pulling audio in 256-frame blocks the moment synthesis is
	/// requested, and re-synthesis has produced nothing yet. Measured against a
	/// live VoiceOver: short utterances starved the audio thread ~10 times and a
	/// 289-character help message starved it 955 times, with no lock contention
	/// and no format conversion -- so the glitching was never the ring or the
	/// converter, it was playback starting before there was anything to play.
	func prebuffer() -> Int {
		let started = Date()
		let deadline = started.addingTimeInterval(PassThrough.prebufferBudget)
		// Wait for the WHOLE utterance, not for a head start.
		//
		// The measurement that forced this: 242,688 frames produced, 242,688
		// drained, none dropped, producer finished -- and 923 render calls that
		// still came up short. That can only happen if the host is not pulling in
		// realtime: it renders offline, as fast as it can ask, and no producer
		// outruns that. Every short answer became silence baked into the audio.
		//
		// Synthesis runs about 24x realtime here, so waiting for all of it costs
		// roughly 0.45 s for eleven seconds of speech -- less than the head start
		// used to cost on long utterances, and it cannot starve.
		// Wait only for the FIRST audio now, not the whole utterance: the render
		// block waits for the rest. That trades ~0.4 s before long sentences for
		// ~0.17 s, and the gaps stay closed because nobody answers with silence.
		while ring.available == 0, !ring.isFinished, Date() < deadline {
			usleep(2000)
		}
		return Int(Date().timeIntervalSince(started) * 1000)
	}


	/// Never wait longer than this: a glitch traded for a hang is a bad trade on
	/// the machine's only screen reader.
	static let prebufferBudget: TimeInterval = 2.0

	/// About 6 ms at the output rate: long enough to remove a click, short enough
	/// that no syllable is lost to it.
	var fadeSamples: Int { max(2, Int(outputFormat.sampleRate * 0.006)) }

	func cancel() {
		// Let the old instance go rather than reusing it: whatever it is doing, it
		// is doing it alone, and the next utterance gets a clean one.
		let outgoing = synthesizer
		synthesizer = AVSpeechSynthesizer()
		synthesisQueue.async { outgoing.stopSpeaking(at: .immediate) }
		ring.truncateWithFade(fadeSamples)
	}

	private func append(_ pcm: AVAudioPCMBuffer) {
		guard let converted = convert(pcm), let channel = converted.floatChannelData?[0] else { return }
		let frames = Int(converted.frameLength)
		if !startedAudio {
			startedAudio = true
			let ramp = min(fadeSamples, frames)
			if ramp > 1 {
				for step in 0..<ramp {
					channel[step] *= Float(step) / Float(ramp - 1)
				}
			}
		}
		totalFrames += frames
		ring.append(channel, count: frames)
	}

	/// The written buffers are whatever the chosen voice produces -- sample rate,
	/// layout and sample type all vary by voice -- and the audio unit's output bus
	/// is fixed. So everything is converted rather than assumed.
	private func convert(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
		if pcm.format == outputFormat { return pcm }
		if converter == nil || converterInputFormat != pcm.format {
			converter = AVAudioConverter(from: pcm.format, to: outputFormat)
			converterInputFormat = pcm.format
		}
		guard let converter else { return nil }
		let ratio = outputFormat.sampleRate / pcm.format.sampleRate
		let capacity = AVAudioFrameCount(Double(pcm.frameLength) * ratio) + 1024
		guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
		var supplied = false
		var error: NSError?
		converter.convert(to: output, error: &error) { _, status in
			if supplied {
				status.pointee = .noDataNow
				return nil
			}
			supplied = true
			status.pointee = .haveData
			return pcm
		}
		return error == nil ? output : nil
	}

	private static func strippingTags(_ text: String) -> String {
		var result = ""
		var inTag = false
		for character in text {
			if character == "<" { inTag = true } else if character == ">" { inTag = false } else if !inTag {
				result.append(character)
			}
		}
		return result.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}
