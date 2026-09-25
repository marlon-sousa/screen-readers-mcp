// ROLE: entity, what counts as a gesture id on this reader and what is refused before the
// machine is touched.
// USED BY: the PressGesture handler, which classifies the whole batch before dispatching any of it.

import Foundation

/// A gesture id this reader cannot accept, and why.
/// Carries the id so an agent sending a batch learns which one was refused.
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
	/// The one gesture source this bridge knows, spelled as NVDA spells it.
	public static let keyboardSource = "kb"

	/// How a person reaches an act that has no key of its own.
	public static let commandsMenuRoute =
		"an act with no key of its own is reached the way a person reaches it: open the Commands "
		+ "menu with \"vo+h\" pressed twice, type the act's name with type_text, and press "
		+ "\"kb:enter\""

	/// Classify a gesture id, or refuse it by name with its reason.
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

	/// The keystroke's canonical spelling, reported in the transcript and the `pressed` entry; an id
	/// with no modifiers carries `kb:`, so it would be accepted if sent back in.
	public static func identifier(for keystroke: Keystroke) -> String {
		guard keystroke.modifiers.isEmpty else { return keystroke.described }
		return "\(keyboardSource):\(keystroke.described)"
	}

	/// Why an ordinary phrase is not a gesture id any more, and what to do instead.
	/// The `kb:` suggestion goes only to an id with no spaces: `kb:go to menu bar` is itself malformed.
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
	private static func reasonHyphenShorthand(_ gesture: String) -> String {
		"it is VoiceOver's own hyphen shorthand, and this bridge writes a keystroke with \"+\" "
			+ "instead -- one notation, the same one the other reader in this contract uses. Write "
			+ "\"\(gesture.replacingOccurrences(of: "-", with: "+").lowercased())\". \"vo\" IS a "
			+ "modifier here: this bridge reads what the person has bound their VoiceOver modifier "
			+ "to and presses that"
	}

	/// Parse a keystroke, quoting the refusal against the id the agent sent.
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
	/// A space before the colon makes it an ordinary phrase, not a source; a space after it is a
	/// malformed keystroke.
	private static func sourcePrefix(of gesture: String) -> (source: String, rest: String)? {
		guard let colon = gesture.firstIndex(of: ":") else { return nil }
		let source = String(gesture[gesture.startIndex..<colon])
		guard !source.contains(" ") else { return nil }
		return (source: source.lowercased(), rest: String(gesture[gesture.index(after: colon)...]))
	}

	/// Why a source is not one here, answering the qualified form by name.
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
	private static func isKeystrokeNotation(_ gesture: String) -> Bool {
		gesture.contains("+") && !gesture.contains(" ")
	}

	/// Whether an id is VoiceOver's own hyphen shorthand (`VO-D`).
	/// The no-space rule keeps hyphenated phrases such as "toggle single-key quick nav on or off" out.
	private static func isReaderModifierNotation(_ gesture: String) -> Bool {
		gesture.contains("-") && !gesture.contains(" ")
	}
}
