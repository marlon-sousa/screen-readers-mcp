// ROLE: controller -- the orchestrator, and the class the spike did not have.
//
// ONE INPUT, TWO OUTPUTS. That is the shape of this provider, and the spike's
// single 300-line audio-unit class hid it:
//
//   in    VoiceOver hands over an utterance as SSML, before any audio exists
//   out   TEXT, through UtteranceSink, ALWAYS -- this is what the bridge reads
//   out   AUDIO, through Synthesizer into the AudioRing, only when not silent
//
// The text half does not depend on the audio half. It is emitted BEFORE
// re-synthesis starts, which is a deliberate change from the spike: there the
// one log line was written after the prebuffer wait, so every captured utterance
// reached the file about 0.2 s late. Nothing is lost by moving it -- the timing
// numbers that used to ride along are read at cancel, where they are final
// anyway.
//
// COLLABORATORS. Built by CaptureAudioUnit, which is this small hexagon's
// composition root. Holds four ports -- UtteranceSink, Synthesizer,
// VoiceCatalogue, CaptureModeSource -- and one entity, the AudioRing, because
// the ring is the thing the render block reads and somebody in the domain has to
// own it. Drives the Utterance, SsmlDocument and VoiceChoice entities.
//
// Unit-tested end to end against four fakes, with no audio device and no
// VoiceOver: that is the whole reason this class exists rather than the spike's
// monolith, and it is the side of the trade with a measured price -- six fixes
// that each cost a live round against the maintainer's own screen reader were
// provable only by running VoiceOver.
//
// THREADING. `capture` and `cancel` are called on whatever thread the system
// uses, and cancel arrives before every new utterance, so the sequence counter
// is taken under a lock. Nothing here touches the audio thread.

import Foundation
import os

public final class CaptureController {
	private let sink: UtteranceSink
	private let synthesizer: Synthesizer
	private let catalogue: VoiceCatalogue
	private let mode: CaptureModeSource
	private let ourVoiceIdentifier: String

	/// Owned here, handed to the synthesizer to fill and to the render block to
	/// drain. Public so the audio unit can capture it concretely.
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

	/// One utterance in.
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
		// ONE READ, ONE ANSWER: both what the bridge is asking for and the voice it
		// asked for it in. Read here rather than twice below, so a marker refreshed
		// mid-utterance cannot have one half of this utterance answered from one
		// session and the other half from the next.
		let directive = mode.directive
		let silent = directive.silent
		var fields: [String: FieldValue] = [
			"seq": .count(utterance.sequence),
			"ssml": .text(utterance.ssml),
			"text": .text(utterance.text),
			"voice": .text(utterance.requestingVoice),
			// Absent from VoiceOver's SSML in every measured utterance. Reported as
			// what it is rather than filled in, so a reader of the feed can tell
			// "the utterance said pt-BR" from "we assumed pt-BR".
			"utterance_language": utterance.language.map(FieldValue.text) ?? .text("<unknown>"),
			"silent": .flag(silent),
		]

		if silent {
			// The audio half simply does not happen. The ring is emptied and
			// declared over so the render block answers "complete" immediately
			// instead of waiting for samples that will never come.
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
		// Rule 0's lookup is BY IDENTIFIER and never through the list, so naming a
		// preferred voice makes the common path shorter rather than longer -- and
		// it is nil whenever the bridge named none, which is every utterance
		// spoken while no session holds the marker.
		let voice = choice.resolve(
			preferred: directive.preferredVoice.flatMap { catalogue.voice(identifier: $0) },
			languageDefault: catalogue.defaultVoice(for: choice.effectiveLanguage),
			candidates: catalogue.allVoices()
		)
		fields["passthrough_language"] = .text(choice.effectiveLanguage)
		// Named rather than inferred from how the audio sounds. This is the field
		// that would have caught the Arabic-reading-Portuguese bug in one glance.
		fields["passthrough_voice"] = .text(voice?.identifier ?? "<none>")
		sink.emit(CaptureEvent(kind: .synthesize, fields: fields))

		guard let voice else {
			// Nothing on this machine can re-speak it. Reported by name above; the
			// ring is closed so the utterance ends cleanly rather than hanging.
			ring.reset()
			ring.markFinished()
			return utterance
		}
		synthesizer.speak(utterance, as: voice, into: ring)
		return utterance
	}

	/// AN ORDINARY PATH, NOT A FAULT. VoiceOver cancels before every new
	/// utterance (spec 0041, A3), so this runs at least as often as `capture`
	/// does and must not read as an error anywhere downstream.
	///
	/// The counters are read BEFORE the synthesizer is stopped, because stopping
	/// truncates the ring and would report the state after the cut rather than
	/// the state that caused it.
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

	/// Pays the voice catalogue's one-off cost NOW, so that no utterance pays it.
	///
	/// MEASURED on macOS 15.0: the first `AVSpeechSynthesisVoice(language:)` in a
	/// process costs about 150 ms and every one after it costs 0.4 ms. The system
	/// relaunches this extension freely, so without this the FIRST utterance after
	/// every relaunch is 150 ms late -- and it is late in the one place a screen
	/// reader user notices, between pressing a key and hearing the answer.
	///
	/// Called off the request path, from the audio unit's construction. Its result
	/// is deliberately discarded: what is wanted is the framework's side effect,
	/// not the voice.
	public func warmUp() {
		_ = catalogue.defaultVoice(for: catalogue.currentLanguage)
	}

	/// Observations the audio unit makes about itself, funnelled through the same
	/// sink so there is ONE feed to read rather than two.
	public func report(_ event: CaptureEvent) {
		sink.emit(event)
	}
}
