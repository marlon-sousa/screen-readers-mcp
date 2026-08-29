// ROLE: entity -- PROCESSING. The SSML VoiceOver hands us, parsed into the two
// things anything downstream wants: the plain text, and the language if it is
// stated.
//
// Pure. Built by Utterance; used by CaptureController through it, and by
// AVFoundationSynthesizer when AVSpeechUtterance refuses the SSML and the text
// still has to be audible.
//
// THE FINDING THIS FILE CARRIES: VoiceOver's SSML has NO xml:lang AT ALL.
// Measured against a live reader on macOS 15.0 -- it carries <prosody> and
// <break> and no language anywhere. So `language == nil` is the NORMAL answer
// here, not an edge case, and it must never be read as licence to pick a
// default: doing exactly that is how this route read Portuguese aloud in Arabic
// for several minutes. VoiceChoice is where the honest fallback lives.

import Foundation

public struct SsmlDocument: Equatable, Sendable {
	/// Exactly what the system handed over. Kept verbatim because it carries
	/// PROSODIC MEANING the words do not -- the outer rate is the user's speech
	/// rate and an inner pitch is VoiceOver lowering its voice for a column
	/// header -- and the bridge (entry 13.5) parses it for itself.
	public let source: String
	/// The words, with tags removed and the five predefined XML entities decoded.
	public let text: String
	/// `xml:lang`, when the document states one. Usually nil; see the header.
	public let language: String?

	public init(_ ssml: String) {
		source = ssml
		text = SsmlDocument.plainText(of: ssml)
		language = SsmlDocument.language(of: ssml)
	}

	/// Read as a string rather than with an XML parser, deliberately.
	///
	/// This runs inside the user's screen reader, once per utterance, on the
	/// thread that must promptly start synthesis. A scan is a few microseconds
	/// and cannot fail; XMLParser allocates a parser and a delegate per utterance
	/// and THROWS on the malformed input this route is not entitled to reject --
	/// whatever arrives has to be spoken.
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

	/// The five predefined XML entities, and only those.
	///
	/// An unknown entity is left ALONE rather than guessed at: `&amp;` spoken as
	/// "amp" is a defect, and a mangled character reference is a worse one. `&amp;`
	/// is decoded last so that `&amp;lt;` yields the literal `&lt;` rather than a
	/// less-than sign.
	static func decodingEntities(_ text: String) -> String {
		guard text.contains("&") else { return text }
		var out = text
		for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
			out = out.replacingOccurrences(of: entity, with: character)
		}
		return out.replacingOccurrences(of: "&amp;", with: "&")
	}
}
