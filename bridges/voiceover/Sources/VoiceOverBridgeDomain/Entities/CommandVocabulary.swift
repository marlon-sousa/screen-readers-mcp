// ROLE: entity -- what counts as a gesture id on this reader, and what is refused
// before the machine is touched.
//
// PURE. USED BY: the PressGesture handler, which classifies the WHOLE batch
// before dispatching any of it -- see below.
//
// ============================================================================
// A GESTURE ID HERE IS A KEYSTROKE. THERE IS NO SECOND ROUTE -- 13.31.
// ============================================================================
//
// protocol.md §5 says gesture id syntax is reader-specific and passes through
// opaquely: it is "the reader's own user-facing command notation, as its
// documentation writes it". On NVDA that notation IS keystrokes (`NVDA+f7`), and
// on this reader it now is too, for one reason:
//
//   NO VOICEOVER USER CAN DISPATCH A COMMAND BY NAME.
//
// A person presses VO-M. To reach an act with no key at all they open the
// Commands menu -- `vo+h` pressed twice -- type its name and press Enter, which is
// keystrokes and typed text and nothing else. So a session standing in for a user
// presses keys, always, and this file has one vocabulary rather than two.
//
// THIS FILE USED TO CLASSIFY BETWEEN THEM, AND THE HISTORY IS WORTH THE PARAGRAPH
// because it is the same mistake arriving from three directions. 13.7 shipped the
// command-name route as the only one. 13.17 added keystrokes beside it, after a
// true statement about this ENTITY -- "this bridge sends command names" -- had
// been read as a fact about the PLATFORM for four entries while a blind user's
// commonest act stayed unreachable (spec 0048 §1.1). 13.25 then found the
// remaining route reporting SUCCESS on chords a real user was stuck on, because a
// command dispatched inside the reader never passes the application under test --
// so the route was hiding the defect class this tool exists to find, and it was
// demoted to an automation convenience. 13.31 finishes it: a convenience no user
// has, bought by asking a blind person to leave "Allow VoiceOver to be controlled
// with AppleScript" on -- which lets ANY process drive their screen reader -- is
// not a convenience worth its price. Spec 0055.
//
// ============================================================================
// THREE RULES DECIDE, AND THE FIRST IS THE SOURCE PREFIX -- 13.19.
// ============================================================================
//
// 1. A SOURCE PREFIX, if there is one, settles it outright. `kb:h` is the
//    keyboard's `h`. The prefix is NVDA's own -- lane 1 strips exactly this shape
//    in `adapters/keyboard_gesture_name.bare_key_name` -- and spec 0018 reserved
//    the namespace for it. Everything up to and including the first `:` is the
//    source, and `kb` is the only one there is.
// 2. Otherwise `VO-D` is refused by name, because this bridge writes a keystroke
//    with `+`.
// 3. Otherwise a `+` means a keystroke, and ANYTHING ELSE IS REFUSED -- which is
//    the rule 13.31 changed. It used to say "anything else is a command name".
//
// SO A LONE TOKEN NEEDS ITS PREFIX: `h` is refused and `kb:h` is the letter key.
// That is deliberately unchanged from 13.19, when a bare `h` really was ambiguous,
// and it is kept now that it is not -- because `Gesture.described` spells a
// modifier-less keystroke `kb:h` in the transcript, and a transcript whose lines
// cannot be fed back in is not doing its job. It is also lane 1's spelling, so one
// notation means one thing on both readers.
//
// A PHRASE IS THE ONE REFUSAL THAT HAS TO TEACH. An id with a space in it was a
// command name until this entry, so an agent carrying guidance from any earlier
// build will send one. It is answered with the route a person actually takes --
// the key, or the Commands menu -- rather than with "unknown gesture", which
// would leave the agent believing the act is unreachable.
//
// THE DISCRIMINATOR BEHIND ALL THREE IS THE SPACE RULE, and it is the one this
// file already lived by. A separator -- `:`, `+` or `-` -- counts as notation
// only in an id with NO SPACES AT ALL.

import Foundation

/// A gesture id this reader cannot accept, and why.
///
/// Carries the id so the message can quote it back: an agent sending a batch
/// learns WHICH one was refused without counting positions.
public struct GestureIdRefused: Error, Equatable, CustomStringConvertible {
	public let gesture: String
	public let reason: String

	public init(gesture: String, reason: String) {
		self.gesture = gesture
		self.reason = reason
	}

	public var description: String {
		"'\(gesture)' is not a gesture id on this reader: \(reason)"
	}
}

public enum CommandVocabulary {
	/// The one gesture source this bridge knows, and it is NVDA's spelling.
	///
	/// Public because the guidance document, the tests and `identifier(for:)` all
	/// have to agree about it, and a second spelling of a notation is how a
	/// notation stops being one.
	public static let keyboardSource = "kb"

	/// How a person reaches an act that has no key of its own.
	///
	/// ONE STRING, because it is the answer to three different refusals below and
	/// a route spelled three ways is a route an agent has to reconcile. It is also
	/// the whole substitute for the deleted command-name channel, so it says what
	/// a user does rather than what this bridge lost.
	public static let commandsMenuRoute =
		"an act with no key of its own is reached the way a person reaches it: open the Commands "
		+ "menu with \"vo+h\" pressed twice, type the act's name with type_text, and press "
		+ "\"kb:enter\""

