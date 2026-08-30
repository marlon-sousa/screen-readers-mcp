// ROLE: adapter -- IMPLEMENTS the AdapterFactory domain port. THE ONLY PLACE
// THAT KNOWS WHAT A CAPTURE MODE MEANS, because the mode is not known until
// `hello` has been read and this is what `hello` calls.
//
// BUILT BY: Wiring. CALLED BY: the Hello handler, once per session.
//
// TODAY IT BUILDS AN EMPTY SET AND REFUSES ONE MODE, and both halves are the
// entry working as designed rather than a stub:
//
// SILENT IS REFUSED UNTIL 13.6, and this is the one real decision in the file --
// which is also what makes it an adapter with a test rather than a leaf. `silent`
// is not a preference, it is a PROMISE ABOUT A HUMAN'S EARS: the reader keeps
// talking, the human hears nothing, and the agent reads what was said. Nothing
// in this build can keep any part of that promise -- the marker file that mutes
// the capture voice arrives with 13.6 and the capture feed with 13.5 -- so a
// session established in silent mode would report `mode: silent` back to an
// agent that would then believe speech was being captured and withheld, when in
// fact the machine is talking normally and nothing is being recorded.
//
// REFUSING IS THE CHEAPER ERROR. A refused handshake names the entry that is
// missing, in one line, at the moment somebody asks for it. The alternative is a
// session that looks established and quietly means something else, which is the
// failure this repo's capability gate exists to prevent -- and 13.6 removes the
// refusal in the same commit that makes the promise keepable.
//
// LIVE IS THE MODE THAT WORKS: the reader talks, and this build simply reads
// nothing back yet -- which is what an empty capability list already says.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class VoiceOverAdapterFactory: AdapterFactory {
	public init() {}

	public func build(mode: CaptureMode) throws -> AdapterSet {
		switch mode {
		case .live:
			return AdapterSet(mode: mode)
		case .silent:
			throw AdapterFactoryError(
				"this bridge cannot run a silent session yet: suppressing the capture voice "
					+ "arrives with board entry 13.6. Connect in live mode."
			)
		}
	}
}
