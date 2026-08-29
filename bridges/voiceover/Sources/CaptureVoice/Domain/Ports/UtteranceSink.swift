// ROLE: port -- TEXT OUTPUT. Where a captured utterance, and everything else the
// provider observes, goes.
//
// Implemented by ContainerFileUtteranceSink (JSON lines into the extension's own
// container, which is the route the bridge reads), by OsLogUtteranceSink (the
// route that works when the file one does not), and by FanOutUtteranceSink, which
// is how "emit two ways" stays a composition rather than an `if`. Held by
// CaptureController, which is the only thing that calls it.
//
// WHY A PORT AT ALL, when the spike simply wrote both routes inline: the spike
// emits two ways ON PURPOSE -- os_log survives a sandbox denial that the file
// write does not, and the file is the only door out of the extension because a
// network-entitled speech provider is silently skipped by macOS (spec 0041, B1).
// Both must keep working, so both are adapters behind one port rather than two
// branches nobody can test.
//
// THE VALUE TYPES LIVE HERE, with the port that owns them, per the repo's rule
// that a DTO lives in the file of the port it belongs to.

/// One field of one observation.
///
/// A closed set of JSON-shaped scalars rather than `Any`: the domain says WHAT it
/// observed and the adapters decide how to render it, so no JSON vocabulary
/// reaches the domain and no `as?` cast decides an event's meaning at the edge.
public enum FieldValue: Equatable, Sendable {
	case text(String)
	case count(Int)
	case number(Double)
	case flag(Bool)
}

/// Something the provider saw, named and with its evidence attached.
///
/// The `kind` strings are the ones the spike wrote and spec 0041 measured
/// against, and entry 13.5 will parse: changing one is a wire change to the
/// bridge, not a rename.
public struct CaptureEvent: Equatable, Sendable {
	public enum Kind: String, Sendable {
		/// The audio unit was constructed -- which is also the only place that can
		/// report whether the background CPU band was escaped.
		case audioUnitCreated = "audio-unit-created"
		/// The host settled the output format, which is not necessarily the one
		/// the unit declared.
		case allocateRenderResources = "allocate-render-resources"
		/// The system read our voice list. Its absence is how "the extension never
		/// ran" is told apart from "VoiceOver ignored it".
		case speechVoicesRead = "speech-voices-read"
		/// AN UTTERANCE. The event the whole route exists for.
		case synthesize
		/// VoiceOver cancels before EVERY new utterance, so this is the normal
		/// path and not a fault (spec 0041, A3). It carries the timing and ring
		/// counters, which is where a glitch is measured at its source.
		case cancel
	}

	public let kind: Kind
	public let fields: [String: FieldValue]

	public init(kind: Kind, fields: [String: FieldValue]) {
		self.kind = kind
		self.fields = fields
	}
}

public protocol UtteranceSink: AnyObject {
	func emit(_ event: CaptureEvent)
}
