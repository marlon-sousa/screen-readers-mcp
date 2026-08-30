// ROLE: adapter -- IMPLEMENTS the TextTyper domain port, over the EventPoster
// seam.
//
// BUILT BY: VoiceOverAdapterFactory. USED BY: the TypeText handler, through the
// port.
//
// IT HOLDS EVERY DECISION ON THIS EDGE: how a string becomes a sequence of
// events, how long a chunk may be, where a chunk may be cut, and what a key-down
// owes a key-up. Below it, `CGEventPoster` builds one event and posts it, and
// decides nothing.
//
// ============================================================================
// THE TARGET APPLICATION REWRITES WHAT WAS TYPED.
// ============================================================================
//
// Measured in spec 0041: two lines sent to TextEdit came back AUTOCAPITALIZED.
// The keystrokes went out exactly as given; the application's own text
// substitution changed them on the way in, before anything a screen reader would
// read had happened.
//
// So "send this keystroke" is NOT "this text arrives", and nothing in this
// bridge, its tests or its documentation may compare typed input with observed
// output as though they were the same string. That is written here, rather than
// in a spec somebody has to remember, because this is the file whoever writes
// that comparison will be reading. Autocapitalization is only the instance that
// was measured -- autocorrect, smart quotes, smart dashes and an application's
// own input filtering are all the same class, and they are per-application and
// per-user settings that no bridge can see or turn off. A check that needs to
// know what arrived must ask the APPLICATION what it now contains, or ask the
// reader to read it back, and compare THAT against what it expects.
//
// It is also why `typed` is a COUNT of what was sent and not an echo of it: the
// count is a fact this adapter can honestly report, and "the text that arrived"
// is not.
//
// UNICODE INJECTION, NOT A KEY SEQUENCE, WHICH IS protocol.md §5's REQUIREMENT.
// Every event carries a virtual key that means nothing and a Unicode payload
// that means everything, so the machine's keyboard layout is irrelevant and
// `typeText` types the same characters on a Dvorak or an ABNT2 keyboard as on a
// US one. Nothing here maps a character to a key, and nothing here interprets
// one: a newline is a newline, not Return, and this adapter never submits
// anything.

import VoiceOverBridgeDomain

public final class AccessibilityTextTyper: TextTyper {
	/// The most UTF-16 code units one event's payload may carry.
	///
	/// APPLE DOCUMENTS NO MAXIMUM, and 20 is the bound every implementation of
	/// this technique uses; longer payloads are reported to be dropped or
	/// truncated rather than to fail, which is the worst failure shape available
	/// -- a `typeText` that reports success and delivered half a sentence. The
	/// cost of being conservative is one extra event per 20 characters, on a path
	/// that is already a system call per keystroke.
	static let chunkLimit = 20

	private let poster: any EventPoster

	public init(poster: any EventPoster) {
		self.poster = poster
	}

	public func type(_ text: String) throws {
		guard !text.isEmpty else { return }
		for chunk in Self.chunks(of: text) {
			do {
				// BOTH HALVES CARRY THE PAYLOAD, and both halves are sent. An
				// application that inserts on key-down and one that inserts on key-up
				// would otherwise disagree about whether anything was typed, and a
				// key-down with no key-up leaves whatever is watching the event stream
				// believing a key is still held.
				try poster.post(unicode: chunk, keyDown: true)
				try poster.post(unicode: chunk, keyDown: false)
			} catch let failure as EventPostingFailure {
				throw TypingError(failure.description)
			}
		}
	}

	/// Cut `text` into payloads no longer than `chunkLimit` UTF-16 units.
	///
	/// Static and pure, so every rule below is an ordinary unit test rather than
	/// something only a live machine could exercise.
	///
	/// THE CUT IS BY GRAPHEME CLUSTER, NOT BY CODE UNIT, and that is the whole
	/// reason this is a function rather than a slice. A payload cut mid-cluster
	/// is not "slightly wrong": half a surrogate pair is not text at all, and a
	/// base letter separated from its combining accent arrives as two characters
	/// where the agent sent one -- which would then be blamed on the application's
	/// substitutions above, since that is exactly what they look like.
	///
	/// A SINGLE CLUSTER LONGER THAN THE LIMIT IS SENT WHOLE rather than split. A
	/// flag or a family emoji is one character to everyone who can see it, and an
	/// over-long payload that might be truncated is a better failure than a
	/// payload that is certainly nonsense.
	static func chunks(of text: String) -> [String] {
		var chunks: [String] = []
		var current = ""
		var currentUnits = 0
		for cluster in text {
			let units = String(cluster).utf16.count
			if currentUnits > 0, currentUnits + units > chunkLimit {
				chunks.append(current)
				current = ""
				currentUnits = 0
			}
			current.append(cluster)
			currentUnits += units
		}
		if !current.isEmpty { chunks.append(current) }
		return chunks
	}
}
