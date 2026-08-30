// ROLE: entity -- what counts as a gesture id on this reader, and what is
// refused before the machine is touched.
//
// PURE. USED BY: the PressGesture handler, which checks the WHOLE batch before
// dispatching any of it -- see below.
//
// A GESTURE ID HERE IS AN ENGLISH COMMAND NAME AND NOTHING ELSE. protocol.md §5
// says gesture id syntax is reader-specific and passes through opaquely: it is
// "the reader's own user-facing command notation, as its documentation writes
// it". On NVDA that is a key combo (`"NVDA+f7"`); on VoiceOver it is a phrase
// from the 415-entry `SCRStringsToCommandsMap` vocabulary -- "go to desktop",
// "describe item in voiceover cursor", "mute sound toggle". Same field, entirely
// different notation, which is exactly what "reader-specific" means.
//
// THERE IS NO TABLE OF THE 415 HERE, AND THAT IS DELIBERATE. VoiceOver does its
// own dispatch and answers an unknown name with `Command does not exist (6)` --
// a clean, specific failure that costs one round trip and changes nothing. A
// copy of the vocabulary in this file would be a second source of truth that
// goes stale with every macOS release, would refuse commands a newer system
// added, and would buy nothing the reader does not already give for free. That
// is also why spec 0046 gives this entry no `GestureResolver` port.
//
// SO WHAT IS LEFT TO REFUSE IS EXACTLY THE MISTAKE THE READER CANNOT DIAGNOSE
// FOR US: A KEYSTROKE SENT AS A GESTURE. An agent that has driven NVDA -- or
// read VoiceOver's own documentation, which writes shortcuts as `VO-D` -- will
// eventually send `"VO-D"` or `"control+l"` here. VoiceOver would answer
// `Command does not exist`, which is true and useless: the agent's mistake is
// not a typo in a command name, it is that this reader's gesture channel does
// not take keystrokes at all. Naming that is the whole value of this type.
//
// AND REFUSING IT IS A LOAD-BEARING BOUNDARY, NOT TIDINESS. Synthesizing a
// keystroke needs the Accessibility grant, which is the grant 13.8 exists to
// keep lazy. A bridge that quietly accepted key combos here would either fail
// them anyway or have to reach for that grant -- and "a session that only
// presses commands and reads speech never triggers an Accessibility request"
// would stop being a checkable statement about this bridge.
//
// THE KEYSTROKE THAT IS NOT REFUSED: the vocabulary itself contains commands
// like "f8 key" and "command key", which press a key THROUGH the reader. Those
// are command names, they go through untouched, and they are the honest route
// for an agent that wants a key pressed before 13.8 exists.

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
	/// Accept a gesture id, or refuse it by name with its reason.
	///
	/// Returns the id to dispatch, which is the input with surrounding
	/// whitespace removed and NOTHING ELSE done to it. The trim is the one
	/// liberty taken with an opaque value, because a trailing space turns a
	/// perfectly good command into `Command does not exist` and no agent would
	/// ever see why; case, spelling and internal spacing are the reader's
	/// business and are passed through exactly as sent.
	public static func accept(_ gesture: String) throws -> String {
		let trimmed = gesture.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			throw GestureIdRefused(
				gesture: gesture,
				reason: "it is empty -- this reader's gestures are English command names, "
					+ "such as \"go to desktop\" or \"describe item in voiceover cursor\""
			)
		}
		guard !looksLikeAKeystroke(trimmed) else {
			throw GestureIdRefused(
				gesture: trimmed,
				reason: "it reads as a key combination, and this reader's gesture channel takes "
					+ "COMMAND NAMES rather than keystrokes -- VoiceOver dispatches them itself, "
					+ "which is why no Accessibility grant is needed. Send the English name of the "
					+ "command instead (\"go to desktop\", not \"VO-D\"); the vocabulary also "
					+ "contains commands like \"f8 key\" for pressing a key through the reader"
			)
		}
		return trimmed
	}

	/// Whether an id is written in somebody's keystroke notation.
	///
	/// TWO SHAPES, AND THE SECOND ONE NEEDS ITS RULE STATED because the obvious
	/// spelling of it is wrong. A `+` is unambiguous -- no command in the
	/// vocabulary contains one, and it is how NVDA, the contract's other reader,
	/// writes every gesture. A HYPHEN is how VoiceOver's own documentation writes
	/// chords (`VO-D`, `Control-Option-Shift-Down`), but hyphens also appear
	/// INSIDE real command names: "toggle single-key quick nav on or off" is one
	/// of the 415. What separates them is the space -- a command name is a
	/// phrase, a chord is a single token -- so a hyphen is a keystroke only in an
	/// id that has no spaces at all. Both halves were read off the real
	/// vocabulary file rather than assumed.
	private static func looksLikeAKeystroke(_ gesture: String) -> Bool {
		if gesture.contains("+") { return true }
		return gesture.contains("-") && !gesture.contains(" ")
	}
}
