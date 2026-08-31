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
// THE KEY GOES LAST, AND THAT IS LANE 1's RULE RATHER THAN ONE INVENTED HERE.
// NVDA's `KeyboardInputGesture.fromName` treats the last token as the key and
// every earlier one as a modifier, which is why that bridge carries
// `keyboard_gesture_name.press_order` to hoist modifiers to the front before it
// presses anything. Following it means `command+l` is the same string on both
// readers in this contract, and `l+command` is a named failure on both.
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
	public enum Modifier: String, CaseIterable, Sendable {
		case fn
		case control
		case option
		case shift
		case command
	}

	/// A key whose position is the same on every layout.
	///
	/// THESE SKIP THE LAYOUT ENTIRELY, and that is the point of separating them
	/// from a character. Return is Return on a Brazilian keyboard, an American one
	/// and a Dvorak one; `l` is not necessarily in the same place on any two of
	/// them. So a named key is a constant the adapter looks up in a table it owns,
	/// and a character is a question only the active layout can answer.
	public enum NamedKey: Hashable, Sendable {
		case space
		case `return`
		case tab
		case escape
		case delete
		case forwardDelete
		case left
		case right
		case up
		case down
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
		public init?(token: String) {
			switch token {
			case "space": self = .space
			case "return", "enter": self = .return
			case "tab": self = .tab
			case "escape", "esc": self = .escape
			case "delete", "backspace": self = .delete
			case "forwarddelete": self = .forwardDelete
			case "left", "leftarrow": self = .left
			case "right", "rightarrow": self = .right
			case "up", "uparrow": self = .up
			case "down", "downarrow": self = .down
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

		/// The one spelling `described` uses, which is the first spelling accepted
		/// above -- so a parse of a `described` id gives the same keystroke back.
		public var described: String {
			switch self {
			case .space: return "space"
			case .return: return "return"
			case .tab: return "tab"
			case .escape: return "escape"
			case .delete: return "delete"
			case .forwardDelete: return "forwarddelete"
			case .left: return "left"
			case .right: return "right"
			case .up: return "up"
			case .down: return "down"
			case .home: return "home"
			case .end: return "end"
			case .pageUp: return "pageup"
			case .pageDown: return "pagedown"
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

	/// Parse `command+l`, or say by name why it is not one.
	///
	/// THE CALLER HAS ALREADY DECIDED THIS IS KEYSTROKE NOTATION -- that is
	/// `CommandVocabulary`'s job and it uses the `+` to decide -- so everything
	/// here reports a malformed KEYSTROKE rather than wondering whether a command
	/// name was meant. The messages say so, because an agent that lands here has
	/// got the notation right and the contents wrong.
	public static func parse(_ id: String) throws -> Keystroke {
		let lowered = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		let tokens = lowered.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
		guard tokens.count >= 2 else {
			throw KeystrokeMalformed(
				id: id,
				reason: "a keystroke is modifiers and a key joined by '+', such as \"command+l\""
			)
		}
		guard !tokens.contains(where: \.isEmpty) else {
			throw KeystrokeMalformed(
				id: id,
				reason: "one of its parts is empty -- write \"command+l\", not \"command+\" or "
					+ "\"command++l\". A literal '+' key is not expressible here; press it as a "
					+ "character with `type_text`"
			)
		}

		var modifiers: Set<Modifier> = []
		for token in tokens.dropLast() {
			guard let modifier = Modifier(rawValue: token) else {
				throw KeystrokeMalformed(
					id: id,
					reason: "'\(token)' is not a modifier this bridge knows. It knows "
						+ Modifier.allCases.map(\.rawValue).joined(separator: ", ")
						+ " -- and only the LAST part may be the key, so \"command+l\" and not \"l+command\" "
						+ "is the spelling to write"
				)
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
	public var described: String {
		let held = Modifier.allCases.filter(modifiers.contains).map(\.rawValue)
		return (held + [key.described]).joined(separator: "+")
	}

	// -- the pieces --------------------------------------------------------------

	private static func parseKey(_ token: String, in id: String) throws -> Key {
		if let named = NamedKey(token: token) { return .named(named) }
		let characters = Array(token)
		guard characters.count == 1, let character = characters.first else {
			throw KeystrokeMalformed(
				id: id,
				reason: "'\(token)' is neither a single character nor a key this bridge names. It "
					+ "names space, return, tab, escape, delete, forwarddelete, the four arrows "
					+ "(left, right, up, down), home, end, pageup, pagedown and f1 to "
					+ "f\(NamedKey.highestFunctionKey)"
			)
		}
		return .character(character)
	}
}
