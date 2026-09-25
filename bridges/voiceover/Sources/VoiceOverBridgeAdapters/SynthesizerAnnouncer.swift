// ROLE: adapter implementing the Announcer port; it picks the voice and hands the words to the SpeechOut seam.
// BUILT BY: Wiring, once per process.
// USED BY: the Announce and AskUser controllers, and `HumanWarning` for `pressGesture` and `typeText`, through the port.
// Speaks through a system synthesizer in this process, which a silent session's suppression cannot reach.
// Excludes the capture voice by suffix; picking it would send an announcement into the extension that is rendering silence.

import VoiceOverBridgeDomain

public final class SynthesizerAnnouncer: Announcer {
	private let voices: any PublishedVoices
	private let out: any SpeechOut
	private let excludedSuffix: String
	private let preferredLanguage: String

	/// Nil means not yet asked; `.some(nil)` means this machine offers nothing but our own voice.
	private var resolved: String??

	/// `preferredLanguage` is a BCP-47 tag as the system spells it, such as `pt-BR`.
	public init(
		voices: any PublishedVoices,
		out: any SpeechOut,
		excludingSuffix: String,
		preferredLanguage: String
	) {
		self.voices = voices
		self.out = out
		self.excludedSuffix = excludingSuffix
		self.preferredLanguage = preferredLanguage
	}

	public func announce(_ text: String) throws {
		do {
			try out.speak(text, voiceIdentifier: voice())
		} catch let failure as AnnouncerError {
			throw failure
		} catch {
			throw AnnouncerError(
				"the bridge's own synthesizer refused to speak: "
					+ ((error as? any CustomStringConvertible)?.description ?? String(describing: error)))
		}
	}

	// -- choosing the voice ----------------------------------------------------

	func voice() -> String? {
		if let resolved { return resolved }
		let chosen = SynthesizerAnnouncer.choose(
			from: voices.identifiers(), excluding: excludedSuffix, preferring: preferredLanguage)
		resolved = .some(chosen)
		return chosen
	}

	/// Ours is dropped first, then the exact language tag wins, then the base language, then anything; nil when nothing else is published, and the leaf lets the system choose.
	static func choose(from identifiers: [String], excluding suffix: String, preferring language: String)
		-> String?
	{
		let candidates = identifiers.filter { !$0.hasSuffix(suffix) }
		guard !candidates.isEmpty else { return nil }
		if let exact = candidates.first(where: { $0.contains(".\(language).") }) {
			return exact
		}
		let base = language.split(separator: "-").first.map(String.init) ?? language
		if let close = candidates.first(where: { $0.contains(".\(base)-") || $0.contains(".\(base).") }) {
			return close
		}
		return candidates.first
	}
}
