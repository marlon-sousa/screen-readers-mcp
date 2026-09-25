// ROLE: the bridge's own version, sent in every `hello` and never compared on the wire.
// build.sh greps this line to stamp the Info.plists, so it must stay a `let` with a double-quoted literal.
public let voiceOverBridgeVersion = "0.1.0"
