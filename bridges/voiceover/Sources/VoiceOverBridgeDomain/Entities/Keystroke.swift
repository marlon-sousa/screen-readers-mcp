// ROLE: entity -- what a keystroke id MEANS, parsed once, before anything is
// posted at the machine.
//
// PURE, and it owns the modifier and named-key vocabulary. USED BY:
// CommandVocabulary, which decides whether an id is one of these at all, and
// through it by the PressGesture handler. The thing that turns one into a system
// event is the KeyPresser port and its adapter, which is where virtual keycodes
// and the machine's keyboard layout live -- none of that is here, and none of it
// may be.
//
// WHY THIS EXISTS AT ALL: A BLIND USER PRESSES CHORDS CONSTANTLY. Until 13.17
// this bridge could dispatch the reader's own commands and could type literal
// text, and could not send Command-L -- which is how a person opens a location,
// finds on a page or switches windows in the first minute of any session. The
// gap was OURS rather than the platform's (spec 0048 §1.1); this is the half of
// closing it that can be reasoned about without a keyboard.
//
// THE NOTATION IS `+`-JOINED, MODIFIERS FIRST AND THE KEY LAST: `command+l`,
// `control+option+space`, `shift+command+4`. Case is not significant and the
// order of the MODIFIERS among themselves is not either, so `Command+L` and
// `shift+command+4` and `command+shift+4` all parse; what comes back out of
// `described` is one canonical spelling, which is what the transcript and the
// result report so a reader of either sees what the bridge UNDERSTOOD rather
// than what was typed at it.
//
// A KEYSTROKE MAY HAVE NO MODIFIERS AT ALL, AND THAT IS 13.19. With single-key
// Quick Nav on, an ordinary VoiceOver user presses `h` to move by heading, and
// until that entry this bridge could not express it: `h` is looked up as one of
// the reader's command names and refused, because 13.17 made the `+` the whole
// discriminator. It is the id's SOURCE PREFIX that says which vocabulary is
// meant -- `kb:h` -- and CommandVocabulary owns that decision. By the time an id
// arrives here it is already known to be a keystroke, so a lone key parses.
//
// ============================================================================
// EVERY TOKEN THIS FILE ACCEPTS NAMES, ON NVDA, THE SAME PHYSICAL KEY.
// ============================================================================
//
// Spec 0049 §2.3, and it is the rule to read before adding a spelling here. The
// contract has two readers and one keystroke notation; a token that means one key
// on this side and another on that side is the worst thing this notation could
// contain, because it presses something with total confidence and nothing
// anywhere reports a problem.
//
// The names below were read out of `../nvda/source/vkCodes.py` at
// `release-2026.1` (its `byCode` map, lower-cased into `byName` for lookup)
// rather than recalled, and today's table diverged from it in four places -- three
// that merely FAIL on lane 1 (`return`, the four arrows, the casing of `pageUp`)
// and one that presses A DIFFERENT KEY: `delete` is this machine's
// erases-backwards key and is Windows' erases-FORWARDS one. So:
//
//   * NVDA's name is the canonical spelling, and the Mac's is a synonym wherever
//     the two name the same physical key (`return` for `enter`, `left` for
//     `leftArrow`, `alt` for `option`);
//   * where a token names a DIFFERENT key on the other reader, or no key at all
//     on this machine, it is REFUSED BY NAME with the alternative it should have
//     been -- `delete`, `insert`, and the `nvda` and `windows` modifiers.
//
// A name that differs with no hazard is tolerated; a name that differs with a
// hazard is refused. That is the whole line.
//
// THE KEY GOES LAST, AND THAT IS LANE 1's RULE RATHER THAN ONE INVENTED HERE.
// NVDA's `KeyboardInputGesture.fromName` treats the last token as the key and
// every earlier one as a modifier, which is why that bridge carries
// `keyboard_gesture_name.press_order` to hoist modifiers to the front before it
// presses anything. Following it means `command+l` is the same string on both
// readers in this contract, and `l+command` is a named failure on both. WE DO
// NOT COPY THE HOISTING ITSELF: `press_order` exists to undo NVDA's own
// normalizer, which sorts a stored gesture's parts alphabetically, and there is
// no such normalizer here -- so a wrong order stays a named failure rather than
// being quietly reordered, because the one place to hide a typo is not the place
// that presses a key.
//
// A MALFORMED ID FAILS BY NAME, and that is the entity's whole job. "command+"
// is missing its key, "command+ll" names no key at all, and "cmd+l" uses a
// modifier this bridge does not know -- each of those is a different mistake
// with a different fix, and an agent that gets "invalid gesture" back learns
// none of them. The one failure this file CANNOT diagnose is a character that
// the machine's current layout has no key for: that is the adapter's, because
// only the adapter knows what layout is active.

