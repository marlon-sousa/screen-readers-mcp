// ROLE: entity -- renders the SSML the capture voice was handed into the plain words an entry carries.
// USED BY: ContainerFileSpeechSource; nothing else renders speech text.
// Duplicates CaptureVoice's SsmlDocument on purpose: the extension shares no code with the bridge in either direction.
// Scanned, not parsed, so malformed SSML still reads back; entities are decoded after tags because VoiceOver escapes `<` as `&lt;`.

import Foundation

public enum SpeechText {
	public static func plain(ofSsml ssml: String) -> String {
		var result = ""
		var inTag = false
		for character in ssml {
			if character == "<" {
				inTag = true
			} else if character == ">" {
				inTag = false
			} else if !inTag {
				result.append(character)
			}
		}
		return decodingEntities(result).trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// `&amp;` is decoded last, so `&amp;lt;` yields the literal `&lt;`; an unknown entity is left alone.
	static func decodingEntities(_ text: String) -> String {
		guard text.contains("&") else { return text }
		var out = text
		for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
			out = out.replacingOccurrences(of: entity, with: character)
		}
		return out.replacingOccurrences(of: "&amp;", with: "&")
	}
}
