// ROLE: entity -- how long the human has been unable to hear their own machine.
//
// The third watchdog's whole model (spec 0032, protocol.md §6.1), and PURE: no
// IO, no clock of its own -- every method takes `now` as monotonic seconds, so
// the entire thing is testable with plain numbers.
//
// BUILT BY: the Session, once, when a SILENT session establishes on an attended
// machine. There is no cap in live mode, because nothing is being withheld, and
// none on a machine whose owner declared it unattended.
// USED BY: the Session's silence check, which turns each returned action into a
// cue through SessionSignals and, at the lift, a call through SilenceControl.
//
// WHY IT IS NEITHER WATCHDOG WE ALREADY HAD. The heartbeat asks "is the server
// PROCESS alive?" and command-inactivity asks "is the AGENT still testing?".
// Both fire on ABSENCE, and both stayed correctly quiet on 2026-08-03 while a
// human sat mute for minutes and reached for NVDA's panic gesture. Twice. This
// one asks the human's question instead:
//
//     How long have I been unable to hear my own machine?
//
// Those readings come apart precisely when an agent is BUSY BUT SLOW, which
// after spec 0025 is the normal case rather than an edge one.
//
// MACOS EARNS THIS WATCHDOG MORE THAN NVDA DOES, and it is worth saying which
// way: here silence is rendered inside the provider, so the reader is MUTE
// rather than merely intercepted. The lift is cheaper in exchange -- one file
// write and the next utterance passes through, with the agent's indices and
// timestamps unchanged.
//
// WHAT RESETS IT is only sound the human ACTUALLY HEARS: the session cue,
// `announce` and `askUser`. Four hundred gestures in ninety seconds reset
// nothing, because they told the human nothing.
//
// A LIFTED SESSION GOES QUIET AGAIN, AND UNTIL 2026-09-01 THIS ONE DID NOT.
// `protocol.md` §6.1 rule 4: *"A lifted session may go quiet again, on a fresh
// window of the same length, and each re-suppression is audibly marked. So
// exposure stays bounded no matter how many times a session re-arms."* This
// file's header used to say `resuppressed` was "left out rather than stubbed"
// and would arrive with 13.10 -- 13.10 added `announce` and `askUser`, which
// reset the window, and the re-arm was never added behind them. What that
// produced is the sequence the maintainer hit while driving the bridge:
//
//   connect (silent) -> quiet -> the cap warns -> still quiet -> the cap LIFTS
//   -> the agent announces -> the machine should go quiet again. It did not.
//
// `didLift` was a ONE-WAY LATCH: `check` answered `.none` forever afterwards, so
// the session was audible for the rest of its life however much the agent
// narrated. The lift is a guarantee about a bounded window, not a decision that
// this session is finished being silent.
//
// THE RE-ARM IS A THIRD ACTION RATHER THAN A METHOD THE CALLER REMEMBERS TO CALL.
// Lane 1 puts it in its session context, which holds the announcer; here the
// Session is the only thing that may touch `SilenceControl` or play a cue, and it
// already acts on this type's answers -- so `heard` records that something
// audible happened after a lift and `check` returns `.resuppress` when it did.
// The entity keeps answering "given these instants, what should happen"; the
// Session does it.
//
// WHAT LANE 1 HAS AND THIS STILL DOES NOT: `paused`/`resumed`. An `askUser`
// window holds the suppression open, and this bridge keeps the window fresh by
// calling `heard` on every tick while a prompt is outstanding rather than by
// stopping the clock. Same effect, one fewer piece of state.

/// The shipped thresholds, in seconds -- lane 1's numbers, settled from the
/// chair on 2026-08-19 and unchanged here because the question they answer is
/// about a human, not about a reader.
///
/// Deliberately not shorter: speech EMISSION runs ahead of audio, so a sound
/// that reset this clock has been made rather than necessarily heard -- a
/// rounding error at 45 s, and not one at 5 s.
public let defaultWarnAfter: Double = 45.0
public let defaultLiftAfter: Double = 90.0

/// Whether a machine bounds its silences, and by how much.
///
/// Settled before the session starts, and NOTHING ON THE WIRE MAY CHANGE IT: an
/// agent that could raise its own ceiling does not have one (protocol.md §6.1,
/// rule 1). `enabled` follows the machine's `attended` flag, which is a fact
/// about the room read from the bridge's own configuration.
public struct SilenceCapPolicy: Equatable, Sendable {
	public let enabled: Bool
	public let warnAfter: Double
	public let liftAfter: Double