import Foundation

/// A keystroke id that is not one, and why.
///
/// Carries the id so the message can quote it back, exactly as `GestureIdRefused`
/// does: an agent sending a batch learns WHICH one was refused without counting
/// positions.
public struct KeystrokeMalformed: Error, Equatable, CustomStringConvertible {
	public let id: String
	public let reason: String

	public init(id: String, reason: String) {
		self.id = id
		self.reason = reason
	}

	public var description: String {
		"'\(id)' is not a keystroke this bridge can press: \(reason)"
	}
}

/// One key, pressed with zero or more modifiers held.
///
/// A DISCRETE PRESS AND RELEASE, which is already the contract's position
/// (protocol.md §5): there is no key repeat here and no way to hold a modifier
/// across several keys, because a gesture is one act. Lane 1 says the same thing
/// about `alt+tab`.
public struct Keystroke: Equatable, Sendable {
	/// The modifiers this bridge knows, in the order `described` writes them.
	///
	/// `fn` is included because a laptop keyboard's function row needs it and
	/// because macOS treats it as a modifier like the others; it is last in the
	/// enumeration and first in the canonical spelling, which is how Apple's own
	/// documentation writes it.
	///
	/// THE ORDER NEEDED NO STANDARDIZING, and that is worth recording where the
	/// next person will see it: lane 1's `press_order` writes `nvda, control, alt,
	/// shift, windows`, and position for position that is this sequence with the
	/// platform's substitutions. The two were arrived at independently.
	public enum Modifier: String, CaseIterable, Sendable {
		case fn
		case control
		case option
		case shift
		case command

		/// Parse one already-lower-cased token, or answer nil if it names no
		/// modifier this bridge knows.
		///
		/// `alt` is `option` -- the same physical key under two labels, and Apple
		/// prints both on its own keyboards, so accepting it can press nothing
		/// unexpected. The two Windows names that would be a HAZARD rather than a
		/// synonym are refused by name in `parse`, not here.
		public init?(token: String) {
			switch token {
			case "alt": self = .option
			default:
				guard let known = Modifier(rawValue: token) else { return nil }
				self = known
			}
		}
	}

	/// A key whose position is the same on every layout.
	///
	/// THESE SKIP THE LAYOUT ENTIRELY, and that is the point of separating them
	/// from a character. Return is Return on a Brazilian keyboard, an American one
	/// and a Dvorak one; `l` is not necessarily in the same place on any two of
	/// them. So a named key is a constant the adapter looks up in a table it owns,
	/// and a character is a question only the active layout can answer.
	///
	/// EACH CASE IS SPELLED AS NVDA SPELLS IT, so the case name and the canonical
	/// wire spelling cannot drift apart, and so a keystroke id written for one
	/// reader in this contract means the same key on the other.
	public enum NamedKey: Hashable, Sendable {
		case space
		case enter
		case tab
		case escape
		/// This machine's Delete key, which erases BACKWARDS. NVDA's name for it,
		/// and deliberately not the Mac's -- see `ambiguousKeyNames`.
		case backspace
		case forwardDelete
		case leftArrow
		case rightArrow
		case upArrow
		case downArrow
		case home
		case end
		case pageUp
		case pageDown
		/// `f1` through `f20`. A range rather than twenty cases, so the parser and
		/// the adapter's table agree about the bound in one place.
		case function(Int)

