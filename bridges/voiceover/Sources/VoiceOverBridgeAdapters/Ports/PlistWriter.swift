// ROLE: adapter seam -- write a property list back to a path.
//
// NOT A DOMAIN PORT: the domain asks for a VoiceOver modifier to be stored
// (`ReaderModifierStore`) and has no idea that the answer is a dictionary
// serialized into a file inside a group container.
//
// IMPLEMENTED BY: FilePlistWriter (a leaf) and FakePlistWriter (Tests/Fakes).
// USED BY: VoiceOverPrefsModifierStore, which is the one place that decides WHAT
// to write and checks that it landed.
//
// IT IS THE WRITE HALF OF `PlistReader`, AND IT IS A SEPARATE SEAM FOR THE REASON
// EVERY OTHER PAIR HERE IS SEPARATED. `VoiceOverPrefsScriptingSetting` and
// `VoiceOverPrefsModifierSetting` both hold a `PlistReader` and both promise in
// their headers that they never write. Handing them a seam that can write would
// make those promises a matter of discipline; two seams makes them a matter of
// what they were constructed with.
//
// ============================================================================
// WHY NOT `defaults`, WHICH IS HOW THE VOICE IS WRITTEN -- MEASURED 2026-09-02.
// ============================================================================
//
// `SpeakSelectionVoiceStore` reaches its domain with `defaults export
// com.apple.SpeakSelection -` and writes it back with `defaults import`. The same
// call on `com.apple.VoiceOver4` RETURNS AN EMPTY PLIST: VoiceOver's settings
// live in a GROUP CONTAINER --
// `~/Library/Group Containers/group.com.apple.VoiceOver/…` -- and `defaults` does
// not reach it. So there is no `defaults` route to this file, and the technique
// has to address the file itself.
//
// `PlistBuddy` DOES work on it, and was declined. The KEY COUNT either side of a
// write is the safety check spec 0053 §3.4 rests on, and `PlistBuddy -c Print`
// answers it only as a human-readable dump somebody would have to scrape.
// `PropertyListSerialization` answers it exactly, round-trips the types for the
// same reason the voice store parses rather than formats, and lets the file be
// written back in the format it was already in.
//
// THE FORMAT TRAVELS, and that is why `write` takes one. VoiceOver's file is
// BINARY on this machine; serializing it back as XML would leave a file macOS
// still reads and every instrument in this repository suddenly disagrees with,
// which is the shape of a diff nobody can review and a "nothing changed" that is
// false.

import Foundation

/// A plist that could not be written.
public struct PlistWriteFailure: Error, Equatable, CustomStringConvertible {
	public let description: String

	public init(_ description: String) {
		self.description = description
	}
}

public protocol PlistWriter: AnyObject {
	/// Serialize `plist` in `format` and replace the file at `path`.
	///
	/// ATOMIC, and that is a requirement rather than a preference: this file holds
	/// around 120 of somebody's screen reader settings, and a partial write is a
	/// reader that comes up at its factory defaults. The leaf uses an atomic
	/// replace so a failure leaves the previous file exactly as it was.
	func write(_ plist: [String: Any], to path: String, format: PropertyListSerialization.PropertyListFormat) throws
}
