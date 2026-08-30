// ROLE: entity -- the wire version this binding was written against, and the
// rule for comparing it with a peer's.
//
// Pure, and held by nothing: the `hello` handler (entry 13.4) asks it, and the
// drift gate reads the number out of this file and compares it with
// `protocolVersion` in specs/wire/v1/schema.json.
//
// WHAT IS COMPARED IS THE PROTOCOL VERSION, NEVER THE COMPONENTS' OWN VERSIONS.
// The server, the NVDA bridge and this bridge release on their own cadences
// (spec 0012); the only thing that must match is the contract they speak.
//
// A SET RATHER THAN A CONSTANT COMPARED WITH ==, mirroring the Go binding's
// SupportedVersions() for the same reason it does: spec 0013 leaves the
// hub-versus-lockstep question open, and accepting a second version must be a
// change to data, not to control flow.

public enum ProtocolVersion {
	/// The version this binding was written against.
	public static let current = 1

	/// Every version this bridge can talk to. One today, on purpose.
	public static let supported: Set<Int> = [current]

	/// Whether a peer announcing `version` can be talked to.
	public static func supports(_ version: Int) -> Bool {
		supported.contains(version)
	}
}