		/// The largest function key macOS names.
		public static let highestFunctionKey = 20

		/// Parse one already-lower-cased token, or answer nil if it names no key.
		///
		/// The first spelling in each case is NVDA's and is what `described`
		/// emits; the rest are what somebody reading Apple's documentation, or
		/// this bridge's own guidance before 13.19, actually writes.
		public init?(token: String) {
			switch token {
			case "space": self = .space
			case "enter", "return": self = .enter
			case "tab": self = .tab
			case "escape", "esc": self = .escape
			case "backspace": self = .backspace
			case "forwarddelete": self = .forwardDelete
			case "leftarrow", "left": self = .leftArrow
			case "rightarrow", "right": self = .rightArrow
			case "uparrow", "up": self = .upArrow
			case "downarrow", "down": self = .downArrow
			case "home": self = .home
			case "end": self = .end
			case "pageup": self = .pageUp
			case "pagedown": self = .pageDown
			default:
				guard token.first == "f", token.count >= 2 else { return nil }
				guard let number = Int(token.dropFirst()),
					number >= 1, number <= Self.highestFunctionKey
				else { return nil }
				self = .function(number)
			}
		}

		/// The one spelling `described` uses, which is NVDA's and is the first
		/// spelling accepted above -- so a parse of a `described` id gives the same
		/// keystroke back, and so does a press of it on the other reader.
		public var described: String {
			switch self {
			case .space: return "space"
			case .enter: return "enter"
			case .tab: return "tab"
			case .escape: return "escape"
			case .backspace: return "backspace"
			case .forwardDelete: return "forwardDelete"
			case .leftArrow: return "leftArrow"
			case .rightArrow: return "rightArrow"
			case .upArrow: return "upArrow"
			case .downArrow: return "downArrow"
			case .home: return "home"
			case .end: return "end"
			case .pageUp: return "pageUp"
			case .pageDown: return "pageDown"
			case .function(let number): return "f\(number)"
			}
		}
	}

	/// What is actually pressed, once the modifiers are accounted for.
	public enum Key: Equatable, Sendable {
		/// A character the ACTIVE LAYOUT has to be asked about. Held as written,
		/// lower-cased by the parser.
		case character(Character)
		/// A key in the same physical place on every keyboard.
		case named(NamedKey)

		public var described: String {
			switch self {
			case .character(let character): return String(character)
			case .named(let key): return key.described
			}
		}
	}

	public let modifiers: Set<Modifier>
	public let key: Key

	public init(modifiers: Set<Modifier>, key: Key) {
		self.modifiers = modifiers
		self.key = key
	}

	/// Parse `command+l` or `h`, or say by name why it is not a keystroke.
	///
	/// THE CALLER HAS ALREADY DECIDED THIS IS KEYSTROKE NOTATION -- that is
	/// `CommandVocabulary`'s job, and it uses the `kb:` source prefix or the `+`
	/// to decide -- so everything here reports a malformed KEYSTROKE rather than
	/// wondering whether a command name was meant. The messages say so, because an
	/// agent that lands here has got the notation right and the contents wrong.
	///
	/// A LONE KEY IS A KEYSTROKE HERE and is not one at the vocabulary: `h` alone
	/// is a command name, `kb:h` is this. The prefix is the whole difference and
	/// it is decided one layer up.
	public static func parse(_ id: String) throws -> Keystroke {
		let lowered = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let tokens = lowered.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
		guard !tokens.isEmpty, !tokens.contains(where: \.isEmpty) else {
			throw KeystrokeMalformed(
				id: id,
				reason: "one of its parts is empty -- write \"command+l\", not \"command+\" or "
					+ "\"command++l\". A literal '+' key is not expressible here; press it as a "
					+ "character with `type_text`"
			)
		}

		var modifiers: Set<Modifier> = []
		for token in tokens.dropLast() {
			guard let modifier = Modifier(token: token) else {
				throw KeystrokeMalformed(id: id, reason: reasonNoSuchModifier(token))
			}
			modifiers.insert(modifier)
		}

		return Keystroke(modifiers: modifiers, key: try parseKey(tokens[tokens.count - 1], in: id))
	}

