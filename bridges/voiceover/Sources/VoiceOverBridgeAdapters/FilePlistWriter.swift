// ROLE: LEAF adapter -- IMPLEMENTS the PlistWriter seam over
// `PropertyListSerialization` and an atomic file replace. Real files, no
// decisions.
//
// BUILT BY: Wiring. USED BY: VoiceOverPrefsModifierStore, which holds every
// decision about WHAT is written and checks that it landed.
//
// NO TEST FILE (leaf): there is nothing here that
// `PropertyListSerialization.data(fromPropertyList:)` and `Data.write(options:
// .atomic)` do not already guarantee. If you are adding a test here, a decision
// has landed in a leaf and belongs one layer up.
//
// THE WRITE IS ATOMIC, AND THAT IS A REQUIREMENT RATHER THAN A HABIT. The file
// this replaces holds around 120 of somebody's screen reader settings -- pitch,
// rate, voice, Quick Nav, the rotor. A partial write is a blind person's reader
// coming up at its factory defaults, which is a worse outcome than any failure
// this class can return. `.atomic` writes a temporary file and renames it, so a
// failure leaves the previous file byte for byte as it was.
//
// IT DOES NOT CHOOSE THE FORMAT. The caller passes one, read from the file it is
// about to replace -- see the seam's header for why a silently re-formatted plist
// is the kind of change nobody can review.

import Foundation

public final class FilePlistWriter: PlistWriter {
	public init() {}

	public func write(
		_ plist: [String: Any], to path: String,
		format: PropertyListSerialization.PropertyListFormat
	) throws {
		let data: Data
		do {
			data = try PropertyListSerialization.data(
				fromPropertyList: plist, format: format, options: 0)
		} catch {
			throw PlistWriteFailure("could not serialize the property list: \(error)")
		}
		do {
			try data.write(to: URL(fileURLWithPath: path), options: .atomic)
		} catch {
			throw PlistWriteFailure("could not write \(path): \(error)")
		}
	}
}
