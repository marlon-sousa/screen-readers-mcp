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

final class PassThrough {
	private let synthesizer = AVSpeechSynthesizer()
	private let ring: AudioRing
	private let outputFormat: AVAudioFormat
	private var converter: AVAudioConverter?
	private var converterInputFormat: AVAudioFormat?

	init(ring: AudioRing, outputFormat: AVAudioFormat) {
		self.ring = ring
		self.outputFormat = outputFormat
	}

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
	static func fallbackVoice(language: String?) -> AVSpeechSynthesisVoice? {
		let candidates = AVSpeechSynthesisVoice.speechVoices()
			.filter { !$0.identifier.hasSuffix(ourVoiceIdentifier) }
		guard let language else { return candidates.first }
		if let exact = candidates.first(where: { $0.language == language }) { return exact }
		let prefix = String(language.prefix(2))
		return candidates.first { $0.language.hasPrefix(prefix) } ?? candidates.first
	}

	/// Starts re-synthesis. Returns what it decided, so the decision is logged
	/// rather than inferred from how the audio sounds.
	func begin(ssml: String) -> (voice: String, language: String) {
		ring.reset()
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

		synthesizer.write(utterance) { [weak self] buffer in
			guard let self else { return }
			guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
				self.ring.markFinished()
				return
			}
			self.append(pcm)
		}
		return (voice?.identifier ?? "<none>", language ?? "<unknown>")
	}

	func cancel() {
		synthesizer.stopSpeaking(at: .immediate)
		ring.reset()
	}

	private func append(_ pcm: AVAudioPCMBuffer) {
		guard let converted = convert(pcm), let channel = converted.floatChannelData?[0] else { return }
		ring.append(channel, count: Int(converted.frameLength))
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
