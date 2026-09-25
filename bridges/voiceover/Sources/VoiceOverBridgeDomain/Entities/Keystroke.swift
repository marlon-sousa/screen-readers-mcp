// ROLE: entity, what a keystroke id means, parsed once before anything is posted at the machine.
// USED BY: CommandVocabulary, and through it the PressGesture handler; keycodes and the keyboard
// layout belong to the KeyPresser adapter, never here.
// Every token accepted here names the same physical key on NVDA, the contract's other reader; a
// token naming a different key there, such as `delete`, is refused by name. `vo` is the one
// exception: each bridge resolves its own reader's modifier symbol.

import Foundation

/// A keystroke id that is not one, and why.
/// Carries the id so an agent sending a batch learns which one was refused.
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

/// One or more keys, pressed together with zero or more modifiers held.
/// A discrete press and release: nothing is held across gestures, and there is no key repeat.
public struct Keystroke: Equatable, Sendable {
	/// The modifiers this bridge knows, in the order `described` writes them.
	public enum Modifier: String, CaseIterable, Sendable {
		case fn
		case control
		case option
		case shift
		case command

		/// Parse one already-lower-cased token, or answer nil if it names no
		/// modifier this bridge knows.
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
	/// Named keys skip the layout, which only a character needs; each case is spelled as NVDA spells it.
	public enum NamedKey: Hashable, Sendable {
		case space
		case enter
		case tab
		case escape
		/// This machine's Delete key, which erases backwards; see `ambiguousKeyNames`.
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
		/// `f1` through `f20`.
		case function(Int)

		/// The largest function key macOS names.
		public static let highestFunctionKey = 20

		/// Parse one already-lower-cased token, or answer nil if it names no key.
		/// The first spelling in each case is NVDA's and is what `described` emits.
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

		/// NVDA's spelling, the first accepted above, so parsing a `described` id round-trips.
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
		/// A character the active layout has to be asked about, lower-cased by the parser.
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

	/// The keys held together, in the order written: the adapter presses them down in this order and
	/// releases them in reverse.
	/// `parse` never produces an empty list; a hand-built empty one holds the modifiers and presses nothing.
	public let keys: [Key]

	/// Whether the chord holds every modifier this machine's reader uses for its own commands, so `vo+m`
	/// and `control+option+m` are the same fact; false when the reader's modifier is Caps Lock or unknown.
	public let holdsReaderModifier: Bool

	public init(modifiers: Set<Modifier>, keys: [Key], holdsReaderModifier: Bool = false) {
		self.modifiers = modifiers
		self.keys = keys
		self.holdsReaderModifier = holdsReaderModifier
	}

	/// Parse `command+l` or `h`, or say by name why it is not a keystroke.
	/// `vo` is resolved against `readerModifier` here or the parse fails, so the adapter never sees it.
	public static func parse(_ id: String, readerModifier: ModifierSetting) throws -> Keystroke {
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
		var index = 0
		// The last token is never a modifier, so `command+shift` fails as a keystroke with no key.
		while index < tokens.count - 1, isModifierToken(tokens[index]) {
			modifiers.formUnion(try resolveModifier(tokens[index], in: id, readerModifier))
			index += 1
		}

		var keys: [Key] = []
		for (offset, token) in tokens[index...].enumerated() {
			// A modifier after a key stays a named failure: reordering would hide a typo where a key is pressed.
			if !keys.isEmpty, isModifierToken(token) {
				throw KeystrokeMalformed(id: id, reason: reasonModifierAfterKey(token))
			}
			keys.append(
				try parseKey(token, in: id, isLast: index + offset == tokens.count - 1))
		}

		return Keystroke(
			modifiers: modifiers,
			keys: keys,
			holdsReaderModifier: holdsReaderModifier(modifiers, readerModifier))
	}

	/// The modifiers this machine's reader holds its own commands with, or nil
	/// when the machine does not say.
	/// The single place this mapping lives, so `vo` and `holdsReaderModifier` cannot drift apart.
	public static func readerModifierKeys(_ setting: ModifierSetting) -> Set<Modifier>? {
		switch setting {
		case .controlOption, .controlOptionOrCapsLock: return [.control, .option]
		case .capsLock, .unknown: return nil
		}
	}

	/// Whether a modifier set holds every modifier the reader claims.
	private static func holdsReaderModifier(
		_ modifiers: Set<Modifier>, _ setting: ModifierSetting
	) -> Bool {
		guard let readers = readerModifierKeys(setting), !readers.isEmpty else { return false }
		return readers.isSubset(of: modifiers)
	}

	/// The token that means "the modifier this reader's own commands are held
	/// with", whatever that is on this machine.
	public static let readerModifierToken = "vo"

	/// Whether a token occupies a modifier position, which `vo` does though it is not a `Modifier`.
	private static func isModifierToken(_ token: String) -> Bool {
		Modifier(token: token) != nil || token == readerModifierToken
	}

	/// One modifier token as the set of real modifiers it stands for.
	/// `vo` is refused, never approximated, when the reader's modifier is Caps Lock alone or could not
	/// be read: `control+option` would then press keys that mean nothing here.
	private static func resolveModifier(
		_ token: String, in id: String, _ readerModifier: ModifierSetting
	) throws -> Set<Modifier> {
		guard token == readerModifierToken else {
			guard let modifier = Modifier(token: token) else { return [] }
			return [modifier]
		}
		if let readers = readerModifierKeys(readerModifier) { return readers }
		switch readerModifier {
		case .capsLock:
			throw KeystrokeMalformed(id: id, reason: reasonModifierIsCapsLock)
		default:
			throw KeystrokeMalformed(id: id, reason: reasonModifierUnknown)
		}
	}

