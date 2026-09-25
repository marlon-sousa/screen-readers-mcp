// ROLE: entity, the capture voice's lifecycle as a pure state machine.
// BUILT BY: PluginKitProviderLifecycle, from pluginkit, the published voices and VoiceOver's
// speech domain.
// PROMOTED BY: whoever holds evidence of capture, through `observing(captured:)`.
// USED BY: the Hello handler and the two waiting speech handlers.

public enum ProviderState: String, Equatable, Sendable, Comparable, CaseIterable {
	case notRegistered
	case registered
	/// The voice exists system-wide; whether VoiceOver offers it cannot be answered.
	case published
	case selected
	/// Utterances have arrived: the only state that is evidence rather than inference.
	case capturing

	private var rank: Int {
		switch self {
		case .notRegistered: return 0
		case .registered: return 1
		case .published: return 2
		case .selected: return 3
		case .capturing: return 4
		}
	}

	public static func < (lhs: ProviderState, rhs: ProviderState) -> Bool {
		lhs.rank < rhs.rank
	}

	public var canCapture: Bool { self >= .selected }

	public var diagnosis: String {
		switch self {
		case .notRegistered:
			return "the capture voice's extension is not registered with the system"
		case .registered:
			return "the extension is registered, but its voice is not published system-wide"
		case .published:
			return "the voice is published system-wide, but VoiceOver is not speaking with it"
		case .selected:
			return "VoiceOver is set to the capture voice, and nothing has been captured yet"
		case .capturing:
			return "VoiceOver is speaking through the capture voice and utterances are arriving"
		}
	}

	/// `selected` is deliberately empty: a session that has heard nothing yet is healthy.
	public var conditions: [ReaderCondition] {
		switch self {
		case .notRegistered, .registered:
			return [.providerNotRunning]
		case .published:
			return [.captureVoiceNotSelected, .captureVoiceNotOfferedByReader]
		case .selected, .capturing:
			return []
		}
	}

	/// With the voice selected and nothing arriving, a dead provider and a voice VoiceOver never offered
	/// cannot be told apart from here, so both are named.
	public var unheardConditions: [ReaderCondition] {
		switch self {
		case .selected:
			return [.providerNotRunning, .captureVoiceNotOfferedByReader]
		case .capturing:
			return []
		default:
			return conditions
		}
	}

	public var report: String {
		([diagnosis] + conditions.map(\.described)).joined(separator: " ")
	}

	/// An utterance that arrived is `capturing`, whatever the inferred state said: the inference cannot
	/// be answered when AppleScript control is off.
	public func observing(captured: Bool) -> ProviderState {
		guard captured else { return self }
		return .capturing
	}
}
