// ROLE: leaf adapter -- implements VoiceCatalogue over AVSpeechSynthesisVoice.
//
// It makes NO decisions: which voice to re-speak with is VoiceChoice's, in the
// domain, where it is tested. This file exists so that decision can be tested at
// all. No test file, per the repo's rule about leaves.
//
// `AVSpeechSynthesisVoice(language:)` is the system's DEFAULT voice for a
// language, and it is a different question from "a voice in the list whose
// language matches" -- see VoiceCatalogue's header for why the difference is
// load-bearing rather than a convenience.

import AVFoundation
import Foundation

public final class AVSpeechVoiceCatalogue: VoiceCatalogue {
	public init() {}

	public var currentLanguage: String {
		AVSpeechSynthesisVoice.currentLanguageCode()
	}

	public func defaultVoice(for language: String) -> AvailableVoice? {
		AVSpeechSynthesisVoice(language: language).map(AVSpeechVoiceCatalogue.describe)
	}

	public func allVoices() -> [AvailableVoice] {
		AVSpeechSynthesisVoice.speechVoices().map(AVSpeechVoiceCatalogue.describe)
	}

	private static func describe(_ voice: AVSpeechSynthesisVoice) -> AvailableVoice {
		AvailableVoice(identifier: voice.identifier, name: voice.name, language: voice.language)
	}
}