	/// An unordered pair is REPAIRED, not rejected, and never by disabling the
	/// cap.
	///
	/// Lane 1 raises on this and falls back to the defaults only for values read
	/// off disk. Swift's equivalent of raising here would be a precondition, and
	/// crashing is not a thing a bridge may do to somebody's screen reader --
	/// while "warn after the lift" would mean the warning is never spoken and
	/// nothing at all would look wrong. So it fails toward the DEFAULTS, which is
	/// the same safe direction the whole entry takes: a machine nobody has
	/// configured coherently is not a machine we may assume is empty.
	public init(enabled: Bool, warnAfter: Double = defaultWarnAfter, liftAfter: Double = defaultLiftAfter) {
		self.enabled = enabled
		let ordered = 0 < warnAfter && warnAfter < liftAfter
		self.warnAfter = ordered ? warnAfter : defaultWarnAfter
		self.liftAfter = ordered ? liftAfter : defaultLiftAfter
	}

	/// What a machine gets when nobody has configured it: capped, on the shipped
	/// thresholds. The single definition of "unconfigured", so the session's
	/// default, wiring's fallback and the tests cannot drift apart about it.
	public static let attendedDefault = SilenceCapPolicy(enabled: true)
}

/// What the session should do about the silence, right now.
public enum SilenceCapAction: Equatable, Sendable {
	/// Nothing is owed: the window is young, or its notice already went out.
	case none
	/// Tell the human the room is quiet, with time to spare.
	case warn
	/// Stop suppressing. Capture continues -- protocol.md §6.1's table.
	case lift
	/// Go quiet again, on a fresh window: the session was lifted and the human
	/// has heard their machine since (protocol.md §6.1, rule 4).
	///
	/// AUDIBLY MARKED BY WHOEVER ACTS ON IT, which the rule requires in as many
	/// words -- a human whose machine goes quiet a second time is entitled to
	/// have heard it happen, or the two windows read as one long silence.
	case resuppress
}

public final class SilenceCap {
	private let policy: SilenceCapPolicy
	/// When the human last heard their machine. Seeded at session start, which is
	/// honest: the session cue is itself a sound that gets past the suppression.
	private var since: Double
	private var warned = false
	private var didLift = false
	/// Whether something audible has reached the human since the lift, which is
	/// the one condition under which suppression may re-arm.
	private var heardSinceLift = false

	public init(policy: SilenceCapPolicy, now: Double) {
		self.policy = policy
		self.since = now
	}

	/// Whether the cap has already given the machine back this session.
	public var lifted: Bool { didLift }

	/// The human heard their machine: a fresh window.
	///
	/// Called for exactly the sounds that reach them past the suppression.
	/// Anything an agent does that makes no sound -- pressing keys, typing,
	/// reading buffers back -- must NOT come through here, however much of it
	/// there is.
	public func heard(_ now: Double) {
		since = now
		warned = false
		// ON A LIFTED SESSION THIS IS ALSO THE MOMENT SUPPRESSION MAY RE-ARM: the
		// agent has narrated, the ordinary flow resumes, and a fresh bounded window
		// can start. Recorded rather than acted on, because whether the machine
		// actually goes quiet is the Session's business and this type does no IO.
		if didLift { heardSinceLift = true }
	}

	/// What is owed at `now`. Never repeats an act, so a loop polling every few
	/// milliseconds does not say the same thing a thousand times.
	public func check(_ now: Double) -> SilenceCapAction {
		guard policy.enabled else { return .none }
		if didLift {
			// A lifted session stays audible until something is HEARD. Until then
			// there is nothing owed: re-arming on a timer would mute a human who has
			// been told nothing since their machine came back, which is the exact
			// harm the lift exists to end.
			guard heardSinceLift else { return .none }
			didLift = false
			heardSinceLift = false
			warned = false
			// THE FRESH WINDOW STARTS WHEN THE MACHINE GOES QUIET, not when the
			// announcement was made: the human can hear everything up to this
			// instant, so charging the new window for that time would shorten it.
			since = now
			return .resuppress
		}
		let elapsed = now - since
		// THE LIFT IS TESTED FIRST, deliberately. It is the guarantee; the warning
		// is a courtesy. A loop starved past both thresholds at once must give the
		// human their machine back, not spend the turn warning about a silence
		// that has already run past its limit.
		if elapsed >= policy.liftAfter {
			didLift = true
			warned = true
			return .lift
		}
		if !warned, elapsed >= policy.warnAfter {
			warned = true
			return .warn
		}
		return .none
	}
}
