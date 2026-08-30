// ROLE: adapter -- implements the Synthesizer port with AVFoundation.
//
// RE-SYNTHESIS, SO CAPTURING DOES NOT MEAN MUTING. The provider route inverts
// spec 0008: on NVDA the capture happens BEFORE the synthesizer and the user's
// real one stays loaded, and here the swap IS the mechanism -- VoiceOver has to
// be pointed at our voice. Hard invariant 3 therefore lands on this file:
// everything VoiceOver says arrives as SSML, and if we do not hand back
// intelligible audio, the machine's owner cannot hear his own computer.
//
// COLLABORATORS. Built by CaptureAudioUnit, which also tells it the format the
// host settled on; called by CaptureController through the port; writes into the
// AudioRing it is handed. It chooses NOTHING: the voice arrives already decided
// by VoiceChoice, in the domain, where that decision is tested.
//
// FOUR OF THE SIX LIVE-ROUND FIXES ARE HERE, and each cost an evening against
// the maintainer's own screen reader (spec 0041, C4):
//
//  1. ONE AVSpeechSynthesizer PER UTTERANCE. VoiceOver cancels before every new
//     utterance, so a shared instance is asked to stopSpeaking and then
//     immediately to write again -- and that combination stalls for seconds. One
//     191-character utterance starved the audio thread 810 times, about 9.4
//     seconds of silence, while a longer one arriving with no stop in flight
//     starved it not at all.
//  2. THE COMPLETION BACKSTOP. `write(_:toBufferCallback:)` signals the end with
//     a zero-length buffer; when that does not arrive, the unit never reports
//     the utterance complete and the host pulls silence from a ring that will
//     never fill. The delegate says the same thing by a second route.
//  3. THE BOUNDARY RAMPS. Speech does not end at a zero crossing, and every
//     utterance here ends in a cancel, so every one of them clicks without a
//     ~6 ms ramp. In an attended session that is a defect, not a polish item.
//  4. THE HOST SETTLES THE OUTPUT FORMAT, at allocateRenderResources, and it is
//     not necessarily what the unit declared. Converting to the format we wished
//     for is heard as glitching and wrong pitch rather than reported as an error.
//
// (The remaining two -- the PRIO_DARWIN_BG escape and the bounded wait inside
// the render block -- are in CaptureAudioUnit, where the thread they concern is.)
//
// THREADING. `speak` is called on the system's request thread and dispatches the
// writing to its own queue; the buffer callback runs on that queue; `cancel`
// arrives on the system's thread. The statistics are written by the callback and
// read by cancel without a lock -- deliberately, as in the spike: they are
// diagnostics, and a lock on this path would be paid on every buffer to make a
// reported number exact that nobody acts on to that precision.

import AVFoundation
import Foundation

/// AVFoundation's synthesizer and utterance predate Swift concurrency and are not
/// `Sendable`, and both have to cross onto the synthesis queue: the utterance to
/// be written, and the OUTGOING synthesizer to be stopped off to the side (fix 1).
///
/// This box says that out loud rather than leaving two warnings on every build.
/// It is sound for the use it is put to here and nowhere else: each value is
/// handed over exactly once, to one serial queue, and the sender does not touch
/// it again -- `synthesizer` has already been replaced by the time `outgoing`
/// travels, and `spoken` is constructed for this one call.
private struct Handoff<Value>: @unchecked Sendable {
	let value: Value
}

/// A completion backstop -- fix 2 above.
private final class CompletionWatcher: NSObject, AVSpeechSynthesizerDelegate {
	let onEnd: () -> Void
	init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }
	func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onEnd() }
	func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onEnd() }
}

public final class AVFoundationSynthesizer: Synthesizer {
	/// Never wait longer than this: a glitch traded for a hang is a bad trade on
	/// the machine's only screen reader.
	public static let prebufferBudget: TimeInterval = 2.0

	private var synthesizer = AVSpeechSynthesizer()
	/// Re-synthesis runs here rather than on whatever thread the system called us
	/// on. runningboardd parks this extension at PRIO_DARWIN_BG -- a background
	/// process feeding a realtime audio callback -- so the work says out loud that
	/// it is interactive.
	private let synthesisQueue = DispatchQueue(
		label: "org.screen-readers-mcp.voiceover.synthesis", qos: .userInteractive)
	/// NOT fixed at construction; see fix 4.
	private var outputFormat: AVAudioFormat
	private var converter: AVAudioConverter?
	private var converterInputFormat: AVAudioFormat?
	private var sourceFormat: AVAudioFormat?
	/// Whether this utterance has produced any audio yet, so the very first
	/// samples can be ramped up from silence rather than starting mid-waveform.
	private var startedAudio = false
	private var watcher: CompletionWatcher?
	private var ring: AudioRing?

	private var prebufferMS = 0
	private var callbackCount = 0
	private var firstCallbackMS = -1
	private var maxGapMS = 0
	private var totalFrames = 0
	private var spanMS = 0
	private var requestedAt = Date()
	private var lastCallbackAt: Date?

