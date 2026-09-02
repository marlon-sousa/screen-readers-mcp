// ROLE: entity -- the five rungs a handshake climbs, and the ONE place a rung's
// failure sentence is composed. Pure.
//
// USED BY: ReaderEdgeSetup, which is the controller that climbs them. BUILT BY:
// nobody -- it is an enumeration.
//
// WHY IT IS A TYPE AND NOT FIVE STRINGS IN A CONTROLLER. Until 13.20 `hello`
// only ever REPORTED where `ProviderState` had stopped; now it climbs, and a
// climb that can stop in five places is a climb that can grow five different
// shapes of apology. One of them would say what is wrong and not what to do
// about it, and that is the shape this repo has decided against everywhere else
// it makes a named failure: `ReaderCondition`, `Precondition` and `Permission`
// each pair a diagnosis with its recovery in one `described` rendering, and this
// is the same rule applied to a SEQUENCE rather than to a condition.
//
// THE AUDIENCE IS THE AGENT, WHICH IS WHY `agentMustDo` IS SPELLED THAT WAY.
// `Permission.recovery` and `ReaderCondition.recovery` are written for the human
// at the machine -- which System Settings pane, which command to run. Nobody is
// necessarily at this machine. What reads a failed `hello` is an agent, and the
// only actions an agent has are: tell the human something, and connect again. So
// the rung's sentence carries the human-facing recovery INSIDE an instruction
// the agent can actually carry out, rather than handing an agent a sentence
// addressed to somebody who may not be in the room.
//
// THE ORDER OF THE CASES IS THE ORDER OF THE CLIMB, and it is load-bearing to
// read it that way: permissions before anything is touched, a reader before
// anything is asked of one, registration before selection, and the proof last,
// because it is the only rung that is EVIDENCE rather than inference.

public enum SetupRung: String, Equatable, Sendable, CaseIterable {
	/// This process is allowed to drive the machine at all. READ, never asked
	/// for -- see ReaderEdgeSetup, and PermissionBroker's header for why a
	/// handshake that raised a consent dialog would be a handshake that hangs.
	case permissions

	/// VoiceOver is running and answers its own name. The bridge may ACTIVATE it
	/// to get there; it may never restart it.
	case readerRunning

	/// The capture voice's extension is registered with the system. MACHINE
	/// state: made once, and never undone at teardown.
	case registration

	/// VoiceOver is set to speak with the capture voice. SESSION state: put back
	/// on every teardown path.
	case voiceSelection

	/// An utterance actually arrived. The only rung that is evidence.
	case captureProof

	/// What this rung establishes, in the sentence that reads after "could not".
	public var summary: String {
		switch self {
		case .permissions:
			return "confirm this process is allowed to drive this machine"
		case .readerRunning:
			return "get VoiceOver running and answering"
		case .registration:
			return "register the capture voice's extension with the system"
		case .voiceSelection:
			return "point VoiceOver at the capture voice"
		case .captureProof:
			return "prove that what the reader says actually reaches this bridge"
		}
	}

	/// The one rendering of a stopped climb: which rung, what is wrong, and what
	/// the AGENT must do about it.
	///
	/// One function so the three halves cannot travel apart, and so a rung added
	/// later cannot quietly answer in a different voice.
	public func failed(_ because: String, agentMustDo action: String) -> String {
		"this bridge could not establish a session on this machine -- it could not \(summary). "
			+ "Setup step '\(rawValue)': \(because) WHAT YOU MUST DO: \(action)"
	}
}
