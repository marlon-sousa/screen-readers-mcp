// ROLE: port -- builds the mode-specific collaborators, once, after `hello`.
//
// IMPLEMENTED BY: VoiceOverAdapterFactory (adapters), the only place that knows
// what a mode MEANS; FakeAdapterFactory (Tests/Fakes).
// BUILT BY: Wiring. CALLED BY: the Hello handler, exactly once per session.
// OWNS: `AdapterSet`, this port's own DTO, and `AdapterFactoryError`, its own
// signalling type -- both in this file, per the repo's rule that a port's types
// live with the port.
//
// WHY A FACTORY AT ALL: the capture mode is not known until the client's `hello`
// arrives, and this repo does not configure a collaborator after constructing it
// (AGENTS.md, Decided). So Wiring injects the factory rather than a fixed set,
// and the session's reader edge comes into existence at the handshake.

import ScreenReaderWire

/// The mode-specific collaborators a session drives.
///
/// THREE FIELDS AT 13.6, AND THAT IS THE HONEST STATE OF THIS BRIDGE. The seam
/// exists because `hello` is where a reader edge is built; what goes in it
/// arrives with the entry that can supply it:
///
/// | Field | Entry |
/// |---|---|
/// | `speechSource` | 13.5, the capture feed |
/// | `silenceControl`, `providerLifecycle` | 13.6, capture mode -- here |
/// | `gestureSender` | 13.7 |
/// | `textTyper` | 13.8 |
/// | `focusInspector` | 13.9 |
///
/// A field stubbed ahead of its entry would be a collaborator that answers
/// nothing while the capability list says it does, which is the one thing the
/// capability gate exists to prevent.
public struct AdapterSet {
	/// The mode this set was built for. Held so a later reader of the set does
	/// not have to ask the session what it was built from.
	public let mode: CaptureMode

	/// Where captured speech comes from. NOT OPTIONAL, because every mode
	/// captures: capture is IDENTICAL in both modes on this route -- the same
	/// feed, the same indices, the same stamps -- and only rendering differs,
	/// which the extension does. So the field is required rather than a question
	/// every handler has to ask. (It read "silent is refused outright until 13.6"
	/// until 13.6 made the promise keepable.)
	public let speechSource: any SpeechSource

	/// Whether the human hears their machine, and the voice pass-through uses.
	///
	/// PRESENT IN BOTH MODES, like the speech source and for a related reason: a
	/// live session still opens the channel, because the user's own voice has to
	/// reach the extension for pass-through to be acoustically invisible (spec
	/// 0046, "Rule 0"). Only what it is asked for differs.
	public let silenceControl: any SilenceControl

	/// Where the capture voice has got to, and how the reader is pointed at it.
	public let providerLifecycle: any ProviderLifecycle

	public init(
		mode: CaptureMode,
		speechSource: any SpeechSource,
		silenceControl: any SilenceControl,
		providerLifecycle: any ProviderLifecycle
	) {
		self.mode = mode
		self.speechSource = speechSource
		self.silenceControl = silenceControl
		self.providerLifecycle = providerLifecycle
	}
}

/// A mode this build cannot carry out.
///
/// Its own type rather than the command layer's `CommandError`, because a port
/// may not depend on a controller. The Hello handler translates it.
public struct AdapterFactoryError: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol AdapterFactory: AnyObject {
	/// Construct the collaborators for `mode`, or refuse the mode.
	///
	/// REFUSING IS PART OF THE CONTRACT, not an error path bolted on: a mode is
	/// an instruction, and a bridge that cannot carry one out must say so at the
	/// handshake rather than establish a session that quietly does something else.
	func build(mode: CaptureMode) throws -> AdapterSet
}