	/// Classify a gesture id, or refuse it by name with its reason.
	///
	/// Every accepted id comes back PARSED, so the id's contents are the caller's
	/// mistake to hear about here rather than the machine's to discover later.
	public static func classify(
		_ gesture: String, readerModifier: ModifierSetting
	) throws -> Keystroke {
		let trimmed = gesture.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw GestureIdRefused(
				gesture: gesture,
				reason: "it is empty -- this reader's gestures are keystrokes, such as \"vo+m\", "
					+ "\"command+l\" and \"kb:h\""
			)
		}
		if let (source, rest) = sourcePrefix(of: trimmed) {
			guard source == keyboardSource else {
				throw GestureIdRefused(gesture: trimmed, reason: reasonNoSuchSource(source))
			}
			return try keystroke(rest, quoting: trimmed, readerModifier)
		}
		guard !isReaderModifierNotation(trimmed) else {
			throw GestureIdRefused(gesture: trimmed, reason: reasonHyphenShorthand(trimmed))
		}
		guard isKeystrokeNotation(trimmed) else {
			throw GestureIdRefused(gesture: trimmed, reason: reasonNotAKeystroke(trimmed))
		}
		return try keystroke(trimmed, quoting: trimmed, readerModifier)
	}

	/// What the bridge UNDERSTOOD, which is what the transcript and the `pressed`
	/// entry report -- the keystroke's canonical spelling, so an agent that wrote
	/// `Command+L` is told `command+l` went out rather than being echoed its own
	/// text back.
	///
	/// THE SOURCE PREFIX APPEARS EXACTLY WHERE DROPPING IT WOULD LIE. A keystroke
	/// with modifiers spells itself `command+l`, which is lane 1's documented form
	/// and needs nothing added; one with no modifiers spells itself `kb:h`, which
	/// is the id that would be accepted if it were sent back in.
	///
	/// A MULTI-KEY CHORD WITH NO MODIFIERS TAKES THE PREFIX TOO -- 13.22 --
	/// `kb:leftArrow+rightArrow`. It would round-trip without one, since the `+`
	/// classifies it, and the rule stays "no modifiers, so say which vocabulary"
	/// rather than growing a second clause.
	///
	/// A FREE FUNCTION ON THE VOCABULARY RATHER THAN A PROPERTY ON `Keystroke`,
	/// because it is a fact about this reader's ID NOTATION and not about the keys:
	/// `Keystroke.described` is the chord, and the `kb:` in front of it is this
	/// file's business.
	public static func identifier(for keystroke: Keystroke) -> String {
		guard keystroke.modifiers.isEmpty else { return keystroke.described }
		return "\(keyboardSource):\(keystroke.described)"
	}

	/// Why an ordinary phrase is not a gesture id any more, and what to do instead.
	///
	/// THIS IS THE ONE REFUSAL IN THE FILE THAT EXISTS FOR AN AGENT'S MEMORY rather
	/// than for a typo. Until 13.31 this id was dispatched to the reader by name,
	/// so a model carrying guidance from an earlier build -- or from anything ever
	/// written about this bridge -- will send one, and it must not conclude that the
	/// act is unreachable. It is reachable; it takes the key, or the menu a person
	/// uses when there is no key.
	/// THE PREFIX IS OFFERED ONLY TO AN ID THAT COULD BE A KEY, and that clause was
	/// wrong in the first build of this entry -- found on 13.31's own live run, by
	/// sending `go to menu bar` and being told to try `kb:go to menu bar`, which is
	/// a malformed keystroke and could never work. A refusal that names an id the
	/// next call will also refuse costs the agent a round trip and teaches it a
	/// spelling that does not exist. So a PHRASE is sent to the key and the menu; a
	/// LONE TOKEN, which is what `h` is, is additionally told how to say it means
	/// the key.
	private static func reasonNotAKeystroke(_ gesture: String) -> String {
		let base =
			"it reads as one of the reader's own command names, and this bridge no longer dispatches "
			+ "those -- no VoiceOver user can type a command name, so neither does a session standing "
			+ "in for one. Press the KEY the act is bound to instead (\"vo+m\" for the menu bar, "
			+ "\"vo+f7\" for the time and date); \(commandsMenuRoute)"
		guard !gesture.contains(" ") else { return base }
		return base
			+ ". If you meant a single key, say so with the source prefix: "
			+ "\"\(keyboardSource):\(gesture)\""
	}

	/// Why VoiceOver's own `VO-D` shorthand is refused, and what to write instead.
	///
	/// THE REFUSAL SURVIVES 13.25 AND 13.31; ITS REASON HAS NOW CHANGED TWICE. It
	/// used to say that `VO` is whatever the person bound it to and that this bridge
	/// would not guess -- no longer true, since the bridge reads what it is bound to
	/// and resolves it. What is refused is the SEPARATOR, for a much smaller reason:
	/// Apple also writes `VO-Shift-M`, so accepting the hyphen means maintaining a
	/// second complete notation -- its own modifier order, its own refusals, its own
	/// tests -- for an id whose fix is one token long.
	///
	/// 13.31 removed its last clause, which offered the English command name as an
	/// alternative. There is no such route now.
	private static func reasonHyphenShorthand(_ gesture: String) -> String {
		"it is VoiceOver's own hyphen shorthand, and this bridge writes a keystroke with \"+\" "
			+ "instead -- one notation, the same one the other reader in this contract uses. Write "
			+ "\"\(gesture.replacingOccurrences(of: "-", with: "+").lowercased())\". \"vo\" IS a "
			+ "modifier here: this bridge reads what the person has bound their VoiceOver modifier "
			+ "to and presses that"
	}

	// -- the pieces --------------------------------------------------------------

	/// Parse a keystroke, re-quoting the refusal against the id the agent SENT.
	///
	/// A `kb:h` that fails must say `kb:h` and not `h`, or the agent is left
	/// looking for an id it never wrote.
	private static func keystroke(
		_ id: String, quoting sent: String, _ readerModifier: ModifierSetting
	) throws -> Keystroke {
		do {
			return try Keystroke.parse(id, readerModifier: readerModifier)
		} catch let malformed as KeystrokeMalformed {
			throw GestureIdRefused(gesture: sent, reason: malformed.reason)
		}
	}

	/// The source prefix and what follows it, or nil when the id carries none.
	///
	/// Everything up to and including the FIRST `:` is the source, which is lane
	/// 1's rule (`bare_key_name`) rather than one invented here.
	///
	/// THE SPACE RULE GUARDS THE SOURCE ITSELF, NOT THE WHOLE ID. A source is a
	/// single token, so a phrase before the colon means the colon is part of an
	/// ordinary phrase -- which is refused by `reasonNotAKeystroke`, with the route
	/// a person takes -- while a phrase AFTER it is a malformed keystroke, because
	/// the agent has already said which vocabulary it meant and the answer to a
	/// mistake is to name it rather than to guess past it.
	private static func sourcePrefix(of gesture: String) -> (source: String, rest: String)? {
		guard let colon = gesture.firstIndex(of: ":") else { return nil }
		let source = String(gesture[gesture.startIndex..<colon])
		guard !source.contains(" ") else { return nil }
		return (source: source.lowercased(), rest: String(gesture[gesture.index(after: colon)...]))
	}

	/// Why a source is not one here, answering the qualified form by name.
	///
	/// `kb(laptop):` is a real NVDA id shape and an agent that has driven that
	/// reader will write it. It selects one of NVDA's own gesture MAPS, which has
	/// no counterpart here -- the layout that matters on this machine is the
	/// system's own, and it is read live at press time (spec 0048 §2.4) rather
	/// than chosen by an id.
	private static func reasonNoSuchSource(_ source: String) -> String {
		if source.hasPrefix("\(keyboardSource)(") {
			return "this bridge has no gesture maps to qualify a source with. NVDA's "
				+ "\"kb(laptop):\" picks one of its own keyboard layouts; here the layout that "
				+ "matters is the machine's own and it is read live when the key is pressed. Send "
				+ "\"kb:\" with no qualifier"
		}
		return "'\(source):' is not a gesture source this bridge knows. It knows one, \"kb:\", which "
			+ "marks an id with no modifiers as a key -- as in \"kb:h\", the letter key an ordinary "
			+ "user presses with single-key Quick Nav on. An id that holds modifiers needs no source: "
			+ "\"vo+m\", \"command+l\""
	}

	/// Whether an id is written as a keystroke: `+`-joined, and one token.
	///
	/// A `+` is how NVDA, the contract's other reader, writes every gesture. The
	/// space rule is what keeps a phrase out: a keystroke is a single token, so an
	/// id with a space in it is not one whatever else it contains.
	///
	/// A LONE KEY IS NOT ONE OF THESE, and 13.31 left that alone on purpose. It was
	/// 13.17's amendment 5, kept through 13.19 because a bare `h` was ambiguous
	/// between the two vocabularies; the ambiguity is gone and the rule stays,
	/// because `kb:h` is what the transcript writes and what lane 1 writes, and a
	/// notation that accepts a spelling it never emits is one an agent has to learn
	/// twice.
	private static func isKeystrokeNotation(_ gesture: String) -> Bool {
		gesture.contains("+") && !gesture.contains(" ")
	}

	/// Whether an id is VoiceOver's own hyphen shorthand (`VO-D`).
	///
	/// THE HYPHEN RULE HAS TO SURVIVE HYPHENATED PHRASES: "toggle single-key quick
	/// nav on or off" is one of the acts a person can ask for by name in the
	/// Commands menu, and an agent may well send it here. What separates them is the
	/// space, exactly as above -- so a hyphen is this notation only in an id with no
	/// spaces at all.
	private static func isReaderModifierNotation(_ gesture: String) -> Bool {
		gesture.contains("-") && !gesture.contains(" ")
	}
}
