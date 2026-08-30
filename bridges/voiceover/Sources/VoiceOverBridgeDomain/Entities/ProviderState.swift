// ROLE: entity -- the capture voice's lifecycle as a state machine, and pure.
//
// FIVE STATES RATHER THAN ONE BOOLEAN, and the reason is the whole point of the
// type: EACH STATE HAS A DIFFERENT DIAGNOSIS AND A DIFFERENT INSTRUCTION FOR THE
// HUMAN. "Registered but not published" is a build problem; "published but not
// selected" is a settings problem the bridge now fixes itself; "selected but not
// capturing" is a dead provider that only a reader restart re-binds. A boolean
// would collapse three different answers into one unhelpful one.
//
// BUILT BY: PluginKitProviderLifecycle, from three independent signals -- what
// pluginkit lists, what the system publishes, and what the speech domain says
// VoiceOver is speaking with. PROMOTED BY: whoever holds the evidence of capture,
// through `observing(captured:)`, because "is it actually capturing?" is a
// question only the session's own buffer can answer (spec 0047, finding 18: the
// reliable signal is utterances arriving, never audio).
// USED BY: the Hello handler and the two waiting speech handlers, which turn a
// state into named ReaderConditions rather than into an empty read-back.
//
// THE ORDER IS A RANKING, and `canCapture` is where it earns its keep: everything
// from `selected` up can capture, everything below it cannot, and that single
// comparison is what a handshake gates a silent session on.

public enum ProviderState: String, Equatable, Sendable, Comparable, CaseIterable {
	/// pluginkit does not list the extension at all.
	case notRegistered
	/// pluginkit lists it, but the system is not publishing its voice.
	case registered
	/// The voice exists system-wide. Whether VOICEOVER offers it is a different
	/// question and an unanswerable one -- see `conditions`.
	case published
	/// VoiceOver's own selected voice is ours. Nothing has been captured yet,
	/// which at the start of a session is entirely normal.
	case selected
	/// Utterances have arrived. The only state that is evidence rather than
	/// inference.
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

	/// Whether this bridge can capture, silence or read back anything at all.
	public var canCapture: Bool { self >= .selected }

	/// What this state means, in one sentence.
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

	/// The named conditions that are live in this state.
	///
	/// EMPTY IS AN ANSWER AND `selected` IS DELIBERATELY EMPTY. A session that has
	/// just selected the voice and heard nothing yet is healthy, not broken, and
	/// reporting two possible faults at every handshake would train a reader to
	/// ignore them. The ambiguity of "selected, and still nothing" belongs to
	/// whoever waited and got nothing -- see `unheardConditions`.
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

	/// What to report when something WAITED for speech and got none.
	///
	/// This is the case spec 0047's findings 6 and 18 make undecidable from
	/// outside the reader: with the voice selected and nothing arriving, the
	/// provider may have died, or VoiceOver may never have offered the voice, and
	/// no signal available here separates them. So BOTH are named, with both
	/// recoveries, which is honest -- where "found: false" would have been a
	/// confident wrong answer.
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

	/// The one rendering of a state for an agent or a transcript: what it means,
	/// then every condition it puts in question, each with its own recovery.
	///
	/// ONE FUNCTION SO THE HALVES CANNOT TRAVEL APART. A diagnosis without its
	/// recovery is a complaint, and a recovery without its diagnosis is a ritual.
	public var report: String {
		([diagnosis] + conditions.map(\.described)).joined(separator: " ")
	}

	/// Promote `selected` to `capturing` on the one piece of evidence that counts.
	///
	/// Pure, so the rule lives here rather than in whichever caller happens to
	/// hold a buffer. Nothing below `selected` is promoted: utterances cannot have
	/// arrived through a voice the reader is not using, so evidence that says
	/// otherwise is stale rather than authoritative.
	public func observing(captured: Bool) -> ProviderState {
		guard captured, self >= .selected else { return self }
		return .capturing
	}
}
