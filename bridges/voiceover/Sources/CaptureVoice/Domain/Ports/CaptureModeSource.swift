// ROLE: port -- is silence in force right now?
//
// Implemented by MarkerFileCaptureModeSource (the marker file entry 13.6
// writes); held by CaptureController, which asks it once per utterance rather
// than caching, because the bridge may lift silence between two utterances and
// the lift must take effect on the next one.
//
// SILENCE IS OPT-IN, AND THAT IS AN INVARIANT RATHER THAN A DEFAULT. On this
// route the provider IS the voice: rendering silence leaves the machine's owner
// unable to hear their own computer. So "no marker" means "speak", and every
// adapter of this port must answer false when it cannot tell.

public protocol CaptureModeSource {
	var isSilent: Bool { get }
}
