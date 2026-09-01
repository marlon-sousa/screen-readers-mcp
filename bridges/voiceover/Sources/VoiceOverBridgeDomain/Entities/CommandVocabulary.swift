// ROLE: entity -- what counts as a gesture id on this reader, WHICH OF THE TWO
// ROUTES it takes, and what is refused before the machine is touched.
//
// PURE. USED BY: the PressGesture handler, which classifies the WHOLE batch
// before dispatching any of it -- see below.
//
// A GESTURE ID HERE IS AN ENGLISH COMMAND NAME OR A KEYSTROKE. protocol.md §5
// says gesture id syntax is reader-specific and passes through opaquely: it is
// "the reader's own user-facing command notation, as its documentation writes
// it". On NVDA that notation IS keystrokes (`NVDA+f7`); on VoiceOver it is a
// phrase from the 415-entry `SCRStringsToCommandsMap` vocabulary -- "go to
// desktop", "describe item in voiceover cursor", "mute sound toggle". This
// reader takes BOTH, because a person driving a Mac uses both:
//
//   * a COMMAND NAME goes to the reader, which dispatches it itself
//   * a KEYSTROKE goes to the system, which is how Command-L opens a location
//
// THIS FILE USED TO REFUSE THE SECOND, AND 13.17 DELETED THAT REFUSAL IN THE
// COMMIT THAT MADE THE PROMISE KEEPABLE -- the pattern 13.6 and 13.10 both
// followed before it. The refusal was not wrong when it was written: nothing in
// the bridge could press a chord, and admitting one would have meant failing it
// anyway. What it cost is recorded in spec 0048 §1.1: a true statement about
// this ENTITY was read as a fact about the PLATFORM, and the gap sat unnoticed
// through four entries while a blind user's commonest act stayed unreachable.
//
// THERE IS NO TABLE OF THE 415 HERE, AND THAT IS DELIBERATE. VoiceOver does its
// own dispatch and answers an unknown name with `Command does not exist (6)` --
// a clean, specific failure that costs one round trip and changes nothing. A
// copy of the vocabulary in this file would be a second source of truth that
// goes stale with every macOS release, would refuse commands a newer system
// added, and would buy nothing the reader does not already give for free. That
// is also why spec 0046 gives this entry no `GestureResolver` port.
//
// ============================================================================
// THREE RULES DECIDE, AND THE FIRST IS THE SOURCE PREFIX -- 13.19.
// ============================================================================
//
// 1. A SOURCE PREFIX, if there is one, settles it outright. `kb:h` is the
//    keyboard's `h`; `h` is one of the reader's command names. The prefix is
//    NVDA's own -- lane 1 strips exactly this shape in
//    `adapters/keyboard_gesture_name.bare_key_name` -- and spec 0018 reserved
//    the namespace for precisely this case: a reader where an id with no prefix
//    does NOT mean the keyboard. Everything up to and including the first `:` is
//    the source, and `kb` is the only one there is.
// 2. Otherwise `VO-D` is refused by name, for the reason below.
// 3. Otherwise a `+` means a keystroke, and anything else is a command name.
//
// WHY THIS HAD TO EXIST: with single-key Quick Nav on, an ordinary VoiceOver
// user presses `h` to move by heading. Under 13.17's rules -- where the `+` was
// the whole discriminator -- that id was looked up as a command and refused, and
// there was NO WAY AT ALL to ask for the letter key. The capability was reachable
// only by calling `type_text "h"`, which means something else entirely and was
// exactly the confusion the two notations were separated to prevent. Spec 0049.
//
// THE PREFIX OUTRANKS THE SHAPE OF WHAT FOLLOWS IT. `kb:go to desktop` is a
// malformed keystroke and not a command name: the agent said which vocabulary it
// meant, and the answer to a mistake is to name it rather than to guess past it.
//
// WHAT IS STILL REFUSED, AND BY NAME: VoiceOver's own `VO-D` notation. It is
// neither a command the reader will dispatch nor a keystroke this bridge can
// construct, because `VO` is whatever the user has configured their VoiceOver
// modifier to be -- Control-Option, or Caps Lock, or both -- and this file
// cannot know which. Guessing would press the wrong keys with total confidence,
// which is the exact mistake this type was written to catch. The refusal says to
// send `control+option+d` if that is what was meant.
//
// THE DISCRIMINATOR BEHIND ALL THREE IS THE SPACE RULE, and it is the one this
// file already lived by. A separator -- `:`, `+` or `-` -- counts as notation
// only in an id with NO SPACES AT ALL: every real command name that carries one
// carries spaces too ("mute sound toggle", "toggle single-key quick nav on or
// off"), and no command in the vocabulary is a bare joined token. So "command
// key" still goes to the reader and "command+l" does not.