	public init(outputFormat: AVAudioFormat) {
		self.outputFormat = outputFormat
	}

	/// Called by the audio unit once the host has settled the real format.
	public func adoptOutputFormat(_ format: AVAudioFormat) {
		guard format != outputFormat else { return }
		outputFormat = format
		converter = nil
		converterInputFormat = nil
	}

	public var currentOutputFormat: AVAudioFormat { outputFormat }

	/// About 6 ms at the output rate: long enough to remove a click, short enough
	/// that no syllable is lost to it.
	public var fadeSamples: Int { max(2, Int(outputFormat.sampleRate * 0.006)) }

	public func speak(_ utterance: Utterance, as voice: AvailableVoice, into ring: AudioRing) {
		self.ring = ring
		ring.reset()
		ring.resetCounters()
		sourceFormat = nil
		startedAudio = false
		prebufferMS = 0
		callbackCount = 0
		firstCallbackMS = -1
		maxGapMS = 0
		totalFrames = 0
		spanMS = 0
		requestedAt = Date()
		lastCallbackAt = nil
		synthesizer = AVSpeechSynthesizer()

		let spoken: AVSpeechUtterance
		if let fromSSML = AVSpeechUtterance(ssmlRepresentation: utterance.ssml) {
			spoken = fromSSML
		} else {
			// Malformed or unsupported SSML must still be AUDIBLE. Whatever arrives
			// has to be spoken; refusing it would mute the reader for that sentence.
			spoken = AVSpeechUtterance(string: utterance.text)
		}
		// The domain chose by identifier; AVFoundation is asked for that exact voice
		// and, if it will not construct one, for the language's default. Leaving it
		// nil is the last resort and is safe here rather than re-entrant: our own
		// voice is unusable by an ordinary AVSpeechSynthesizer client -- measured, it
		// fails with CoreSynthesizer's retryFallbackVoice and falls back -- so the
		// system default cannot end up being us (spec 0041, A1).
		spoken.voice =
			AVSpeechSynthesisVoice(identifier: voice.identifier)
			?? AVSpeechSynthesisVoice(language: voice.language)

		let handoff = Handoff(value: spoken)
		synthesisQueue.async { [weak self] in
			self?.startWriting(handoff.value, into: ring)
		}
		prebufferMS = prebuffer(ring)
	}

	public func cancel() {
		// Let the old instance go rather than reusing it: whatever it is doing, it
		// is doing it alone, and the next utterance gets a clean one (fix 1).
		let outgoing = Handoff(value: synthesizer)
		synthesizer = AVSpeechSynthesizer()
		synthesisQueue.async { outgoing.value.stopSpeaking(at: .immediate) }
		ring?.truncateWithFade(fadeSamples)
	}

	public func statistics() -> SynthesisStatistics {
		SynthesisStatistics(
			prebufferMilliseconds: prebufferMS,
			callbackCount: callbackCount,
			firstCallbackMilliseconds: firstCallbackMS,
			maxGapMilliseconds: maxGapMS,
			totalFrames: totalFrames,
			spanMilliseconds: spanMS,
			sourceSampleRate: sourceFormat?.sampleRate,
			sourceChannels: sourceFormat.map { Int($0.channelCount) },
			converted: sourceFormat.map { $0 != outputFormat }
		)
	}

	private func startWriting(_ spoken: AVSpeechUtterance, into ring: AudioRing) {
		let writer = synthesizer
		let watcher = CompletionWatcher { [weak self] in
			ring.fadeOutTail(self?.fadeSamples ?? 0)
			ring.markFinished()
		}
		self.watcher = watcher
		writer.delegate = watcher
		writer.write(spoken) { [weak self] buffer in
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
				ring.fadeOutTail(self.fadeSamples)
				ring.markFinished()
				return
			}
			if self.sourceFormat == nil { self.sourceFormat = pcm.format }
			self.append(pcm, to: ring)
		}
	}

	/// Waits until playback can start without starving, and reports how long that
	/// took.
	///
	/// The host starts pulling audio the moment synthesis is requested, and
	/// re-synthesis has produced nothing yet. Measured against a live VoiceOver:
	/// short utterances starved the audio thread ~10 times and a 289-character
	/// help message starved it 955 times, with no lock contention and no format
	/// conversion -- so the glitching was never the ring or the converter, it was
	/// playback starting before there was anything to play.
	///
	/// Waits for the FIRST audio, not for the whole utterance: the render block
	/// waits for the rest, which trades ~0.4 s before a long sentence for ~0.17 s
	/// and keeps the gaps closed because nobody answers with silence.
	private func prebuffer(_ ring: AudioRing) -> Int {
		let started = Date()
		let deadline = started.addingTimeInterval(AVFoundationSynthesizer.prebufferBudget)
		while ring.available == 0, !ring.isFinished, Date() < deadline {
			usleep(2000)
		}
		return Int(Date().timeIntervalSince(started) * 1000)
	}

	private func append(_ pcm: AVAudioPCMBuffer, to ring: AudioRing) {
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
}
