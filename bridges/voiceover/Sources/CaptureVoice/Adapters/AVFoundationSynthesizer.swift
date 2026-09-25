// ROLE: adapter that implements the Synthesizer port with AVFoundation.
// BUILT BY: CaptureAudioUnit, which also passes it the format the host settled on.
// USED BY: CaptureController, through the port; it writes into the AudioRing it is handed.
// Everything VoiceOver says arrives here as SSML: if this does not hand back intelligible audio,
// the user cannot hear the computer at all.
// The statistics are written on the synthesis queue and read by `cancel` without a lock; they are diagnostics only.

import AVFoundation
import Foundation

/// Sound only because each value is handed over exactly once, to one serial queue, and the sender never
/// touches it again.
private struct Handoff<Value>: @unchecked Sendable {
	let value: Value
}

/// When the zero-length end buffer never arrives, the delegate still finishes the utterance, or the host
/// pulls silence from a ring that will never fill.
private final class CompletionWatcher: NSObject, AVSpeechSynthesizerDelegate {
	let onEnd: () -> Void
	init(onEnd: @escaping () -> Void) { self.onEnd = onEnd }
	func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { onEnd() }
	func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { onEnd() }
}

public final class AVFoundationSynthesizer: Synthesizer {
	public static let prebufferBudget: TimeInterval = 2.0

	private var synthesizer = AVSpeechSynthesizer()
	/// runningboardd parks this extension at PRIO_DARWIN_BG, so the work declares itself interactive.
	private let synthesisQueue = DispatchQueue(
		label: "org.screen-readers-mcp.voiceover.synthesis", qos: .userInteractive)
	/// The host settles the real format at allocateRenderResources; converting to the declared one instead is
	/// heard as glitching and wrong pitch, never reported as an error.
	private var outputFormat: AVAudioFormat
	private var converter: AVAudioConverter?
	private var converterInputFormat: AVAudioFormat?
	private var sourceFormat: AVAudioFormat?
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

	public func adoptOutputFormat(_ format: AVAudioFormat) {
		guard format != outputFormat else { return }
		outputFormat = format
		converter = nil
		converterInputFormat = nil
	}

	public var currentOutputFormat: AVAudioFormat { outputFormat }

	/// About 6 ms at the output rate; every utterance ends in a cancel, and each one clicks without the ramp.
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
			// Malformed SSML must still be spoken, or the reader goes mute for that sentence.
			spoken = AVSpeechUtterance(string: utterance.text)
		}
		// Leaving the voice nil is safe: on macOS 15 an ordinary AVSpeechSynthesizer client cannot use our voice
		// (it fails with retryFallbackVoice), so the system default is never us.
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
		// One synthesizer per utterance: VoiceOver on macOS 15 cancels before every utterance, and a shared instance
		// asked to stop and then write again stalled for seconds, starving one 191-character utterance 810 times.
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

	/// Waits for the first audio only, and returns how long that took. VoiceOver on macOS 15 starts pulling
	/// at once; playing before any audio existed starved a 289-character message 955 times.
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
