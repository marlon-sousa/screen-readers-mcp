// ROLE: controller: one utterance in as SSML; its text always out through UtteranceSink, and its audio
// through Synthesizer into the AudioRing only when not silent.
// BUILT BY: CaptureAudioUnit, this module's composition root.
// The text is emitted before re-synthesis starts, so the feed never waits on the prebuffer.
// `capture` and `cancel` run on whatever thread the system uses, so the sequence counter is locked.

import Foundation
import os

public final class CaptureController {
	private let sink: UtteranceSink
	private let synthesizer: Synthesizer
	private let catalogue: VoiceCatalogue
	private let mode: CaptureModeSource
	private let ourVoiceIdentifier: String

	/// Public so the audio unit can capture it concretely.
	public let ring: AudioRing

	private let counter = OSAllocatedUnfairLock(initialState: 0)

	public init(
		sink: UtteranceSink,
		synthesizer: Synthesizer,
		catalogue: VoiceCatalogue,
		mode: CaptureModeSource,
		ring: AudioRing,
		ourVoiceIdentifier: String
	) {
		self.sink = sink
		self.synthesizer = synthesizer
		self.catalogue = catalogue
		self.mode = mode
		self.ring = ring
		self.ourVoiceIdentifier = ourVoiceIdentifier
	}

	@discardableResult
	public func capture(ssml: String, requestedBy voiceIdentifier: String) -> Utterance {
		let utterance = Utterance(
			sequence: counter.withLock { value in
				value += 1
				return value
			},
			ssml: ssml,
			requestingVoice: voiceIdentifier
		)
		// Read once, so a marker refreshed mid-utterance cannot answer the two halves from different sessions.
		let directive = mode.directive
		let silent = directive.silent
		var fields: [String: FieldValue] = [
			"seq": .count(utterance.sequence),
			"ssml": .text(utterance.ssml),
			"text": .text(utterance.text),
			"voice": .text(utterance.requestingVoice),
			// Usually absent (see SsmlDocument), so it is reported as unknown, never filled in.
			"utterance_language": utterance.language.map(FieldValue.text) ?? .text("<unknown>"),
			"silent": .flag(silent),
		]

		if silent {
			// Declared over so the render block answers "complete" at once instead of waiting for samples.
			ring.reset()
			ring.markFinished()
			sink.emit(CaptureEvent(kind: .synthesize, fields: fields))
			return utterance
		}

		let choice = VoiceChoice(
			requestedLanguage: utterance.language,
			systemLanguage: catalogue.currentLanguage,
			ourIdentifierSuffix: ourVoiceIdentifier
		)
		let preferred = directive.preferredVoice.flatMap { catalogue.voice(identifier: $0) }
		if let asked = directive.preferredVoice {
			fields["passthrough_voice_asked"] = .text(asked)
			fields["passthrough_voice_in_catalogue"] = .text(preferred == nil ? "no" : "yes")
		}
		let voice = choice.resolve(
			preferred: preferred,
			languageDefault: catalogue.defaultVoice(for: choice.effectiveLanguage),
			candidates: catalogue.allVoices()
		)
		fields["passthrough_language"] = .text(choice.effectiveLanguage)
		// The voice asked for, never the one heard: no API reports which voice rendered, and on macOS 15 the system
		// silently substituted Luciana for an Eloquence voice that was advertised but not installed.
		fields["passthrough_voice_requested"] = .text(voice?.identifier ?? "<none>")
		sink.emit(CaptureEvent(kind: .synthesize, fields: fields))

		guard let voice else {
			// Nothing here can re-speak it; the ring is closed so the utterance ends rather than hangs.
			ring.reset()
			ring.markFinished()
			return utterance
		}
		synthesizer.speak(utterance, as: voice, into: ring)
		return utterance
	}

	/// The counters are read before the synthesizer stops, because stopping truncates the ring.
	public func cancel() {
		let stats = synthesizer.statistics()
		var fields: [String: FieldValue] = [
			"contention_drops": .count(ring.contentionDrops),
			"underruns": .count(ring.underruns),
			"overflow_drops": .count(ring.overflowDrops),
			"drained_frames": .count(ring.drainedTotal),
			"ring_left": .count(ring.available),
			"producer_finished": .flag(ring.isFinished),
			"prebuffer_ms": .count(stats.prebufferMilliseconds),
			"cb_count": .count(stats.callbackCount),
			"cb_first_ms": .count(stats.firstCallbackMilliseconds),
			"cb_max_gap_ms": .count(stats.maxGapMilliseconds),
			"cb_frames": .count(stats.totalFrames),
			"cb_span_ms": .count(stats.spanMilliseconds),
		]
		if let rate = stats.sourceSampleRate { fields["source_rate"] = .number(rate) }
		if let channels = stats.sourceChannels { fields["source_channels"] = .count(channels) }
		if let converted = stats.converted { fields["converted"] = .flag(converted) }
		sink.emit(CaptureEvent(kind: .cancel, fields: fields))
		synthesizer.cancel()
	}

	/// On macOS 15 the first `AVSpeechSynthesisVoice(language:)` in a process costs about 150 ms and each
	/// later one 0.4 ms, and the system relaunches this extension freely.
	public func warmUp() {
		_ = catalogue.defaultVoice(for: catalogue.currentLanguage)
	}

	public func report(_ event: CaptureEvent) {
		sink.emit(event)
	}
}
