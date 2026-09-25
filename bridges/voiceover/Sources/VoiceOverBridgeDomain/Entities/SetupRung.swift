// ROLE: entity -- the five rungs a handshake climbs, and the one place a rung's failure sentence is composed.
// USED BY: ReaderEdgeSetup, the controller that climbs them.

public enum SetupRung: String, Equatable, Sendable, CaseIterable {
	/// Read, never requested: a handshake that raised a consent dialog would hang.
	case permissions

	case readerRunning

	/// Machine state: made once, and never undone at teardown.
	case registration

	/// Session state: put back on every teardown path.
	case voiceSelection

	case captureProof

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

	public func failed(_ because: String, agentMustDo action: String) -> String {
		"this bridge could not establish a session on this machine -- it could not \(summary). "
			+ "Setup step '\(rawValue)': \(because) WHAT YOU MUST DO: \(action)"
	}
}
