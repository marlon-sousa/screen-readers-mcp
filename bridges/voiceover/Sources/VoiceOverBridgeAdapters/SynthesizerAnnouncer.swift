// ROLE: adapter -- IMPLEMENTS the Announcer domain port. It decides which voice
// the bridge speaks in, and hands the words to the SpeechOut seam.
//
// BUILT BY: Wiring, once per process. USED BY: the Announce and AskUser
// controllers, and by `HumanWarning` on behalf of `pressGesture` and `typeText`
// -- all through the port.
// HOLDS: the PublishedVoices seam (what this machine can speak with) and the
// SpeechOut seam (the speaking itself).
//
// ============================================================================
// IT SPEAKS OUTSIDE VOICEOVER ENTIRELY, WHICH IS THE WHOLE POINT.
// ============================================================================
//
// A silent session mutes the reader by having the capture voice render nothing,
// so anything said THROUGH the reader is exactly what the human cannot hear.
// This goes around it: an ordinary system synthesizer in this process, which the
// suppression has no reach into. That is a cleaner bypass than NVDA's, where the
// same claim rests on the interception being a filter in front of a synth that
// is still loaded -- and it is why `pressGesture`'s and `typeText`'s `announce`
// field is honourable here at all.
//
// AND IT EXCLUDES OUR OWN VOICE BY SUFFIX, WHICH IS THE ONE WAY THIS COULD FAIL
// SILENTLY. If the announcer picked the capture voice, the announcement would go
// into the very extension that is rendering silence, and it would be silence
// talking to itself -- an `announce` that returned `ok` while the room stayed
// quiet, in the one mode where it is the human's only channel. The match is by
// SUFFIX and never by equality, because the system publishes our voice as the
// extension's bundle id followed by the one the audio unit declared, so the
// published string never equals what the unit said (spec 0041 A1, spec 0047
// finding 17). That is the same rule `PluginKitProviderLifecycle` matches ours
// by, and it is deliberately the same constant.
//
// THE LANGUAGE PREFERENCE IS A PREFERENCE, NOT A REQUIREMENT. Voice identifiers
// are opaque strings that happen to carry a locale (`com.apple.voice.compact.
// pt-BR.Luciana`), so matching on one is a heuristic: it is worth doing because a
// warning spoken in the wrong language is a warning nobody acts on, and it is
// never worth failing over, so an unmatched preference falls through to any
// voice that is not ours.

import VoiceOverBridgeDomain

public final class SynthesizerAnnouncer: Announcer {
	private let voices: any PublishedVoices
	private let out: any SpeechOut
	private let excludedSuffix: String
	private let preferredLanguage: String

	/// The chosen voice, resolved once. Nil means "not yet asked"; `.some(nil)`
	/// means "asked, and this machine offered nothing but our own voice", which is
	/// a real answer and not a reason to ask again on every announcement.
	private var resolved: String??

	/// `preferredLanguage` is a BCP-47 tag as the system spells it (`pt-BR`),
	/// read from the environment by Wiring -- the one place in this bridge that
	/// reads the environment -- so everything here is a pure function of values.
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

	/// Which voice to announce in, resolved on first use and kept.
	///
	/// KEPT, because the list is a property of the machine and re-reading it per
	/// announcement would pay a framework enumeration for an answer that does not
	/// change -- and because an announcement made in a different voice each time
	/// would be a worse thing to listen to than one made in the wrong voice once.
	func voice() -> String? {
		if let resolved { return resolved }
		let chosen = SynthesizerAnnouncer.choose(
			from: voices.identifiers(), excluding: excludedSuffix, preferring: preferredLanguage)
		resolved = .some(chosen)
		return chosen
	}

	/// The rule, as a pure function so it is testable without a synthesizer.
	///
	/// Ours is dropped first and unconditionally; among what is left, the exact
	/// language tag wins, then the base language, then whatever is there. Nil when
	/// the machine published nothing else at all -- in which case the leaf lets the
	/// system choose, which is the only remaining option and still not our voice
	/// unless a human has made it their system default.
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
