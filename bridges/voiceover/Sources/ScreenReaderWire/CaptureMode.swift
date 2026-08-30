// ROLE: entity -- the speech-capture mode a session chooses at `hello` time.
//
// Pure. Carried by HelloParams and HelloResult; the adapter factory (entry 13.4)
// is the only place that decides what a mode MEANS, because the mode is not
// known until `hello` has been answered.
//
// A closed set, so an unknown value is a validation error rather than a silently
// accepted third mode -- unlike Capability, which must tolerate strings a newer
// peer invents. The difference is direction: a mode is an INSTRUCTION this
// bridge has to carry out, and one it cannot recognise it must refuse.

public enum CaptureMode: String, Codable, CaseIterable, Sendable {
	/// The user hears nothing; on macOS the capture voice renders silence and
	/// the utterance still reaches the bridge (spec 0041).
	case silent
	/// The reader keeps talking and the bridge reads along.
	case live
}
