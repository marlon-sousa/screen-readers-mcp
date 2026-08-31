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
/// TWELVE FIELDS AT 13.17, AND THAT IS THE HONEST STATE OF THIS BRIDGE. The seam
/// exists because `hello` is where a reader edge is built; what goes in it
/// arrives with the entry that can supply it:
///
/// | Field | Entry |
/// |---|---|
/// | `speechSource` | 13.5, the capture feed |
/// | `silenceControl`, `providerLifecycle` | 13.6, capture mode |
/// | `gestureSender`, `readerLiveness` | 13.7, input: commands |
/// | `textTyper`, `permissions` | 13.8, input: typing |
/// | `focusInspector` | 13.9, focus |
/// | `announcer`, `userPrompter` | 13.10, the human channel |
/// | `keyPresser` | 13.17, chords -- here |
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

	/// How a command reaches the reader. Present in both modes: a gesture is
	/// dispatched identically whether or not the human can hear the result.
	public let gestureSender: any GestureSender

	/// Whether the reader is there at all, asked only when something has already
	/// failed. IT IS A SECOND FIELD RATHER THAN A BOOLEAN THE SENDER RETURNS, and
	/// that is a layout amendment to spec 0046's 13.7 table with its why: "the
	/// reader answers its own name but not its own state" is a claim about TWO
	/// channels, so the port that answers one of them and the port that answers
	/// the other are separate, and the CONTROLLER combines them. Putting the
	/// combination inside the sender would make one adapter depend on another
	/// without a seam, which is the one thing the layering rule forbids.
	public let readerLiveness: any ReaderLiveness

	/// How literal text reaches whatever holds system focus. A SECOND INPUT PORT
	/// beside the gesture sender rather than a method on it, and the separation is
	/// the design rather than tidiness: input on this platform costs different
	/// permissions depending on how it is delivered (spec 0041), and one port that
	/// did everything would make "this session was asked for no permission"
	/// impossible to check.
	public let textTyper: any TextTyper

	/// How a KEY WITH MODIFIERS HELD reaches whatever holds system focus -- the
	/// third input port, and 13.17's one addition to this set.
	///
	/// IT IS NOT A METHOD ON THE TYPER, and the reason is the typer's own promise:
	/// `typeText` is layout-independent Unicode injection, and a chord is the
	/// opposite -- a virtual keycode, in a place that differs between a Brazilian
	/// keyboard and an American one. Folding the two together would have put a
	/// layout question inside the adapter whose header says the layout is
	/// irrelevant. See `KeyPresser`, whose header carries the rest.
	///
	/// IT COSTS THE SAME GRANT THE TYPER DOES, which is why `pressGesture` became
	/// the second of the bridge's two callers of `PermissionBroker.request`. The
	/// lever narrowed rather than being spent: a session that presses only the
	/// reader's COMMAND NAMES and reads speech still asks for nothing.
	public let keyPresser: any KeyPresser

	/// What the system lets this process do, and the one place it may ask for
	/// more. HELD BY THE SET AND COMBINED BY THE CONTROLLER, which is a layout
	/// amendment to spec 0046's 13.8 table with its why: the spec has the TYPER
	/// hold it, which would put a domain port inside an adapter and make one
	/// adapter depend on another outside an `adapters/ports/` seam. 13.7 met the
	/// same shape with `readerLiveness` and resolved it the same way. See
	/// `PermissionBroker`, whose header carries the rest of the argument --
	/// including the one 13.7 did not have, that the control dialog will need this port
	/// too and a view may consume a port but not an adapter's private seam.
	///
	/// PROCESS-SCOPED, like the provider lifecycle: it describes this process's
	/// standing with the system, which cannot change because a socket was
	/// accepted.
	public let permissions: any PermissionBroker

	/// Where the focus is. Present in both modes, like the gesture sender and for
	/// the same reason: focus is read identically whether or not the human can
	/// hear the result.
	///
	/// IT DOES NOT HOLD THE PERMISSION BROKER, and that is 13.9's one layout
	/// decision. Focus answers from the accessibility tree when this process holds
	/// the Accessibility grant and from the VoiceOver cursor when it does not --
	/// but choosing between two routes is a DECISION, decisions live in the upper
	/// adapter, and a macOS permission has no place in a port's signature. So the
	/// adapter reads the grant through an adapter seam of its own
	/// (`AccessibilityTrust`, answered by the same leaf that answers
	/// `permissions`), the domain never learns that focus has two routes, and
	/// NOTHING on this path can request anything. See `FocusInspector`.
	public let focusInspector: any FocusInspector

	/// How this session speaks TO the human at the reader.
	///
	/// PRESENT IN BOTH MODES, and in a silent one it is the human's ONLY channel:
	/// it speaks with the bridge's own synthesizer, outside VoiceOver entirely, so
	/// the suppression the capture voice is rendering does not reach it. See
	/// `Announcer`, whose header carries the argument, and `HumanWarning`, which
	/// is where a promise this bridge used to be unable to keep became keepable.
	///
	/// PROCESS-SCOPED, like the permission broker: it describes a way out of this
	/// process rather than anything about a session.
	public let announcer: any Announcer

	/// How this session asks the human a question and collects the answer later.
	///
	/// TWO COMMANDS, ONE PORT (protocol.md §5): `askUser` presents and
	/// `waitForUserReply` polls, and NOTHING BLOCKS -- because the thread that
	/// would block is the one that renews the silence lease. `UserPrompter`'s
	/// header carries that decision and the alternative it was chosen over.
	public let userPrompter: any UserPrompter

	public init(
		mode: CaptureMode,
		speechSource: any SpeechSource,
		silenceControl: any SilenceControl,
		providerLifecycle: any ProviderLifecycle,
		gestureSender: any GestureSender,
		readerLiveness: any ReaderLiveness,
		textTyper: any TextTyper,
		keyPresser: any KeyPresser,
		permissions: any PermissionBroker,
		focusInspector: any FocusInspector,
		announcer: any Announcer,
		userPrompter: any UserPrompter
	) {
		self.mode = mode
		self.speechSource = speechSource
		self.silenceControl = silenceControl
		self.providerLifecycle = providerLifecycle
		self.gestureSender = gestureSender
		self.readerLiveness = readerLiveness
		self.textTyper = textTyper
		self.keyPresser = keyPresser
		self.permissions = permissions
		self.focusInspector = focusInspector
		self.announcer = announcer
		self.userPrompter = userPrompter
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