	/// The canonical spelling: modifiers in the enumeration's order, then the key.
	///
	/// It is what the transcript and the `pressed` entry report, so both say what
	/// the bridge understood rather than echoing what it was handed. Feeding it
	/// back into `parse` gives the same keystroke.
	///
	/// THIS IS THE KEYSTROKE'S SPELLING AND NOT THE GESTURE ID'S. A keystroke with
	/// no modifiers is `h` here and `kb:h` as a gesture id, because without the
	/// prefix that id means one of the reader's command names instead --
	/// `Gesture.described` is where that lives, since notation belongs to the type
	/// that decides notation.
	public var described: String {
		let held = Modifier.allCases.filter(modifiers.contains).map(\.rawValue)
		return (held + [key.described]).joined(separator: "+")
	}

	// -- the pieces --------------------------------------------------------------

	private static func parseKey(_ token: String, in id: String) throws -> Key {
		if let reason = ambiguousKeyNames[token] {
			throw KeystrokeMalformed(id: id, reason: reason)
		}
		if let named = NamedKey(token: token) { return .named(named) }
		let characters = Array(token)
		guard characters.count == 1, let character = characters.first else {
			throw KeystrokeMalformed(
				id: id,
				reason: "'\(token)' is neither a single character nor a key this bridge names. It "
					+ "names space, enter, tab, escape, backspace, forwardDelete, the four arrows "
					+ "(leftArrow, rightArrow, upArrow, downArrow), home, end, pageUp, pageDown and "
					+ "f1 to f\(NamedKey.highestFunctionKey)"
			)
		}
		return .character(character)
	}

	/// The key names that are REFUSED rather than mapped, each with why.
	///
	/// THIS TABLE IS THE POINT OF SPEC 0049 §2.3. `delete` is the entry it exists
	/// for: it is this machine's erases-backwards key and Windows' erases-forwards
	/// one, so accepting it would mean the same gesture id doing two different
	/// things on the contract's two readers, with nothing anywhere to see. A
	/// refusal costs one round trip and names the fix; a wrong key costs whoever
	/// finds out, whenever they do.
	private static let ambiguousKeyNames: [String: String] = [
		"delete":
			"'delete' names a different key on each of this contract's readers, so this bridge will "
			+ "not guess. On this machine the Delete key erases BACKWARDS, which is \"backspace\" "
			+ "here; on NVDA \"delete\" is the forward delete, which is \"forwardDelete\" here. Say "
			+ "which you meant -- or send the reader's own \"delete key\" command, which erases "
			+ "backwards and costs no permission",
		"insert":
			"this keyboard has no Insert key. It is NVDA's own modifier and a key its users press "
			+ "constantly; there is nothing here to press. VoiceOver's modifier is Control-Option "
			+ "unless the person rebound it -- send the reader's command name instead, which works "
			+ "whatever it is bound to",
	]

	/// Why a token is not a modifier here, naming the fix where there is one.
	///
	/// The two Windows modifiers get their own answers, because an agent that has
	/// driven the other reader in this contract writes them and the generic
	/// message would leave it guessing which of five to try.
	private static func reasonNoSuchModifier(_ token: String) -> String {
		switch token {
		case "nvda":
			return "there is no NVDA key on this machine, and this bridge will not guess at the one "
				+ "that stands in for it: VoiceOver's modifier is Control-Option unless the person "
				+ "rebound it. Send the reader's own command name, which works whatever it is bound "
				+ "to -- or, if you meant the literal keys, write them out as \"control+option+…\""
		case "windows", "win":
			return "there is no Windows key on this machine; the key in that place is \"command\""
		default:
			return "'\(token)' is not a modifier this bridge knows. It knows "
				+ Modifier.allCases.map(\.rawValue).joined(separator: ", ")
				+ " (and \"alt\" for option) -- and only the LAST part may be the key, so "
				+ "\"command+l\" and not \"l+command\" is the spelling to write"
		}
	}
}
