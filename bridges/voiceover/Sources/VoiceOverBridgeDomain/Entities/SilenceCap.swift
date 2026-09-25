// ROLE: entity -- how long the human has been unable to hear their own machine.
// BUILT BY: the Session, once, when a silent session establishes on an attended machine.
// USED BY: the Session's silence check, which turns each returned action into a cue or a SilenceControl call.
/// Not shorter: speech emission runs ahead of audio, so a sound that reset this clock was made, not necessarily heard.
public let defaultWarnAfter: Double = 45.0
public let defaultLiftAfter: Double = 90.0

/// Nothing on the wire may change this: an agent that could raise its own ceiling does not have one.
public struct SilenceCapPolicy: Equatable, Sendable {
	public let enabled: Bool
	public let warnAfter: Double
	public let liftAfter: Double

	public init(enabled: Bool, warnAfter: Double = defaultWarnAfter, liftAfter: Double = defaultLiftAfter) {
		self.enabled = enabled
		let ordered = 0 < warnAfter && warnAfter < liftAfter
		self.warnAfter = ordered ? warnAfter : defaultWarnAfter
		self.liftAfter = ordered ? liftAfter : defaultLiftAfter
	}

	public static let attendedDefault = SilenceCapPolicy(enabled: true)
}

/// What the session should do about the silence, right now.
public enum SilenceCapAction: Equatable, Sendable {
	case none
	case warn
	case lift
	/// Whoever acts on this must mark it audibly, or the two silent windows read as one.
	case resuppress
}

public final class SilenceCap {
	private let policy: SilenceCapPolicy
	private var since: Double
	private var warned = false
	private var didLift = false
	private var heardSinceLift = false

	public init(policy: SilenceCapPolicy, now: Double) {
		self.policy = policy
		self.since = now
	}

	public var lifted: Bool { didLift }

	/// Call only for sounds that reach the human past the suppression; silent agent actions must not reset the window.
	public func heard(_ now: Double) {
		since = now
		warned = false
		if didLift { heardSinceLift = true }
	}

	public func check(_ now: Double) -> SilenceCapAction {
		guard policy.enabled else { return .none }
		if didLift {
			// Stays audible until something is heard: re-arming on a timer would mute a human told nothing since the lift.
			guard heardSinceLift else { return .none }
			didLift = false
			heardSinceLift = false
			warned = false
			since = now
			return .resuppress
		}
		let elapsed = now - since
		// The lift is tested first: a loop starved past both thresholds must give the machine back, not warn.
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
