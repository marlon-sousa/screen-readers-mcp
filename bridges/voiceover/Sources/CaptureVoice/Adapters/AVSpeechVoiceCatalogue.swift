// ROLE: leaf adapter that implements VoiceCatalogue over AVSpeechSynthesisVoice.

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

	public func voice(identifier: String) -> AvailableVoice? {
		AVSpeechSynthesisVoice(identifier: identifier).map(AVSpeechVoiceCatalogue.describe)
	}

	public func allVoices() -> [AvailableVoice] {
		AVSpeechSynthesisVoice.speechVoices().map(AVSpeechVoiceCatalogue.describe)
	}

	private static func describe(_ voice: AVSpeechSynthesisVoice) -> AvailableVoice {
		AvailableVoice(identifier: voice.identifier, name: voice.name, language: voice.language)
	}
}