import Foundation

/// Which of this reader's two routes an accepted id takes.
///
/// THE ENTITY CLASSIFIES; THE CONTROLLER ROUTES. Deciding this here is what lets
/// the whole batch be checked before any of it moves the machine, and what lets
/// the handler ask for the Accessibility grant exactly once, for a batch that
/// contains a keystroke, before anything at all has been pressed.
public enum Gesture: Equatable {
	/// One of VoiceOver's own English command names, dispatched by the reader.
	/// Costs no Accessibility grant.
	case readerCommand(String)

	/// A key with modifiers held, posted at the system. Costs the Accessibility
	/// grant, exactly as `typeText` does.
	case keystroke(Keystroke)

	/// What the bridge UNDERSTOOD, which is what the transcript and the `pressed`
	/// entry report. A command name is the trimmed id; a keystroke is its
	/// canonical spelling, so an agent that wrote `Command+L` is told `command+l`
	/// went out rather than being echoed its own text back.
	///
	/// THE SOURCE PREFIX APPEARS EXACTLY WHERE DROPPING IT WOULD LIE. A keystroke
	/// with modifiers spells itself `command+l`, which is lane 1's documented form
	/// and needs nothing added; one with no modifiers spells itself `kb:h`,
	/// because `h` fed back in is a command name and a transcript whose lines
	/// cannot be replayed is not doing its job.
	public var described: String {
		switch self {
		case .readerCommand(let command): return command
		case .keystroke(let keystroke):
			guard keystroke.modifiers.isEmpty else { return keystroke.described }
			return "\(CommandVocabulary.keyboardSource):\(keystroke.described)"
		}
	}

