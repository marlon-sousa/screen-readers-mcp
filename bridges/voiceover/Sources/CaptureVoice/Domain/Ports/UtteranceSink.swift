// ROLE: port where every captured utterance and every other observation of the provider goes.
// IMPLEMENTED BY: ContainerFileUtteranceSink, OsLogUtteranceSink and FanOutUtteranceSink.

public enum FieldValue: Equatable, Sendable {
	case text(String)
	case count(Int)
	case number(Double)
	case flag(Bool)
}

/// The `kind` strings are parsed by the bridge: changing one is a wire change, not a rename.
public struct CaptureEvent: Equatable, Sendable {
	public enum Kind: String, Sendable {
		case audioUnitCreated = "audio-unit-created"
		case allocateRenderResources = "allocate-render-resources"
		/// Its absence tells "the extension never ran" apart from "VoiceOver ignored it".
		case speechVoicesRead = "speech-voices-read"
		case synthesize
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
