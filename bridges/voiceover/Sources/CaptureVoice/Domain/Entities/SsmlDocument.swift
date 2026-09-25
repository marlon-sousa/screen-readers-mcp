// ROLE: entity, the SSML VoiceOver hands over, parsed into its plain text and its language if stated.
// USED BY: Utterance, and AVFoundationSynthesizer when AVSpeechUtterance refuses the SSML.
// VoiceOver on macOS 15 sends SSML with no xml:lang at all, so a nil language is the normal answer and
// must never license a default; VoiceChoice holds the fallback.

import Foundation

public struct SsmlDocument: Equatable, Sendable {
	/// Kept verbatim: its prosody carries the user's speech rate and VoiceOver's pitch changes.
	public let source: String
	public let text: String
	public let language: String?

	public init(_ ssml: String) {
		source = ssml
		text = SsmlDocument.plainText(of: ssml)
		language = SsmlDocument.language(of: ssml)
	}

	/// A string scan, not XMLParser, because malformed input must still be spoken rather than thrown on.
	static func language(of ssml: String) -> String? {
		guard let range = ssml.range(of: "xml:lang=\"") else { return nil }
		let rest = ssml[range.upperBound...]
		guard let end = rest.firstIndex(of: "\"") else { return nil }
		let value = String(rest[..<end])
		return value.isEmpty ? nil : value
	}

	static func plainText(of ssml: String) -> String {
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

	/// Unknown entities are left alone; `&amp;` is decoded last so that `&amp;lt;` yields `&lt;`.
	static func decodingEntities(_ text: String) -> String {
		guard text.contains("&") else { return text }
		var out = text
		for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
			out = out.replacingOccurrences(of: entity, with: character)
		}
		return out.replacingOccurrences(of: "&amp;", with: "&")
	}
}
