// ROLE: adapter -- IMPLEMENTS the ReaderModifierStore domain port. It holds every
// decision about rewriting ONE key of VoiceOver's own preference file without
// taking the other hundred-and-nineteen with it.
//
// BUILT BY: Wiring, once per process. USED BY: ReaderEdgeSetup's modifier rung,
// through the port. HOLDS: the PlistReader and PlistWriter seams, and
// VoiceOverPreferencesFile for the paths -- the same derivation
// `VoiceOverPrefsModifierSetting` reads through, so the reader and the writer
// cannot come to disagree about where the file is.
//
// ============================================================================
// THE HAZARD IS THE OTHER 119 KEYS, AND IT IS NOT HYPOTHETICAL.
// ============================================================================
//
// That file holds pitch, rate, volume, the voice, Quick Nav, the rotor, the
// verbosity settings -- around 120 keys, measured 2026-09-02. `defaults import`
// REPLACES A WHOLE DOMAIN, and this repository has already destroyed a blind
// person's speech settings once by rewriting a preference the coarse way (spec
// 0047, finding 17, and the 2026-09-02 field report's recovery, which cost the
// maintainer his pitch, rate, volume and his premium voice).
//
// So spec 0053 §3.4 is four rules, and all four are implemented below:
//
//   1. READ FRESH at the instant of each write. Never a snapshot taken earlier:
//      a snapshot imported at teardown would revert everything VoiceOver wrote in
//      between -- a Quick Nav toggle the person flipped, a rotor position, the
//      lot.
//   2. MODIFY EXACTLY ONE KEY, in the dictionary that was just read.
//   3. WRITE IT BACK, in the format it was already in.
//   4. READ IT BACK and check it took, AND COUNT THE KEYS EITHER SIDE. A DROP is
//      a failure, loudly. Today's live run was 120 -> 120; that is what
//      "accounted for exactly" looks like, and the count is what makes it
//      checkable rather than hoped for.
//
// A COUNT THAT GREW IS NOT A FAILURE, and the asymmetry is deliberate: VoiceOver
// is running while this happens and writes its own keys whenever it likes, so a
// larger file is the reader doing its job. Only a SHRINKING file is evidence that
// this class ate something.
//
// ============================================================================
// NO SUBPROCESS, AND THAT IS A DEPARTURE FROM `SpeakSelectionVoiceStore`.
// ============================================================================
//
// Spec 0053 §4 first had this class hold a `ProcessRunner`, by analogy with the
// voice store's `defaults export | modify | defaults import`. MEASURED 2026-09-02:
// `defaults export com.apple.VoiceOver4 -` RETURNS AN EMPTY PLIST. VoiceOver's
// settings live in a GROUP CONTAINER and `defaults` does not reach it, so that
// route does not exist for this file at all.
//
// `PlistBuddy` does work on the file, and was declined for one reason: rule 4's
// KEY COUNT is the safety check, and `PlistBuddy -c Print` answers it only as a
// human-readable dump somebody would have to scrape. `PropertyListSerialization`
// answers it exactly and round-trips the types, which is the same reason the
// voice store parses rather than formats.
//
// ============================================================================
// IT WRITES WHILE THE READER IS RUNNING, AND THE CALLER RESTARTS AFTERWARDS.
// ============================================================================
//
// VoiceOver reads this key ONLY AT STARTUP. Measured 2026-09-02: writing
// `SCRVOModifierControlOption` and then pressing `control+option+d` with Marlon
// listening produced nothing; restarting the reader and pressing it again
// produced "we are in dock". So a write on its own changes nothing a session can
// use, and the RESTART is the caller's -- this class knows nothing about it.
//
// The same run measured the write itself as clean: 120 keys before, 120 after,
// one line different, and pitch, rate, voice and Quick Nav untouched.

import Foundation
import VoiceOverBridgeDomain

public final class VoiceOverPrefsModifierStore: ReaderModifierStore {
	/// The values VoiceOver spells its three choices as, keyed by what this bridge
	/// calls them. THE SAME TABLE `VoiceOverPrefsModifierSetting` READS BY, in the
	/// other direction and read from it rather than copied -- two spellings of one
	/// preference is how a reader and a writer come to disagree about somebody's
	/// keyboard.
	static func recordedValue(for setting: ModifierSetting) -> String? {
		VoiceOverPrefsModifierSetting.values.first { $0.value == setting }?.key
	}

	private let reader: any PlistReader
	private let writer: any PlistWriter
	private let home: String

	public init(reader: any PlistReader, writer: any PlistWriter, home: String) {
		self.reader = reader
		self.writer = writer
		self.home = home
	}

	public func store(_ setting: ModifierSetting) throws {
		// `unknown` IS NOT A VALUE. It is the answer "I could not read the file",
		// and writing it would mean inventing a modifier for somebody.
		guard let value = VoiceOverPrefsModifierStore.recordedValue(for: setting) else {
			throw ReaderModifierStoreError(
				"'\(setting.rawValue)' is not a VoiceOver modifier this bridge can write: it is what "
					+ "this bridge says when it could not READ the setting, and a modifier nobody knows "
					+ "is not one to store")
		}

		// NEWEST LOCATION FIRST, and the first file that can be READ is the one
		// written -- the same rule, in the same order, as the read-only setting
		// beside this class. A machine upgraded to Sequoia can still carry the
		// pre-Sequoia file, and the reader is no longer reading that one.
		let paths = VoiceOverPreferencesFile.candidates(home: home)
		guard let path = paths.first(where: { reader.read(at: $0) != nil }),
			var preferences = reader.read(at: path),
			let format = reader.format(at: path)
		else {
			throw ReaderModifierStoreError(
				"VoiceOver's preferences could not be read, so there is nothing to rewrite safely. "
					+ "Looked in: \(paths.joined(separator: ", "))")
		}

		// RULE 4's FIRST HALF: what was there before this class touched anything.
		let countBefore = preferences.count
		// RULE 2: exactly one key.
		preferences[VoiceOverPrefsModifierSetting.preferencesKey] = value

		do {
			// RULE 3: back into the file, in the format it was already in.
			try writer.write(preferences, to: path, format: format)
		} catch let failure as PlistWriteFailure {
			throw ReaderModifierStoreError(
				"the VoiceOver modifier could not be written to \(path): \(failure.description)")
		}

		// RULE 4's SECOND HALF: it is not written until the file says so. A write
		// that silently did not take is exactly how spec 0047's finding 17 stood as
		// a fact for weeks.
		guard let confirmed = reader.read(at: path) else {
			throw ReaderModifierStoreError(
				"the VoiceOver modifier was written to \(path) and the file could not be read back, so "
					+ "there is no evidence it took")
		}
		guard confirmed[VoiceOverPrefsModifierSetting.preferencesKey] as? String == value else {
			throw ReaderModifierStoreError(
				"the VoiceOver modifier was written to \(path) and reading it back says "
					+ "'\(confirmed[VoiceOverPrefsModifierSetting.preferencesKey] ?? "nothing")' rather "
					+ "than '\(value)'")
		}
		// A FILE THAT GREW IS THE READER DOING ITS JOB; a file that SHRANK is this
		// class having eaten something, and it is reported as loudly as it deserves.
		guard confirmed.count >= countBefore else {
			throw ReaderModifierStoreError(
				"writing the VoiceOver modifier to \(path) LOST SETTINGS: \(countBefore) keys before "
					+ "and \(confirmed.count) after. That file holds this person's pitch, rate, voice and "
					+ "Quick Nav; treat it as damaged and restore it from a Time Machine backup rather "
					+ "than starting another session")
		}
	}
}
