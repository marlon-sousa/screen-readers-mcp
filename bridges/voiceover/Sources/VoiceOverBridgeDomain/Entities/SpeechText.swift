// ROLE: entity -- PROCESSING. The SSML the capture voice was handed, rendered
// into the plain words an entry carries.
//
// Pure, and a namespace rather than a value because it holds no state: the one
// place `<prosody>`, `<break>` and XML entities are decided for this half.
// USED BY: ContainerFileSpeechSource, which parses the feed's JSON and asks this
// what the utterance SAYS. Nothing else renders speech text.
//
// IT DELIBERATELY REPEATS `CaptureVoice`'s `SsmlDocument`, AND THE DUPLICATION IS
// THE POINT. The extension runs inside the user's screen reader and depends on
// nothing of ours by hard rule, so nothing of ours may reach into it either; the
// two are separate processes that meet at a file. The feed's line carries the
// extension's own rendering in a `text` field, and this half re-derives from the
// `ssml` field instead, so what an agent reads back is decided by ONE tested
// entity on this side of the door rather than by whatever version of the
// extension happens to be installed. `SsmlDocument`'s own header says the same
// thing from the other side: "the bridge parses it for itself".
//
// SCANNED, NOT PARSED. An XML parser throws on the malformed input this route is
// not entitled to reject -- whatever the reader said has to be readable back --
// and a scan cannot fail. The cost is that a `<` inside a text node would be
// read as a tag; VoiceOver's SSML escapes it as `&lt;`, which is exactly why the
// five predefined entities are decoded after the tags come out and not before.

import Foundation

public enum SpeechText {
	/// The words, with tags removed, entities decoded and the ends trimmed.
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

	/// The five predefined XML entities, and only those.
	///
	/// An unknown entity is left ALONE rather than guessed at: `&amp;` read back
	/// as "amp" is a defect and a mangled character reference is a worse one.
	/// `&amp;` is decoded LAST, so `&amp;lt;` yields the literal `&lt;` rather
	/// than a less-than sign.
	static func decodingEntities(_ text: String) -> String {
		guard text.contains("&") else { return text }
		var out = text
		for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
			out = out.replacingOccurrences(of: entity, with: character)
		}
		return out.replacingOccurrences(of: "&amp;", with: "&")
	}
}