	/// The canonical spelling: modifiers in the enumeration's order, then the keys in the order given;
	/// parsing it gives the same keystroke back.
	public var described: String {
		let held = Modifier.allCases.filter(modifiers.contains).map(\.rawValue)
		return (held + keys.map(\.described)).joined(separator: "+")
	}

	/// One key token, or why it is not one.
	/// `isLast` picks the diagnosis, never the outcome: an unknown token before the last is told about
	/// modifiers.
	private static func parseKey(_ token: String, in id: String, isLast: Bool) throws -> Key {
		if token == readerModifierToken {
			throw KeystrokeMalformed(
				id: id,
				reason: "\"vo\" is the reader's own modifier and a keystroke needs a key beside it "
					+ "-- \"vo+m\" for the menu bar, \"vo+shift+w\" to read the window. On its own it "
					+ "presses nothing"
			)
		}
		if let reason = ambiguousKeyNames[token] {
			throw KeystrokeMalformed(id: id, reason: reason)
		}
		if let named = NamedKey(token: token) { return .named(named) }
		let characters = Array(token)
		guard characters.count == 1, let character = characters.first else {
			guard isLast else {
				throw KeystrokeMalformed(id: id, reason: reasonNoSuchModifier(token))
			}
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

	/// Why `vo` cannot be pressed on a machine bound to Caps Lock; it also says `control+option` is not
	/// the substitute.
	private static let reasonModifierIsCapsLock =
		"\"vo\" is the VoiceOver modifier, and on this machine it is bound to CAPS LOCK alone -- "
		+ "read from the reader's own preferences, not assumed. This bridge cannot synthesize that "
		+ "-- measured 2026-09-02, and it is a property of the platform rather than a gap here: "
		+ "Caps Lock is a system-level toggle, a posted `CGEvent` cannot hold it, and the reader "
		+ "never sees the chord (the letter reached the focused application instead). Reaching it "
		+ "would take HID-level remapping, which is not something to do to somebody's keyboard, "
		+ "and \"control+option\" is NOT a substitute here: those two keys are not the modifier on "
		+ "this machine and pressing them would do something else entirely. Send the reader's own "
		+ "command name instead (\"go to menu bar\", \"read contents of window\"), which works "
		+ "whatever the modifier is bound to and costs no permission -- or ask the person at this "
		+ "machine to set the modifier to Control-Option in VoiceOver Utility > Commands"

	/// Why `vo` cannot be pressed when the machine would not say what it is bound
	/// to.
	private static let reasonModifierUnknown =
		"\"vo\" is the VoiceOver modifier, and this bridge could not read what it is bound to on "
		+ "this machine -- VoiceOver's preferences could not be read, or hold a value this bridge "
		+ "does not know. It will not guess: Control-Option and Caps Lock are both possible, and "
		+ "pressing the wrong one presses something else with total confidence. Send the reader's "
		+ "own command name, which works whatever the modifier is bound to"

	/// Key names refused rather than mapped: `delete` erases backwards here and forwards on NVDA.
	private static let ambiguousKeyNames: [String: String] = [
		"delete":
			"'delete' names a different key on each of this contract's readers, so this bridge will "
			+ "not guess. On this machine the Delete key erases BACKWARDS, which is \"backspace\" "
			+ "here; on NVDA \"delete\" is the forward delete, which is \"forwardDelete\" here. Say "
			+ "which you meant -- or send the reader's own \"delete key\" command, which erases "
			+ "backwards and costs no permission",
		"insert":
			"this keyboard has no Insert key. It is NVDA's own modifier and a key its users press "
			+ "constantly; there is nothing here to press. THE COUNTERPART ON THIS READER IS "
			+ "\"vo\" -- write \"vo+m\" where you would have written \"insert+m\", and this bridge "
			+ "resolves it against what the person has actually bound their VoiceOver modifier to",
	]

	/// Why a modifier may not follow a key, and how to write what was probably
	/// meant.
	private static func reasonModifierAfterKey(_ token: String) -> String {
		"'\(token)' is a modifier, and a modifier may not follow a key: the modifiers come first "
			+ "and the keys LAST, so \"command+l\" and not \"l+command\". This bridge does not "
			+ "reorder them, because the one place not to hide a typo is the one that presses a "
			+ "key. If you meant two ordinary keys held together, every part after the modifiers "
			+ "has to be a key -- \"leftArrow+rightArrow\""
	}

	/// Why a token is not a modifier here, naming the fix where there is one.
	private static func reasonNoSuchModifier(_ token: String) -> String {
		switch token {
		case "nvda":
			return "there is no NVDA key on this machine. THE COUNTERPART HERE IS \"vo\", the "
				+ "VoiceOver modifier -- write \"vo+m\" where you would have written \"NVDA+m\", and "
				+ "this bridge resolves it against what the person has actually bound it to, exactly "
				+ "as NVDA resolves its own"
		case "windows", "win":
			return "there is no Windows key on this machine; the key in that place is \"command\""
		default:
			return "'\(token)' is not a modifier this bridge knows, and it names no key either. "
				+ "It knows the modifiers "
				+ (Modifier.allCases.map(\.rawValue) + [readerModifierToken]).joined(separator: ", ")
				+ " (\"alt\" for option, and \"vo\" for the reader's own modifier), and they come "
				+ "first -- every part after them is a key, so \"command+l\" and not \"l+command\" is "
				+ "the spelling to write. Two ordinary keys held together are written the same way: "
				+ "\"leftArrow+rightArrow\""
		}
	}
}
