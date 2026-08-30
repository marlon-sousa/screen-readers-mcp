// ROLE: adapter -- IMPLEMENTS the AdapterFactory domain port. THE ONLY PLACE
// THAT KNOWS WHAT A CAPTURE MODE MEANS, because the mode is not known until
// `hello` has been read and this is what `hello` calls.
//
// BUILT BY: Wiring. CALLED BY: the Hello handler, once per session.
//
// IT NO LONGER REFUSES ANYTHING, AND THAT IS 13.6. Until this entry a silent
// session was refused outright, with a named test that had to be deleted by
// whoever made the promise keepable -- because `silent` is not a preference, it
// is a PROMISE ABOUT A HUMAN'S EARS: the reader keeps talking, the human hears
// nothing, and the agent reads what was said. 13.5 could keep the last clause
// and neither of the others, and half a promise is the more dangerous kind:
// capture that works is exactly what would have made a claimed silence look
// plausible.
//
// WHAT MAKES IT KEEPABLE NOW is the marker file this factory builds -- read by
// the capture voice once per utterance, so a lift lands on the very next thing
// VoiceOver says -- and hard invariant 3 in its macOS form, which is not a
// teardown path at all but an EXPIRY: see SilenceControl and
// MarkerFileSilenceControl for why a `finally` was never enough here.
//
// THE REFUSAL MOVED RATHER THAN VANISHING. A mode is still an instruction a
// bridge may be unable to carry out, and `silent` now fails at the HANDSHAKE
// when the reader edge cannot deliver it -- see the Hello handler, which asks
// the provider lifecycle and refuses by NAMED CONDITION with its recovery. That
// is the same argument in the place that can now actually answer the question:
// this factory builds collaborators, and only the handshake knows whether the
// machine is in a state where they mean anything.
//
// BOTH MODES GET THE SAME THREE COLLABORATORS, and the symmetry is the route's:
// capture is identical either way, the marker channel carries the user's own
// voice in both (Rule 0), and the provider lifecycle answers the same questions.
// Only what the handshake ASKS for differs.
//
// WHAT IS NOT DECIDED HERE: where any of it lives. The capture path, the marker
// path and the lifecycle are values Wiring resolves, so this class stays the
// place that knows what a MODE means and not the place that knows where files
// are.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class VoiceOverAdapterFactory: AdapterFactory {
	private let capturePath: String
	private let markerPath: String
	private let lifecycle: any ProviderLifecycle

	/// `capturePath` is where the capture voice appends its feed; `markerPath` is
	/// where it reads what the bridge is asking of it. Passed in with no defaults,
	/// deliberately: a default here would be an environment read hidden in a
	/// signature, and Wiring is the one place in this bridge that reads the
	/// environment.
	///
	/// The lifecycle is passed in rather than built here because it is the one
	/// collaborator that is NOT per-session: it describes the machine, the same
	/// answer for every session, and building one per handshake would run
	/// `pluginkit` for no reason.
	public init(capturePath: String, markerPath: String, lifecycle: any ProviderLifecycle) {
		self.capturePath = capturePath
		self.markerPath = markerPath
		self.lifecycle = lifecycle
	}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		// A source and a silence control PER SESSION, not per process: a tailer
		// shared between two sessions would deliver each utterance to whichever
		// buffer read first, and a marker shared between them would let one
		// session's teardown lift the other's silence.
		AdapterSet(
			mode: mode,
			speechSource: ContainerFileSpeechSource(tailer: FileLineTailer(path: capturePath)),
			silenceControl: MarkerFileSilenceControl(path: markerPath),
			providerLifecycle: lifecycle
		)
	}
}
