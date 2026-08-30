// ROLE: adapter -- IMPLEMENTS the AdapterFactory domain port. THE ONLY PLACE
// THAT KNOWS WHAT A CAPTURE MODE MEANS, because the mode is not known until
// `hello` has been read and this is what `hello` calls.
//
// BUILT BY: Wiring. CALLED BY: the Hello handler, once per session.
//
// TODAY IT BUILDS THE CAPTURE FEED AND REFUSES ONE MODE, and both halves are the
// entry working as designed rather than a stub:
//
// SILENT IS STILL REFUSED UNTIL 13.6, and 13.5 does not soften it. `silent` is
// not a preference, it is a PROMISE ABOUT A HUMAN'S EARS: the reader keeps
// talking, the human hears nothing, and the agent reads what was said. This
// build now keeps the LAST clause and neither of the others -- the marker file
// that mutes the capture voice arrives with 13.6 -- so a session established in
// silent mode would report `mode: silent` back to an agent that would then
// believe speech was being withheld, while the machine talked normally. Half a
// promise is the more dangerous kind: capture that works is exactly what would
// make the silence look plausible.
//
// REFUSING IS THE CHEAPER ERROR. A refused handshake names the entry that is
// missing, in one line, at the moment somebody asks for it. The alternative is a
// session that looks established and quietly means something else, which is the
// failure this repo's capability gate exists to prevent -- and 13.6 removes the
// refusal in the same commit that makes the promise keepable.
//
// LIVE IS THE MODE THAT WORKS: the reader talks and the bridge reads back what
// it said, over the extension's container file -- the only door out of a speech
// provider (spec 0041, B1). WHICH FILE is not decided here: the path is a value
// Wiring resolves, so this class stays the place that knows what a MODE means
// and not the place that knows where anything lives.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class VoiceOverAdapterFactory: AdapterFactory {
	private let capturePath: String

	/// `capturePath` is where the capture voice appends its feed. Passed in with
	/// no default, deliberately: a default here would be an environment read
	/// hidden in a signature, and Wiring is the one place in this bridge that
	/// reads the environment.
	public init(capturePath: String) {
		self.capturePath = capturePath
	}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		switch mode {
		case .live:
			// A source per session, not per process: a tailer shared between two
			// sessions would deliver each utterance to whichever buffer read first.
			return AdapterSet(
				mode: mode,
				speechSource: ContainerFileSpeechSource(tailer: FileLineTailer(path: capturePath))
			)
		case .silent:
			throw AdapterFactoryError(
				"this bridge cannot run a silent session yet: suppressing the capture voice "
					+ "arrives with board entry 13.6. Connect in live mode."
			)
		}
	}
}
