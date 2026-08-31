// ROLE: the bridge's own version, declared ONCE.
//
// READ BY: `Wiring.bridgeVersion`, which puts it in every `hello`; and by
// `build.sh`, which greps this file to stamp `CFBundleShortVersionString` into
// the three Info.plists it writes. Those are the only two readers, and they are
// why this is a file of its own rather than a constant inside Wiring: a build
// script that greps a 300-line composition root is a build script that breaks
// when somebody reformats it.
//
// IT USED TO BE A LITERAL IN TWO PLACES THAT DID NOT AGREE. `Wiring` said
// `0.1.0-dev` while every plist said `1.0`, so the version an agent read in
// `hello` and the version macOS showed in Get Info were different numbers with
// no relationship. Wiring's own header said 13.11 owned packaging and was where
// this stopped being a literal; this is that.
//
// SWIFT IS THE SOURCE AND THE SHELL DERIVES, which is lane 1's shape (buildVars.py
// declares `addon_version` and scons reads it) for lane 1's reason: the value
// belongs with the code that ships it, and a build script is the thing most
// likely to be run by something other than a developer.
//
// WHAT IT IS NOT: anything the wire compares. `hello` sends it for the human
// reading a transcript, and what must MATCH between two halves is the protocol
// version and never the components' own (spec 0012) -- the server, the NVDA
// bridge and this one release on their own cadences. Nothing may gate on this
// string.
//
// THE FORMAT IS `MAJOR.MINOR.PATCH`, and build.sh's extraction depends on the
// line below keeping its shape: a `let` whose value is a double-quoted literal.
// Changing the declaration's syntax means changing the grep in build.sh, in the
// same commit.

/// This bridge's own version. See the header: it travels, and it is never
/// compared.
public let voiceOverBridgeVersion = "0.1.0"