	/// Whether this one costs the Accessibility grant. Asked of a WHOLE BATCH by
	/// the handler, before any of it is dispatched.
	public var isKeystroke: Bool {
		guard case .keystroke = self else { return false }
		return true
	}
}

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
	/// Public because the guidance document, the tests and `Gesture.described`
	/// all have to agree about it, and a second spelling of a notation is how a
	/// notation stops being one.
	public static let keyboardSource = "kb"

	/// Classify a gesture id, or refuse it by name with its reason.
	///
	/// A command name comes back as the input with surrounding whitespace removed
	/// and NOTHING ELSE done to it. The trim is the one liberty taken with an
	/// opaque value, because a trailing space turns a perfectly good command into
	/// `Command does not exist` and no agent would ever see why; case, spelling
	/// and internal spacing are the reader's business and are passed through
	/// exactly as sent.
	///
	/// A keystroke comes back PARSED, so the id's contents are the caller's
	/// mistake to hear about here rather than the machine's to discover later.
	public static func classify(_ gesture: String) throws -> Gesture {
		let trimmed = gesture.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw GestureIdRefused(
				gesture: gesture,
				reason: "it is empty -- this reader's gestures are English command names, "
					+ "such as \"go to desktop\", or keystrokes, such as \"command+l\" and \"kb:h\""
			)
		}
		if let (source, rest) = sourcePrefix(of: trimmed) {
			guard source == keyboardSource else {
				throw GestureIdRefused(gesture: trimmed, reason: reasonNoSuchSource(source))
			}
			return .keystroke(try keystroke(rest, quoting: trimmed))
		}
		guard !isReaderModifierNotation(trimmed) else {
			throw GestureIdRefused(
				gesture: trimmed,
				reason: "it is VoiceOver's own shorthand, and this bridge cannot press it. \"VO\" is "
					+ "whatever the user has bound their VoiceOver modifier to -- Control-Option, or "
					+ "Caps Lock, or both -- so pressing it would mean guessing at somebody's own "
					+ "configuration. Send the reader's English command name (\"describe item in "
					+ "voiceover cursor\"), which costs no permission and works whatever the modifier "
					+ "is; or, if you meant the literal keys, write them out as \"control+option+d\""
			)
		}
		guard isKeystrokeNotation(trimmed) else {
			return .readerCommand(trimmed)
		}
		return .keystroke(try keystroke(trimmed, quoting: trimmed))
	}

	// -- the pieces --------------------------------------------------------------

	/// Parse a keystroke, re-quoting the refusal against the id the agent SENT.
	///
	/// A `kb:h` that fails must say `kb:h` and not `h`, or the agent is left
	/// looking for an id it never wrote.
	private static func keystroke(_ id: String, quoting sent: String) throws -> Keystroke {
		do {
			return try Keystroke.parse(id)
		} catch let malformed as KeystrokeMalformed {
			throw GestureIdRefused(gesture: sent, reason: malformed.reason)
		}
	}

	/// The source prefix and what follows it, or nil when the id carries none.
	///
	/// Everything up to and including the FIRST `:` is the source, which is lane
	/// 1's rule (`bare_key_name`) rather than one invented here.
	///
	/// THE SPACE RULE GUARDS THE SOURCE ITSELF, NOT THE WHOLE ID, and that is the
	/// one place this differs from the `+` and the `-`. A source is a single token,
	/// so a phrase before the colon means the colon is part of a command name --
	/// while a phrase AFTER it is a malformed keystroke, because the agent has
	/// already said which vocabulary it meant and the answer to a mistake is to
	/// name it rather than to guess past it.
	///
	/// Checked on the machine rather than assumed, 2026-08-31: none of the 415
	/// entries in `SCRStringsToCommandsMap.scrconfig` contains a `:` -- the same
	/// thing that was checked of the `+` before it became a discriminator.
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
			+ "says the id is a KEYSTROKE rather than one of the reader's command names -- as in "
			+ "\"kb:h\", the letter key an ordinary user presses with single-key Quick Nav on. An id "
			+ "with no source at all is a command name"
	}

	/// Whether an id is written as a keystroke: `+`-joined, and one token.
	///
	/// A `+` is unambiguous -- no command in the 415-entry vocabulary contains
	/// one, and it is how NVDA, the contract's other reader, writes every gesture.
	/// The space rule is what keeps it that way: a command name is a phrase, a
	/// keystroke is a single token, so an id with a space in it is a command name
	/// whatever else it contains.
	///
	/// A LONE KEY IS NOT ONE OF THESE, and that is 13.17's amendment 5 surviving
	/// 13.19 intact: the vocabulary's 30 `… key` commands cost no grant, so
	/// routing a bare `return` through the event path would spend an Accessibility
	/// request on a keypress that never needed one. The prefix is how an agent
	/// says it meant the key itself.
	private static func isKeystrokeNotation(_ gesture: String) -> Bool {
		gesture.contains("+") && !gesture.contains(" ")
	}

	/// Whether an id is VoiceOver's own hyphen shorthand (`VO-D`).
	///
	/// THE HYPHEN RULE HAS TO SURVIVE REAL COMMAND NAMES THAT CONTAIN HYPHENS:
	/// "toggle single-key quick nav on or off" is one of the 415, and there are
	/// three. What separates them is the space, exactly as above -- so a hyphen is
	/// this notation only in an id with no spaces at all. Both halves were read
	/// off the machine's own vocabulary file rather than assumed.
	private static func isReaderModifierNotation(_ gesture: String) -> Bool {
		gesture.contains("-") && !gesture.contains(" ")
	}
}
